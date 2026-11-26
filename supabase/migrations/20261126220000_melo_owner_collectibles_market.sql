create table public.melo_collectibles (
 serial bigint generated always as identity primary key,
 recipient_id uuid not null references public.profiles(id) on delete cascade,
 kind text not null check(kind in ('gift','collectible')),
 title text not null check(char_length(trim(title)) between 1 and 60),
 icon text not null check(icon in ('redeem','diamond','star','favorite','rocket_launch','workspace_premium','local_fire_department','pets','cake','auto_awesome','emoji_events')),
 color text not null check(color ~ '^#[0-9a-fA-F]{6}$'),
 rarity text not null check(rarity in ('common','rare','epic','legendary')),
 description text not null default '' check(char_length(description)<=240),
 created_at timestamptz not null default now()
);
create index melo_collectibles_recipient on public.melo_collectibles(recipient_id);
create table public.melo_premium_names (
 username text primary key check(username ~ '^[a-z][a-z0-9_]{3,23}$'),
 price integer not null check(price between 0 and 1000000),
 assigned_to uuid references public.profiles(id) on delete set null,
 created_at timestamptz not null default now()
);
create table public.melo_credits (
 user_id uuid primary key references public.profiles(id) on delete cascade,
 balance bigint not null default 0 check(balance between 0 and 1000000000)
);
create table public.melo_name_requests (
 id uuid primary key default gen_random_uuid(),
 username text not null references public.melo_premium_names(username),
 user_id uuid not null references public.profiles(id) on delete cascade,
 price integer not null check(price>=0),
 status text not null default 'pending' check(status in ('pending','approved','rejected')),
 created_at timestamptz not null default now()
);
create unique index melo_pending_name_request on public.melo_name_requests(username,user_id) where status='pending';
create index melo_name_requests_user on public.melo_name_requests(user_id,created_at desc);
alter table public.melo_collectibles enable row level security;
alter table public.melo_premium_names enable row level security;
alter table public.melo_credits enable row level security;
alter table public.melo_name_requests enable row level security;
revoke all on public.melo_collectibles,public.melo_premium_names,public.melo_credits,public.melo_name_requests from public,anon,authenticated;
grant select on public.melo_collectibles,public.melo_premium_names,public.melo_credits,public.melo_name_requests to authenticated;
create policy collectible_read on public.melo_collectibles for select to authenticated using(true);
create policy premium_name_read on public.melo_premium_names for select to authenticated using(true);
create policy own_credit_read on public.melo_credits for select to authenticated using(user_id=(select auth.uid()));
create policy name_request_read on public.melo_name_requests for select to authenticated using(user_id=(select auth.uid()) or exists(select 1 from public.melo_admins a where a.user_id=(select auth.uid()) and a.is_owner));

create function private.melo_check_reserved_name() returns trigger language plpgsql security definer set search_path='' as $$
declare holder uuid;
begin
 if tg_op='UPDATE' and new.username=old.username then return new; end if;
 perform pg_advisory_xact_lock(hashtextextended(new.username,741));
 select assigned_to into holder from public.melo_premium_names where username=new.username;
 if found then
 if tg_table_name='profiles' then
 if holder is null or holder<>new.id then raise exception 'Этот username зарезервирован в магазине Melo' using errcode='23514'; end if;
 else raise exception 'Этот username зарезервирован в магазине Melo' using errcode='23514'; end if;
 end if;
 return new;
end $$;
revoke all on function private.melo_check_reserved_name() from public,anon,authenticated;
create trigger melo_reserved_profile_name before insert or update of username on public.profiles for each row execute function private.melo_check_reserved_name();
create trigger melo_reserved_channel_name before insert or update of username on public.melo_channels for each row execute function private.melo_check_reserved_name();

create function private.melo_collectible_owner(action text,target uuid default null,params jsonb default '{}'::jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
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
 insert into public.melo_premium_names(username,price,assigned_to) values(n,0,target) on conflict(username) do update set assigned_to=excluded.assigned_to where public.melo_premium_names.assigned_to is null;
 if not found then raise exception 'Username already issued'; end if;
 update public.profiles set username=n where id=target;
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
 update public.melo_premium_names set assigned_to=req.user_id where username=req.username;
 update public.profiles set username=req.username where id=req.user_id;
 update public.melo_name_requests set status=case when id=target then 'approved' else 'rejected' end where username=req.username and status='pending';
 return jsonb_build_object('status','approved');
 else raise exception 'Invalid action'; end if;
end $$;
revoke all on function private.melo_collectible_owner(text,uuid,jsonb) from public,anon,authenticated;
grant execute on function private.melo_collectible_owner(text,uuid,jsonb) to authenticated;
create function public.melo_collectible_owner(action text,target uuid default null,params jsonb default '{}'::jsonb) returns jsonb language sql security invoker set search_path='' as $$select private.melo_collectible_owner(action,target,params)$$;
revoke all on function public.melo_collectible_owner(text,uuid,jsonb) from public,anon,authenticated;
grant execute on function public.melo_collectible_owner(text,uuid,jsonb) to authenticated;

create function private.melo_request_name(name text) returns uuid language plpgsql security definer set search_path='' as $$
declare n text:=lower(trim(name)); p integer; rid uuid;
begin
 if auth.uid() is null then raise exception 'Authentication required' using errcode='42501'; end if;
 perform pg_advisory_xact_lock(hashtextextended(n,741));
 select price into p from public.melo_premium_names where username=n and assigned_to is null;
 if not found then raise exception 'Username unavailable'; end if;
 if p>coalesce((select balance from public.melo_credits where user_id=auth.uid()),0) then raise exception 'Insufficient Melo points'; end if;
 insert into public.melo_name_requests(username,user_id,price) values(n,auth.uid(),p) on conflict(username,user_id) where status='pending' do nothing returning id into rid;
 if rid is null then select id into rid from public.melo_name_requests where username=n and user_id=auth.uid() and status='pending'; end if;
 return rid;
end $$;
revoke all on function private.melo_request_name(text) from public,anon,authenticated;
grant execute on function private.melo_request_name(text) to authenticated;
create function public.melo_request_name(name text) returns uuid language sql security invoker set search_path='' as $$select private.melo_request_name(name)$$;
revoke all on function public.melo_request_name(text) from public,anon,authenticated;
grant execute on function public.melo_request_name(text) to authenticated;