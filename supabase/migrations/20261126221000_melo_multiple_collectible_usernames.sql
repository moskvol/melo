alter table public.melo_premium_names add column acquired_at timestamptz, add column acquisition text check(acquisition in ('gift','purchase')), add column paid_price integer check(paid_price>=0);
create index melo_premium_names_holder on public.melo_premium_names(assigned_to) where assigned_to is not null;
CREATE OR REPLACE FUNCTION private.melo_collectible_owner(action text, target uuid DEFAULT NULL::uuid, params jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare n text; p integer; req public.melo_name_requests%rowtype; entry public.melo_premium_names%rowtype; bal bigint; amount bigint; sid bigint;
begin
 if auth.uid() is null or not exists(select 1 from public.melo_admins where user_id=auth.uid() and is_owner) then raise exception 'Owner access required' using errcode='42501'; end if;
 if action='gift' then
 insert into public.melo_collectibles(recipient_id,kind,title,icon,color,rarity,description) values(target,params->>'kind',trim(params->>'title'),params->>'icon',params->>'color',params->>'rarity',coalesce(params->>'description','')) returning serial into sid;
 return jsonb_build_object('serial',sid);
 elsif action='credits' then
 amount:=(params->>'amount')::bigint;
 if amount is null or amount not between 1 and 1000000 then raise exception 'Invalid amount'; end if;
 insert into public.melo_credits(user_id,balance) values(target,amount) on conflict(user_id) do update set balance=public.melo_credits.balance+excluded.balance returning balance into bal;
 return jsonb_build_object('balance',bal);
 elsif action in ('reserve','grant') then
 n:=lower(trim(leading '@' from trim(params->>'username')));
 if n is null or n !~ '^[a-z][a-z0-9_]{3,23}$' then raise exception 'Invalid username'; end if;
 perform pg_advisory_xact_lock(hashtextextended(n,741));
 if exists(select 1 from public.profiles where username=n) or exists(select 1 from public.melo_channels where username=n) then raise exception 'Username already in use'; end if;
 if action='reserve' then
 p:=(params->>'price')::integer;
 insert into public.melo_premium_names(username,price) values(n,p);
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
 if entry.assigned_to is not null or entry.price<>req.price then raise exception 'Username unavailable or price changed'; end if;
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
create function public.melo_search_aliases(term text) returns setof public.profiles language sql stable security invoker set search_path='' as $$
 select p.* from public.profiles p where exists(select 1 from public.melo_premium_names n where n.assigned_to=p.id and strpos(n.username,lower(trim(leading '@' from trim(term))))>0) and char_length(trim(leading '@' from trim(term))) between 1 and 32 order by p.username limit 20
$$;
revoke all on function public.melo_search_aliases(text) from public,anon,authenticated;
grant execute on function public.melo_search_aliases(text) to authenticated;