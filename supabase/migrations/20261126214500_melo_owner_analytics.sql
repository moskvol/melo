create function private.melo_owner_stats(days integer default 30)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare since timestamptz; result jsonb;
begin
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
end $$;
revoke all on function private.melo_owner_stats(integer) from public,anon,authenticated;
grant execute on function private.melo_owner_stats(integer) to authenticated;
create function public.melo_owner_stats(days integer default 30) returns jsonb language sql stable security invoker set search_path='' as $$select private.melo_owner_stats(days)$$;
revoke all on function public.melo_owner_stats(integer) from public,anon,authenticated;
grant execute on function public.melo_owner_stats(integer) to authenticated;

create function private.melo_owner_user_stats(days integer, page_number integer, search_term text default '')
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare since timestamptz; result jsonb; term text:=left(lower(trim(coalesce(search_term,''))),100);
begin
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
end $$;
revoke all on function private.melo_owner_user_stats(integer,integer,text) from public,anon,authenticated;
grant execute on function private.melo_owner_user_stats(integer,integer,text) to authenticated;
create function public.melo_owner_user_stats(days integer,page_number integer,search_term text default '') returns jsonb language sql stable security invoker set search_path='' as $$select private.melo_owner_user_stats(days,page_number,search_term)$$;
revoke all on function public.melo_owner_user_stats(integer,integer,text) from public,anon,authenticated;
grant execute on function public.melo_owner_user_stats(integer,integer,text) to authenticated;