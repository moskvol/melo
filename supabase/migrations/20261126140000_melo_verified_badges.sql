alter table public.profiles add column verified boolean not null default false;
create table public.melo_admins (
  user_id uuid primary key references auth.users(id) on delete cascade
);
alter table public.melo_admins enable row level security;
revoke all on public.melo_admins from public, anon, authenticated;
grant select on public.melo_admins to authenticated;
create policy own_admin_status on public.melo_admins for select to authenticated using (user_id = (select auth.uid()));
create or replace function private.set_melo_verified(target_username text, make_verified boolean)
returns boolean language plpgsql security definer set search_path = '' as $$
begin
  if auth.uid() is null or not exists (select 1 from public.melo_admins where user_id=auth.uid()) then
    raise exception 'Administrator access required' using errcode='42501';
  end if;
  update public.profiles set verified=make_verified where username=lower(trim(leading '@' from trim(target_username)));
  if not found then raise exception 'Username not found'; end if;
  return make_verified;
end $$;
revoke all on function private.set_melo_verified(text,boolean) from public, anon, authenticated;
grant execute on function private.set_melo_verified(text,boolean) to authenticated;
create or replace function public.set_melo_verified(target_username text, make_verified boolean)
returns boolean language sql security invoker set search_path = '' as $$
  select private.set_melo_verified(target_username, make_verified)
$$;
revoke all on function public.set_melo_verified(text,boolean) from public, anon, authenticated;
grant execute on function public.set_melo_verified(text,boolean) to authenticated;
