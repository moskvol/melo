alter table public.melo_admins add column is_owner boolean not null default false;
update public.melo_admins a set is_owner=true from public.profiles p where p.id=a.user_id and p.username='test';
create unique index melo_single_owner on public.melo_admins(is_owner) where is_owner;
revoke insert,update,delete,truncate on public.melo_admins from public,anon,authenticated;
grant select(is_owner) on public.melo_admins to authenticated;

create function private.set_melo_admin(target_id uuid, make_admin boolean)
returns boolean language plpgsql security definer set search_path='' as $$
begin
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
end $$;
revoke all on function private.set_melo_admin(uuid,boolean) from public,anon,authenticated;
grant execute on function private.set_melo_admin(uuid,boolean) to authenticated;
create function public.set_melo_admin(target_id uuid, make_admin boolean)
returns boolean language sql security invoker set search_path='' as $$select private.set_melo_admin(target_id,make_admin)$$;
revoke all on function public.set_melo_admin(uuid,boolean) from public,anon,authenticated;
grant execute on function public.set_melo_admin(uuid,boolean) to authenticated;

create function public.set_melo_block(target_id uuid, make_blocked boolean)
returns boolean language plpgsql security invoker set search_path='' as $$
begin
 if auth.uid() is null then raise exception 'Authentication required' using errcode='42501'; end if;
 if target_id is null or target_id=auth.uid() or make_blocked is null then raise exception 'Invalid block request'; end if;
 if make_blocked then insert into public.blocks(blocker_id,blocked_id) values(auth.uid(),target_id) on conflict(blocker_id,blocked_id) do nothing;
 else delete from public.blocks where blocker_id=auth.uid() and blocked_id=target_id; end if;
 return make_blocked;
end $$;
revoke all on function public.set_melo_block(uuid,boolean) from public,anon,authenticated;
grant execute on function public.set_melo_block(uuid,boolean) to authenticated;