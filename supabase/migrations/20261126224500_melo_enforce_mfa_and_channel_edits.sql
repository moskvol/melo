create function private.melo_mfa_ok() returns boolean language sql stable security definer set search_path='' as $$
 select auth.uid() is not null and (coalesce(auth.jwt()->>'aal','')='aal2' or not exists(select 1 from auth.mfa_factors f where f.user_id=auth.uid() and f.status='verified'))
$$;
revoke all on function private.melo_mfa_ok() from public,anon,authenticated;
grant execute on function private.melo_mfa_ok() to authenticated;
create policy melo_require_mfa on public.blocks as restrictive for all to authenticated using((select private.melo_mfa_ok())) with check((select private.melo_mfa_ok()));
create policy melo_require_mfa on public.conversation_members as restrictive for all to authenticated using((select private.melo_mfa_ok())) with check((select private.melo_mfa_ok()));
create policy melo_require_mfa on public.conversations as restrictive for all to authenticated using((select private.melo_mfa_ok())) with check((select private.melo_mfa_ok()));
create policy melo_require_mfa on public.melo_admins as restrictive for all to authenticated using((select private.melo_mfa_ok())) with check((select private.melo_mfa_ok()));
create policy melo_require_mfa on public.melo_bots as restrictive for all to authenticated using((select private.melo_mfa_ok())) with check((select private.melo_mfa_ok()));
create policy melo_require_mfa on public.melo_channel_posts as restrictive for all to authenticated using((select private.melo_mfa_ok())) with check((select private.melo_mfa_ok()));
create policy melo_require_mfa on public.melo_channel_subscriptions as restrictive for all to authenticated using((select private.melo_mfa_ok())) with check((select private.melo_mfa_ok()));
create policy melo_require_mfa on public.melo_channels as restrictive for all to authenticated using((select private.melo_mfa_ok())) with check((select private.melo_mfa_ok()));
create policy melo_require_mfa on public.melo_collectibles as restrictive for all to authenticated using((select private.melo_mfa_ok())) with check((select private.melo_mfa_ok()));
create policy melo_require_mfa on public.melo_credits as restrictive for all to authenticated using((select private.melo_mfa_ok())) with check((select private.melo_mfa_ok()));
create policy melo_require_mfa on public.melo_name_requests as restrictive for all to authenticated using((select private.melo_mfa_ok())) with check((select private.melo_mfa_ok()));
create policy melo_require_mfa on public.melo_post_comments as restrictive for all to authenticated using((select private.melo_mfa_ok())) with check((select private.melo_mfa_ok()));
create policy melo_require_mfa on public.melo_post_reactions as restrictive for all to authenticated using((select private.melo_mfa_ok())) with check((select private.melo_mfa_ok()));
create policy melo_require_mfa on public.melo_post_views as restrictive for all to authenticated using((select private.melo_mfa_ok())) with check((select private.melo_mfa_ok()));
create policy melo_require_mfa on public.melo_premium_names as restrictive for all to authenticated using((select private.melo_mfa_ok())) with check((select private.melo_mfa_ok()));
create policy melo_require_mfa on public.melo_reports as restrictive for all to authenticated using((select private.melo_mfa_ok())) with check((select private.melo_mfa_ok()));
create policy melo_require_mfa on public.melo_stories as restrictive for all to authenticated using((select private.melo_mfa_ok())) with check((select private.melo_mfa_ok()));
create policy melo_require_mfa on public.messages as restrictive for all to authenticated using((select private.melo_mfa_ok())) with check((select private.melo_mfa_ok()));
create policy melo_require_mfa on public.profiles as restrictive for all to authenticated using((select private.melo_mfa_ok())) with check((select private.melo_mfa_ok()));
create policy melo_require_mfa on public.reactions as restrictive for all to authenticated using((select private.melo_mfa_ok())) with check((select private.melo_mfa_ok()));
create policy melo_require_mfa on storage.objects as restrictive for all to authenticated using((select private.melo_mfa_ok())) with check((select private.melo_mfa_ok()));
CREATE OR REPLACE FUNCTION public.create_direct_chat(other_user uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare chat_id uuid; me uuid := auth.uid();
begin
 if not private.melo_mfa_ok() then raise exception 'MFA verification required' using errcode='42501'; end if;
  if me is null or other_user = me or not exists (select 1 from public.profiles where id = other_user) then raise exception 'Invalid recipient'; end if;
  if exists (select 1 from public.blocks where (blocker_id = me and blocked_id = other_user) or (blocker_id = other_user and blocked_id = me)) then raise exception 'Conversation unavailable'; end if;
  perform pg_advisory_xact_lock(hashtext(least(me::text,other_user::text) || greatest(me::text,other_user::text)));
  select c.id into chat_id from public.conversations c
  join public.conversation_members a on a.conversation_id = c.id and a.user_id = me
  join public.conversation_members b on b.conversation_id = c.id and b.user_id = other_user
  where c.kind = 'direct' limit 1;
  if chat_id is not null then return chat_id; end if;
  insert into public.conversations(kind, owner_id) values ('direct', me) returning id into chat_id;
  insert into public.conversation_members(conversation_id,user_id) values (chat_id,me),(chat_id,other_user);
  return chat_id;
end $function$
;
CREATE OR REPLACE FUNCTION public.create_group_chat(group_name text, group_description text DEFAULT ''::text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare chat_id uuid; me uuid := auth.uid();
begin
 if not private.melo_mfa_ok() then raise exception 'MFA verification required' using errcode='42501'; end if;
  if me is null or nullif(trim(group_name),'') is null or char_length(group_name) > 80 then raise exception 'Invalid group name'; end if;
  insert into public.conversations(kind,name,description,owner_id) values ('group',trim(group_name),left(coalesce(group_description,''),500),me) returning id into chat_id;
  insert into public.conversation_members(conversation_id,user_id,role) values (chat_id,me,'owner');
  return chat_id;
end $function$
;
CREATE OR REPLACE FUNCTION public.delete_my_account()
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare item record; successor uuid;
begin
 if not private.melo_mfa_ok() then raise exception 'MFA verification required' using errcode='42501'; end if;
  if auth.uid() is null then raise exception 'Sign in first'; end if;
  for item in select id from public.conversations where kind = 'group' and owner_id = auth.uid() loop
    select user_id into successor from public.conversation_members
      where conversation_id = item.id and user_id <> auth.uid()
      order by case role when 'admin' then 0 else 1 end, joined_at limit 1;
    if successor is null then
      delete from public.conversations where id = item.id;
    else
      update public.conversations set owner_id = successor where id = item.id;
      update public.conversation_members set role = 'owner' where conversation_id = item.id and user_id = successor;
    end if;
  end loop;
  delete from auth.users where id = auth.uid();
end $function$
;
CREATE OR REPLACE FUNCTION public.join_group(invite uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare chat_id uuid; me uuid := auth.uid();
begin
 if not private.melo_mfa_ok() then raise exception 'MFA verification required' using errcode='42501'; end if;
  if me is null then raise exception 'Sign in first'; end if;
  select id into chat_id from public.conversations where invite_token = invite and kind = 'group';
  if chat_id is null then raise exception 'Invalid invitation'; end if;
  if (select count(*) from public.conversation_members where conversation_id = chat_id) >= 200 then raise exception 'Group is full'; end if;
  insert into public.conversation_members(conversation_id,user_id) values (chat_id,me) on conflict do nothing;
  return chat_id;
end $function$
;
CREATE OR REPLACE FUNCTION public.leave_group(chat_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare me uuid := auth.uid(); successor uuid;
begin
 if not private.melo_mfa_ok() then raise exception 'MFA verification required' using errcode='42501'; end if;
  if me is null or (select kind from public.conversations where id = chat_id) <> 'group' or not private.is_member(chat_id, me) then raise exception 'Not a group member'; end if;
  if (select owner_id from public.conversations where id = chat_id) = me then
    select user_id into successor from public.conversation_members where conversation_id = chat_id and user_id <> me
      order by case role when 'admin' then 0 else 1 end, joined_at limit 1;
    if successor is null then delete from public.conversations where id = chat_id; return; end if;
    update public.conversations set owner_id = successor where id = chat_id;
    update public.conversation_members set role = 'owner' where conversation_id = chat_id and user_id = successor;
  end if;
  delete from public.conversation_members where conversation_id = chat_id and user_id = me;
end $function$
;
CREATE OR REPLACE FUNCTION private.manage_melo_badge(target_id uuid, badge_id uuid, badge_label text, badge_icon text, badge_bg text, badge_fg text, badge_description text, remove_badge boolean)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare badges jsonb; item jsonb; label_clean text:=trim(badge_label); descr text:=trim(coalesce(badge_description,'')); normalized text;
begin
 if not private.melo_mfa_ok() then raise exception 'MFA verification required' using errcode='42501'; end if;
 if auth.uid() is null or not exists(select 1 from public.melo_admins where user_id=auth.uid()) then raise exception 'Administrator access required' using errcode='42501'; end if;
 select custom_badges into badges from public.profiles where id=target_id for update;
 if not found then raise exception 'User not found'; end if;
 if remove_badge then
  select coalesce(jsonb_agg(x.value order by x.ordinality),'[]'::jsonb) into badges from jsonb_array_elements(badges) with ordinality x(value,ordinality) where x.value->>'id'<>badge_id::text;
 else
  if label_clean is null or char_length(label_clean) not between 1 and 20 or label_clean !~ '^[[:alnum:][:space:]_+.-]+$' or label_clean ~ '[[:cntrl:]]' then raise exception 'Название: 1–20 букв, цифр или обычных символов'; end if;
  normalized:=lower(regexp_replace(label_clean,'[[:space:]_+.-]','','g'));
  if normalized ~ '(админ|admin|владелец|owner|moderator|модератор|verified|верифиц|подтвержд|meloplus)' then raise exception 'Это название зарезервировано для системных статусов'; end if;
  if badge_icon is null or badge_icon not in ('','star','favorite','bolt','diamond','code','science','rocket_launch','palette','workspace_premium','emoji_events','local_fire_department','music_note','sports_esports','auto_awesome','flutter_dash','pets','public','brush','lightbulb','celebration') then raise exception 'Invalid icon'; end if;
  if badge_bg is null or badge_fg is null or badge_bg !~ '^#[0-9a-fA-F]{6}$' or badge_fg !~ '^#[0-9a-fA-F]{6}$' or char_length(descr)>120 then raise exception 'Invalid colors or description'; end if;
  item:=jsonb_build_object('id',coalesce(badge_id,gen_random_uuid()),'label',label_clean,'icon',badge_icon,'bg',badge_bg,'fg',badge_fg,'description',descr);
  if badge_id is not null then
   if not exists(select 1 from jsonb_array_elements(badges) x where x->>'id'=badge_id::text) then raise exception 'Badge not found'; end if;
   select jsonb_agg(case when x.value->>'id'=badge_id::text then item else x.value end order by x.ordinality) into badges from jsonb_array_elements(badges) with ordinality x(value,ordinality);
  else
   if jsonb_array_length(badges)>=3 then raise exception 'Максимум 3 кастомных бейджа на пользователя'; end if;
   badges:=badges||jsonb_build_array(item);
  end if;
 end if;
 update public.profiles set custom_badges=badges where id=target_id;
 return badges;
end $function$
;
CREATE OR REPLACE FUNCTION private.melo_collectible_owner(action text, target uuid DEFAULT NULL::uuid, params jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare n text; p integer; req public.melo_name_requests%rowtype; entry public.melo_premium_names%rowtype; bal bigint; amount bigint; sid bigint;
begin
 if not private.melo_mfa_ok() then raise exception 'MFA verification required' using errcode='42501'; end if;
 if auth.uid() is null or not exists(select 1 from public.melo_admins where user_id=auth.uid() and is_owner) then raise exception 'Owner access required' using errcode='42501'; end if;
 if action='gift' then
 insert into public.melo_collectibles(recipient_id,kind,title,icon,color,rarity,description) values(target,params->>'kind',trim(params->>'title'),params->>'icon',params->>'color',params->>'rarity',coalesce(params->>'description','')) returning serial into sid;
 return jsonb_build_object('serial',sid);
 elsif action='credits' then
 amount:=(params->>'amount')::bigint;
 if amount is null or amount not between 1 and 1000000 then raise exception 'Invalid amount'; end if;
 insert into public.melo_credits(user_id,balance) values(target,amount) on conflict(user_id) do update set balance=public.melo_credits.balance+excluded.balance returning balance into bal;
 return jsonb_build_object('balance',bal);
 elsif action='delist' then
 n:=lower(trim(leading '@' from trim(params->>'username')));
 if n is null or n !~ '^[a-z][a-z0-9_]{3,23}$' then raise exception 'Invalid username'; end if;
 perform pg_advisory_xact_lock(hashtextextended(n,741));
 update public.melo_premium_names set listed=false where username=n and assigned_to is null;
 if not found then raise exception 'Only unassigned usernames may be delisted'; end if;
 update public.melo_name_requests set status='rejected' where username=n and status='pending';
 return jsonb_build_object('username',n,'listed',false);
 elsif action in ('reserve','grant') then
 n:=lower(trim(leading '@' from trim(params->>'username')));
 if n is null or n !~ '^[a-z][a-z0-9_]{3,23}$' then raise exception 'Invalid username'; end if;
 perform pg_advisory_xact_lock(hashtextextended(n,741));
 if exists(select 1 from public.profiles where username=n) or exists(select 1 from public.melo_channels where username=n) then raise exception 'Username already in use'; end if;
 if action='reserve' then
 p:=(params->>'price')::integer;
 insert into public.melo_premium_names(username,price,listed) values(n,p,true) on conflict(username) do update set price=excluded.price,listed=true where public.melo_premium_names.assigned_to is null and not public.melo_premium_names.listed;
 if not found then raise exception 'Username already listed or issued'; end if;
 else
 if target is null or not exists(select 1 from public.profiles where id=target) then raise exception 'User not found'; end if;
 insert into public.melo_premium_names(username,price,assigned_to,acquired_at,acquisition,paid_price) values(n,0,target,now(),'gift',0) on conflict(username) do update set assigned_to=excluded.assigned_to,acquired_at=now(),acquisition='gift',paid_price=0 where public.melo_premium_names.assigned_to is null;
 if not found then raise exception 'Username already issued'; end if;
 -- Keep the account's existing primary username.
 update public.melo_name_requests set status='rejected' where username=n and status='pending';
 end if;
 return jsonb_build_object('username',n);
 elsif action in ('approve','reject') then
 select * into req from public.melo_name_requests where id=target;
 if not found then raise exception 'Request not found'; end if;
 perform pg_advisory_xact_lock(hashtextextended(req.username,741));
 select * into req from public.melo_name_requests where id=target for update;
 if req.status<>'pending' then raise exception 'Request already processed'; end if;
 if action='reject' then update public.melo_name_requests set status='rejected' where id=target; return jsonb_build_object('status','rejected'); end if;
 select * into entry from public.melo_premium_names where username=req.username for update;
 if not found or not entry.listed or entry.assigned_to is not null or entry.price<>req.price then raise exception 'Username unavailable or price changed'; end if;
 if exists(select 1 from public.profiles where username=req.username) or exists(select 1 from public.melo_channels where username=req.username) then raise exception 'Username already in use'; end if;
 if req.price>0 then
 update public.melo_credits set balance=balance-req.price where user_id=req.user_id and balance>=req.price;
 if not found then raise exception 'Insufficient Melo points'; end if;
 end if;
 update public.melo_premium_names set assigned_to=req.user_id,acquired_at=now(),acquisition='purchase',paid_price=req.price where username=req.username;
 -- Purchased usernames become additional aliases.
 update public.melo_name_requests set status=case when id=target then 'approved' else 'rejected' end where username=req.username and status='pending';
 return jsonb_build_object('status','approved');
 else raise exception 'Invalid action'; end if;
end $function$
;
CREATE OR REPLACE FUNCTION private.melo_moderate_post(report_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare report public.melo_reports%rowtype;
begin
 if not private.melo_mfa_ok() then raise exception 'MFA verification required' using errcode='42501'; end if;
 if auth.uid() is null or not exists(select 1 from public.melo_admins where user_id=auth.uid() and is_owner) then raise exception 'Owner access required' using errcode='42501';end if;
 select * into report from public.melo_reports where id=report_id and target_type='post' and status='open' for update;
 if not found then raise exception 'Report unavailable';end if;
 delete from public.melo_channel_posts where id=report.target_id;
 update public.melo_reports set status='resolved' where id=report_id;
end $function$
;
CREATE OR REPLACE FUNCTION private.melo_owner_stats(days integer DEFAULT 30)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare since timestamptz; result jsonb;
begin
 if not private.melo_mfa_ok() then raise exception 'MFA verification required' using errcode='42501'; end if;
 if auth.uid() is null or not exists(select 1 from public.melo_admins where user_id=auth.uid() and is_owner) then raise exception 'Owner access required' using errcode='42501'; end if;
 if days is null or days not in (7,30,90) then raise exception 'Invalid period'; end if;
 since:=((now() at time zone 'UTC')::date-(days-1))::timestamp at time zone 'UTC';
 with m as (select sender_id,created_at,kind,conversation_id,deleted_at from public.messages),
 activity as (
 select sender_id as uid,created_at from m where deleted_at is null
 union all select c.owner_id,p.created_at from public.melo_channel_posts p join public.melo_channels c on c.id=p.channel_id
 union all select user_id,created_at from public.melo_post_comments
 ),
 daily as (
 select d::date as day,
 (select count(*) from public.profiles p where p.created_at>=d at time zone 'UTC' and p.created_at<(d+interval '1 day') at time zone 'UTC') as registrations,
 (select count(*) from m where deleted_at is null and created_at>=d at time zone 'UTC' and created_at<(d+interval '1 day') at time zone 'UTC') as messages,
 (select count(distinct uid) from activity where created_at>=d at time zone 'UTC' and created_at<(d+interval '1 day') at time zone 'UTC') as active,
 (select count(*) from public.melo_channel_posts p where p.created_at>=d at time zone 'UTC' and p.created_at<(d+interval '1 day') at time zone 'UTC') as posts,
 (select count(*) from public.melo_post_comments p where p.created_at>=d at time zone 'UTC' and p.created_at<(d+interval '1 day') at time zone 'UTC') as comments
 from generate_series((since at time zone 'UTC')::date::timestamp,(now() at time zone 'UTC')::date::timestamp,interval '1 day') d
 )
 select jsonb_build_object(
 'generated_at',now(),'days',days,
 'accounts',(select count(*) from auth.users),
 'confirmed_accounts',(select count(*) from auth.users where email_confirmed_at is not null),
 'profiles',(select count(*) from public.profiles),
 'registered_period',(select count(*) from public.profiles where created_at>=since),
 'writers',(select count(distinct sender_id) from m where deleted_at is null),
 'writers_period',(select count(distinct sender_id) from m where deleted_at is null and created_at>=since),
 'active_period',(select count(distinct uid) from activity where created_at>=since),
 'active_today',(select count(distinct uid) from activity where created_at>=((now() at time zone 'UTC')::date::timestamp at time zone 'UTC')),
 'active_7',(select count(distinct uid) from activity where created_at>=now()-interval '7 days'),
 'active_30',(select count(distinct uid) from activity where created_at>=now()-interval '30 days'),
 'recently_seen',(select count(*) from public.profiles where last_seen_at>=now()-interval '2 minutes' and show_online),
 'messages',(select count(*) from m where deleted_at is null),
 'messages_period',(select count(*) from m where deleted_at is null and created_at>=since),
 'messages_deleted',(select count(*) from m where deleted_at is not null),
 'direct_messages',(select count(*) from m join public.conversations c on c.id=m.conversation_id where c.kind='direct' and m.deleted_at is null),
 'group_messages',(select count(*) from m join public.conversations c on c.id=m.conversation_id where c.kind='group' and m.deleted_at is null),
 'message_types',(select coalesce(jsonb_object_agg(kind,n),'{}'::jsonb) from (select kind,count(*) n from m where deleted_at is null group by kind) x),
 'chats',(select count(*) from public.conversations),
 'direct_chats',(select count(*) from public.conversations where kind='direct'),
 'groups',(select count(*) from public.conversations where kind='group'),
 'active_chats_period',(select count(distinct conversation_id) from m where deleted_at is null and created_at>=since),
 'memberships',(select count(*) from public.conversation_members),
 'channels',(select count(*) from public.melo_channels),
 'channels_period',(select count(*) from public.melo_channels where created_at>=since),
 'subscriptions',(select count(*) from public.melo_channel_subscriptions),
 'subscribers',(select count(distinct user_id) from public.melo_channel_subscriptions),
 'posts',(select count(*) from public.melo_channel_posts),
 'posts_period',(select count(*) from public.melo_channel_posts where created_at>=since),
 'comments',(select count(*) from public.melo_post_comments),
 'comments_period',(select count(*) from public.melo_post_comments where created_at>=since),
 'post_reactions',(select count(*) from public.melo_post_reactions),
 'chat_reactions',(select count(*) from public.reactions),
 'stories',(select count(*) from public.melo_stories where expires_at>now()),
 'admins',(select count(*) from public.melo_admins),
 'verified',(select count(*) from public.profiles where verified),
 'plus',(select count(*) from public.profiles where plus),
 'custom_badges',(select coalesce(sum(jsonb_array_length(custom_badges)),0) from public.profiles),
 'daily',(select coalesce(jsonb_agg(to_jsonb(daily) order by day),'[]'::jsonb) from daily),
 'top_channels',(select coalesce(jsonb_agg(to_jsonb(t) order by subscribers desc,posts desc,name),'[]'::jsonb) from (select c.name,c.username,c.subscriber_count as subscribers,(select count(*) from public.melo_channel_posts p where p.channel_id=c.id) as posts from public.melo_channels c order by c.subscriber_count desc,c.created_at desc limit 10) t)
 ) into result;
 return result;
end $function$
;
CREATE OR REPLACE FUNCTION private.melo_owner_user_stats(days integer, page_number integer, search_term text DEFAULT ''::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare since timestamptz; result jsonb; term text:=left(lower(trim(coalesce(search_term,''))),100);
begin
 if not private.melo_mfa_ok() then raise exception 'MFA verification required' using errcode='42501'; end if;
 if auth.uid() is null or not exists(select 1 from public.melo_admins where user_id=auth.uid() and is_owner) then raise exception 'Owner access required' using errcode='42501'; end if;
 if days is null or days not in (7,30,90) or page_number is null or page_number<0 or page_number>100000 then raise exception 'Invalid page or period'; end if;
 since:=((now() at time zone 'UTC')::date-(days-1))::timestamp at time zone 'UTC';
 with users as (select id,username,created_at from public.profiles where term='' or strpos(lower(username),trim(leading '@' from term))>0),
 msg as (select sender_id,count(*) as messages,count(*) filter(where created_at>=since) as recent from public.messages where deleted_at is null group by sender_id),
 ranked as (select u.id,u.username,u.created_at,coalesce(m.messages,0) as messages,coalesce(m.recent,0) as messages_period from users u left join msg m on m.sender_id=u.id order by messages_period desc,messages desc,u.username limit 25 offset page_number*25),
 rows as (select r.username,r.created_at,r.messages,r.messages_period,
 (select count(*) from public.conversation_members m where m.user_id=r.id) as chats,
 (select count(*) from public.conversations c where c.owner_id=r.id and c.kind='group') as groups,
 (select count(*) from public.melo_channels c where c.owner_id=r.id) as channels,
 (select count(*) from public.melo_channel_subscriptions s where s.user_id=r.id) as subscriptions,
 (select count(*) from public.melo_channel_posts p join public.melo_channels c on c.id=p.channel_id where c.owner_id=r.id) as posts,
 (select count(*) from public.melo_post_comments c where c.user_id=r.id) as comments
 from ranked r)
 select jsonb_build_object('total',(select count(*) from users),'rows',(select coalesce(jsonb_agg(to_jsonb(rows) order by messages_period desc,messages desc,username),'[]'::jsonb) from rows)) into result;
 return result;
end $function$
;
CREATE OR REPLACE FUNCTION private.melo_request_name(name text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare n text:=lower(trim(name)); p integer; rid uuid;
begin
 if not private.melo_mfa_ok() then raise exception 'MFA verification required' using errcode='42501'; end if;
 if auth.uid() is null then raise exception 'Authentication required' using errcode='42501'; end if;
 perform pg_advisory_xact_lock(hashtextextended(n,741));
 select price into p from public.melo_premium_names where username=n and assigned_to is null and listed;
 if not found then raise exception 'Username unavailable'; end if;
 if p>coalesce((select balance from public.melo_credits where user_id=auth.uid()),0) then raise exception 'Insufficient Melo points'; end if;
 insert into public.melo_name_requests(username,user_id,price) values(n,auth.uid(),p) on conflict(username,user_id) where status='pending' do nothing returning id into rid;
 if rid is null then select id into rid from public.melo_name_requests where username=n and user_id=auth.uid() and status='pending'; end if;
 return rid;
end $function$
;
CREATE OR REPLACE FUNCTION private.melo_sessions()
 RETURNS TABLE(id uuid, created_at timestamp with time zone, updated_at timestamp with time zone, user_agent text, current_session boolean)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$select s.id,s.created_at,s.updated_at,s.user_agent,s.id::text=auth.jwt()->>'session_id' from auth.sessions s where private.melo_mfa_ok() and s.user_id=auth.uid() and (s.not_after is null or s.not_after>now()) order by s.updated_at desc$function$
;
CREATE OR REPLACE FUNCTION private.melo_view_counts(ids uuid[])
 RETURNS TABLE(post_id uuid, views bigint)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$select v.post_id,count(*) from public.melo_post_views v where private.melo_mfa_ok() and auth.uid() is not null and cardinality(ids)<=150 and v.post_id=any(ids) group by v.post_id$function$
;
CREATE OR REPLACE FUNCTION public.remove_group_member(chat_id uuid, member_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
 if not private.melo_mfa_ok() then raise exception 'MFA verification required' using errcode='42501'; end if;
  if auth.uid() is null or not private.is_admin(chat_id,auth.uid()) or (select kind from public.conversations where id=chat_id) <> 'group' then raise exception 'Admins only'; end if;
  if (select role from public.conversation_members where conversation_id=chat_id and user_id=member_id) = 'owner' then raise exception 'Cannot remove owner'; end if;
  delete from public.conversation_members where conversation_id=chat_id and user_id=member_id;
end $function$
;
CREATE OR REPLACE FUNCTION public.set_group_admin(chat_id uuid, member_id uuid, make_admin boolean)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
 if not private.melo_mfa_ok() then raise exception 'MFA verification required' using errcode='42501'; end if;
  if auth.uid() is null or (select owner_id from public.conversations where id=chat_id and kind='group') is distinct from auth.uid() then raise exception 'Owner only'; end if;
  update public.conversation_members set role = case when make_admin then 'admin' else 'member' end where conversation_id=chat_id and user_id=member_id and role <> 'owner';
end $function$
;
CREATE OR REPLACE FUNCTION private.set_melo_admin(target_id uuid, make_admin boolean)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
 if not private.melo_mfa_ok() then raise exception 'MFA verification required' using errcode='42501'; end if;
 if auth.uid() is null or not exists(select 1 from public.melo_admins where user_id=auth.uid() and is_owner) then
  raise exception 'Owner access required' using errcode='42501';
 end if;
 if make_admin is null or target_id is null then raise exception 'Invalid target or role'; end if;
 if exists(select 1 from public.melo_admins where user_id=target_id and is_owner) then
  raise exception 'Owner role cannot be changed' using errcode='42501';
 end if;
 if not exists(select 1 from public.profiles where id=target_id) then raise exception 'User not found'; end if;
 if make_admin then insert into public.melo_admins(user_id) values(target_id) on conflict(user_id) do nothing;
 else delete from public.melo_admins where user_id=target_id and not is_owner; end if;
 return make_admin;
end $function$
;
CREATE OR REPLACE FUNCTION private.set_melo_awards(target_username text, make_plus boolean, badge text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
 if not private.melo_mfa_ok() then raise exception 'MFA verification required' using errcode='42501'; end if;
 if auth.uid() is null or not exists(select 1 from public.melo_admins where user_id=auth.uid()) then
  raise exception 'Administrator access required' using errcode='42501';
 end if;
 if badge not in ('','founder','developer','tester','legend') then raise exception 'Invalid badge'; end if;
 update public.profiles set plus=make_plus, rare_badge=badge where username=lower(trim(leading '@' from trim(target_username)));
 if not found then raise exception 'Username not found'; end if;
end $function$
;
CREATE OR REPLACE FUNCTION private.set_melo_verified(target_username text, make_verified boolean)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
 if not private.melo_mfa_ok() then raise exception 'MFA verification required' using errcode='42501'; end if;
  if auth.uid() is null or not exists (select 1 from public.melo_admins where user_id=auth.uid()) then
    raise exception 'Administrator access required' using errcode='42501';
  end if;
  update public.profiles set verified=make_verified where username=lower(trim(leading '@' from trim(target_username)));
  if not found then raise exception 'Username not found'; end if;
  return make_verified;
end $function$
;
create trigger melo_channel_latest_edit after update of body on public.melo_channel_posts for each row execute function private.melo_channel_latest_change();