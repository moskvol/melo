-- Display-only administrator marker, derived exclusively from the trusted role table.
alter table public.profiles add column is_melo_admin boolean not null default false;
update public.profiles p set is_melo_admin=exists(select 1 from public.melo_admins a where a.user_id=p.id);
create or replace function private.sync_melo_admin_marker()
returns trigger language plpgsql security definer set search_path='' as $$
begin
  if tg_op in ('DELETE','UPDATE') then
    update public.profiles set is_melo_admin=false where id=old.user_id;
  end if;
  if tg_op in ('INSERT','UPDATE') then
    update public.profiles set is_melo_admin=true where id=new.user_id;
  end if;
  return null;
end $$;
revoke all on function private.sync_melo_admin_marker() from public,anon,authenticated;
create trigger sync_melo_admin_marker after insert or update or delete on public.melo_admins
for each row execute function private.sync_melo_admin_marker();
revoke update(is_melo_admin) on public.profiles from anon,authenticated;
