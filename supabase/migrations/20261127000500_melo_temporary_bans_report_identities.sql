create table private.melo_bans(id uuid primary key default gen_random_uuid(),user_id uuid not null references public.profiles(id) on delete cascade,issued_by uuid references public.profiles(id) on delete set null,reason text not null check(char_length(trim(reason)) between 1 and 500),created_at timestamptz not null default now(),ends_at timestamptz not null,revoked_at timestamptz,revoked_by uuid references public.profiles(id) on delete set null,check(ends_at>created_at));
alter table private.melo_bans enable row level security;
revoke all on private.melo_bans from public,anon,authenticated;
create index melo_bans_active on private.melo_bans(user_id,ends_at) where revoked_at is null;
create or replace function private.melo_mfa_ok() returns boolean language sql stable security definer set search_path='' as $$
 select auth.uid() is not null and not exists(select 1 from private.melo_bans b where b.user_id=auth.uid() and b.revoked_at is null and b.ends_at>now()) and (coalesce(auth.jwt()->>'aal','')='aal2' or not exists(select 1 from auth.mfa_factors f where f.user_id=auth.uid() and f.status='verified'))
$$;
create function private.melo_my_ban() returns jsonb language sql stable security definer set search_path='' as $$
 select jsonb_build_object('reason',b.reason,'ends_at',b.ends_at) from private.melo_bans b where b.user_id=auth.uid() and b.revoked_at is null and b.ends_at>now() order by b.ends_at desc limit 1
$$;
create function private.melo_admin_ban(target uuid,minutes integer,reason_text text default '') returns jsonb language plpgsql security definer set search_path='' as $$
declare actor_owner boolean; result jsonb;
begin
 if not private.melo_mfa_ok() then raise exception 'Access denied' using errcode='42501';end if;
 select is_owner into actor_owner from public.melo_admins where user_id=auth.uid();
 if not found or target is null or target=auth.uid() or exists(select 1 from public.melo_admins where user_id=target and (is_owner or not actor_owner)) then raise exception 'Cannot moderate this account' using errcode='42501';end if;
 if not exists(select 1 from public.profiles where id=target) then raise exception 'User not found';end if;
 if minutes is null or minutes<0 or minutes>525600 or (minutes>0 and (reason_text is null or char_length(trim(reason_text)) not between 1 and 500)) then raise exception 'Invalid duration or reason';end if;
 perform pg_advisory_xact_lock(hashtextextended(target::text,972));
 update private.melo_bans set revoked_at=now(),revoked_by=auth.uid() where user_id=target and revoked_at is null and ends_at>now();
 if minutes=0 then return null;end if;
 insert into private.melo_bans(user_id,issued_by,reason,ends_at) values(target,auth.uid(),trim(reason_text),now()+make_interval(mins=>minutes)) returning jsonb_build_object('reason',reason,'ends_at',ends_at) into result;
 delete from private.melo_push_subscriptions where user_id=target;
 return result;
end $$;
create function private.melo_ban_list() returns jsonb language sql stable security definer set search_path='' as $$
 select coalesce(jsonb_agg(to_jsonb(x)),'[]'::jsonb) from (select b.id,b.user_id,p.username,b.reason,b.ends_at,b.created_at,b.revoked_at,a.username as issued_by_username from private.melo_bans b join public.profiles p on p.id=b.user_id left join public.profiles a on a.id=b.issued_by where private.melo_mfa_ok() and exists(select 1 from public.melo_admins where user_id=auth.uid()) and b.revoked_at is null and b.ends_at>now() order by b.ends_at limit 200) x
$$;
alter table public.melo_channel_posts add column author_id uuid references public.profiles(id) on delete set null;
create function private.melo_post_author() returns trigger language plpgsql set search_path='' as $$begin new.author_id:=auth.uid();return new;end $$;
create trigger melo_post_author before insert on public.melo_channel_posts for each row execute function private.melo_post_author();
alter table public.melo_reports add column reporter_username text,add column reported_user_id uuid,add column reported_username text,add column reported_channel text,add column reported_post_text text,add column reported_is_channel_owner boolean not null default false;
create function private.melo_report_snapshot() returns trigger language plpgsql security definer set search_path='' as $$
begin
 select username into new.reporter_username from public.profiles where id=new.reporter_id;
 if new.target_type='user' then
 new.reported_user_id:=new.target_id;
 select username into new.reported_username from public.profiles where id=new.target_id;
 else
 select coalesce(p.author_id,c.owner_id),u.username,c.username,p.body,p.author_id is null into new.reported_user_id,new.reported_username,new.reported_channel,new.reported_post_text,new.reported_is_channel_owner from public.melo_channel_posts p join public.melo_channels c on c.id=p.channel_id left join public.profiles u on u.id=coalesce(p.author_id,c.owner_id) where p.id=new.target_id;
 new.reported_is_channel_owner:=coalesce(new.reported_is_channel_owner,false);
 end if;
 return new;
end $$;
revoke all on function private.melo_report_snapshot() from public,anon,authenticated;
create trigger melo_report_snapshot before insert on public.melo_reports for each row execute function private.melo_report_snapshot();
update public.melo_reports r set reporter_username=p.username from public.profiles p where p.id=r.reporter_id;
update public.melo_reports r set reported_user_id=p.id,reported_username=p.username from public.profiles p where r.target_type='user' and r.target_id=p.id;
update public.melo_reports r set reported_user_id=c.owner_id,reported_username=u.username,reported_channel=c.username,reported_post_text=p.body,reported_is_channel_owner=true from public.melo_channel_posts p join public.melo_channels c on c.id=p.channel_id left join public.profiles u on u.id=c.owner_id where r.target_type='post' and r.target_id=p.id;
create function private.melo_admin_reports() returns jsonb language sql stable security definer set search_path='' as $$
 select coalesce(jsonb_agg(to_jsonb(x)),'[]'::jsonb) from (select r.id,r.reporter_id,r.target_type,r.target_id,r.reason,r.status,r.created_at,coalesce(a.username,r.reporter_username) as reporter_username, r.reported_user_id,coalesce(b.username,r.reported_username) as reported_username,r.reported_channel,r.reported_post_text,r.reported_is_channel_owner from public.melo_reports r left join public.profiles a on a.id=r.reporter_id left join public.profiles b on b.id=r.reported_user_id where private.melo_mfa_ok() and exists(select 1 from public.melo_admins where user_id=auth.uid()) order by (r.status='open') desc,r.created_at desc limit 150) x
$$;
revoke all on function private.melo_my_ban() from public,anon,authenticated;
grant execute on function private.melo_my_ban() to authenticated;
create function public.melo_my_ban() returns jsonb language sql security invoker set search_path='' as $$select private.melo_my_ban()$$;
revoke all on function public.melo_my_ban() from public,anon,authenticated;
grant execute on function public.melo_my_ban() to authenticated;
revoke all on function private.melo_admin_ban(uuid,integer,text) from public,anon,authenticated;
grant execute on function private.melo_admin_ban(uuid,integer,text) to authenticated;
create function public.melo_admin_ban(target uuid,minutes integer,reason_text text default '') returns jsonb language sql security invoker set search_path='' as $$select private.melo_admin_ban(target,minutes,reason_text)$$;
revoke all on function public.melo_admin_ban(uuid,integer,text) from public,anon,authenticated;
grant execute on function public.melo_admin_ban(uuid,integer,text) to authenticated;
revoke all on function private.melo_ban_list() from public,anon,authenticated;
grant execute on function private.melo_ban_list() to authenticated;
create function public.melo_ban_list() returns jsonb language sql security invoker set search_path='' as $$select private.melo_ban_list()$$;
revoke all on function public.melo_ban_list() from public,anon,authenticated;
grant execute on function public.melo_ban_list() to authenticated;
revoke all on function private.melo_admin_reports() from public,anon,authenticated;
grant execute on function private.melo_admin_reports() to authenticated;
create function public.melo_admin_reports() returns jsonb language sql security invoker set search_path='' as $$select private.melo_admin_reports()$$;
revoke all on function public.melo_admin_reports() from public,anon,authenticated;
grant execute on function public.melo_admin_reports() to authenticated;
revoke select on public.melo_reports from authenticated;
grant select(id,reporter_id,target_type,target_id,reason,status,created_at) on public.melo_reports to authenticated;