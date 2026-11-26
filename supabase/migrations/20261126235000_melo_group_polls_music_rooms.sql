alter table public.messages add column poll_options jsonb check(poll_options is null or (jsonb_typeof(poll_options)='array' and jsonb_array_length(poll_options) between 2 and 8));
grant insert(poll_options) on public.messages to authenticated;
create function private.melo_validate_group_poll() returns trigger language plpgsql set search_path='' as $$
begin
 if new.poll_options is not null then
 if new.kind<>'text' or not exists(select 1 from public.conversations c where c.id=new.conversation_id and c.kind='group') or exists(select 1 from jsonb_array_elements(new.poll_options) e where jsonb_typeof(e)<>'string' or char_length(trim(e#>>'{}')) not between 1 and 120) then raise exception 'Invalid group poll';end if;
 end if;
 return new;
end $$;
create trigger melo_validate_group_poll before insert on public.messages for each row execute function private.melo_validate_group_poll();
create table public.melo_group_poll_votes(message_id uuid not null references public.messages(id) on delete cascade,user_id uuid not null references public.profiles(id) on delete cascade,choice integer not null check(choice between 0 and 7),primary key(message_id,user_id));
alter table public.melo_group_poll_votes enable row level security;
revoke all on public.melo_group_poll_votes from public,anon,authenticated;
grant select,delete on public.melo_group_poll_votes to authenticated;
grant insert(message_id,user_id,choice),update(choice) on public.melo_group_poll_votes to authenticated;
create policy group_poll_own_read on public.melo_group_poll_votes for select to authenticated using(user_id=(select auth.uid()));
create policy group_poll_own_insert on public.melo_group_poll_votes for insert to authenticated with check(user_id=(select auth.uid()) and exists(select 1 from public.messages m where m.id=message_id and m.deleted_at is null and m.poll_options is not null and choice<jsonb_array_length(m.poll_options)));
create policy group_poll_own_update on public.melo_group_poll_votes for update to authenticated using(user_id=(select auth.uid())) with check(user_id=(select auth.uid()) and exists(select 1 from public.messages m where m.id=message_id and m.deleted_at is null and m.poll_options is not null and choice<jsonb_array_length(m.poll_options)));
create policy group_poll_own_delete on public.melo_group_poll_votes for delete to authenticated using(user_id=(select auth.uid()));
create policy group_poll_visible on public.melo_group_poll_votes as restrictive for all to authenticated using(exists(select 1 from public.messages m where m.id=message_id and m.deleted_at is null)) with check(exists(select 1 from public.messages m where m.id=message_id and m.deleted_at is null));
create policy melo_require_mfa on public.melo_group_poll_votes as restrictive for all to authenticated using((select private.melo_mfa_ok())) with check((select private.melo_mfa_ok()));
create function private.melo_group_poll_stats(mid uuid) returns jsonb language sql stable security definer set search_path='' as $$
 select jsonb_build_object('counts',coalesce((select jsonb_object_agg(v.choice,v.n) from (select choice,count(*) n from public.melo_group_poll_votes where message_id=mid group by choice) v),'{}'::jsonb),'mine',(select choice from public.melo_group_poll_votes where message_id=mid and user_id=auth.uid())) from public.messages m where m.id=mid and m.poll_options is not null and m.deleted_at is null and private.melo_mfa_ok() and private.is_member(m.conversation_id,auth.uid())
$$;
revoke all on function private.melo_group_poll_stats(uuid) from public,anon,authenticated;
grant execute on function private.melo_group_poll_stats(uuid) to authenticated;
create function public.melo_group_poll_stats(mid uuid) returns jsonb language sql stable security invoker set search_path='' as $$select private.melo_group_poll_stats(mid)$$;
revoke all on function public.melo_group_poll_stats(uuid) from public,anon,authenticated;
grant execute on function public.melo_group_poll_stats(uuid) to authenticated;
create table public.melo_music_rooms(id uuid primary key default gen_random_uuid(),host_id uuid not null references public.profiles(id) on delete cascade,track_id uuid not null references public.melo_music(id) on delete cascade,playing boolean not null default false,position double precision not null default 0 check(position between 0 and 86400),sync_at timestamptz not null default now(),created_at timestamptz not null default now());
create table public.melo_music_room_members(room_id uuid not null references public.melo_music_rooms(id) on delete cascade,user_id uuid not null references public.profiles(id) on delete cascade,primary key(room_id,user_id));
alter table public.melo_music_rooms enable row level security;
alter table public.melo_music_room_members enable row level security;
revoke all on public.melo_music_rooms,public.melo_music_room_members from public,anon,authenticated;
grant select,delete on public.melo_music_rooms,public.melo_music_room_members to authenticated;
grant insert(host_id,track_id),update(playing,position) on public.melo_music_rooms to authenticated;
create function private.melo_music_room_visible(rid uuid) returns boolean language sql stable security definer set search_path='' as $$
 select private.melo_mfa_ok() and exists(select 1 from public.melo_music_rooms r join public.melo_music t on t.id=r.track_id where r.id=rid and (r.host_id=auth.uid() or (t.shared and exists(select 1 from public.melo_music_room_members m where m.room_id=rid and m.user_id=auth.uid()) and not exists(select 1 from public.blocks b where (b.blocker_id=r.host_id and b.blocked_id=auth.uid()) or (b.blocker_id=auth.uid() and b.blocked_id=r.host_id)))))
$$;
revoke all on function private.melo_music_room_visible(uuid) from public,anon,authenticated;
grant execute on function private.melo_music_room_visible(uuid) to authenticated;
create policy room_read on public.melo_music_rooms for select to authenticated using(host_id=(select auth.uid()) or private.melo_music_room_visible(id));
create policy room_create on public.melo_music_rooms for insert to authenticated with check(host_id=(select auth.uid()) and exists(select 1 from public.melo_music t where t.id=track_id and t.shared));
create policy room_edit on public.melo_music_rooms for update to authenticated using(host_id=(select auth.uid())) with check(host_id=(select auth.uid()) and exists(select 1 from public.melo_music t where t.id=track_id and t.shared));
create policy room_close on public.melo_music_rooms for delete to authenticated using(host_id=(select auth.uid()));
create policy room_member_read on public.melo_music_room_members for select to authenticated using(user_id=(select auth.uid()) or exists(select 1 from public.melo_music_rooms r where r.id=room_id and r.host_id=(select auth.uid())));
create policy room_member_leave on public.melo_music_room_members for delete to authenticated using(user_id=(select auth.uid()) or exists(select 1 from public.melo_music_rooms r where r.id=room_id and r.host_id=(select auth.uid())));
create policy melo_require_mfa on public.melo_music_rooms as restrictive for all to authenticated using((select private.melo_mfa_ok())) with check((select private.melo_mfa_ok()));
create policy melo_require_mfa on public.melo_music_room_members as restrictive for all to authenticated using((select private.melo_mfa_ok())) with check((select private.melo_mfa_ok()));
create function private.melo_join_music_room(rid uuid) returns void language plpgsql security definer set search_path='' as $$
declare host uuid;
begin
 if not private.melo_mfa_ok() then raise exception 'Authentication required' using errcode='42501';end if;
 perform pg_advisory_xact_lock(hashtextextended(rid::text,846));
 select r.host_id into host from public.melo_music_rooms r join public.melo_music t on t.id=r.track_id where r.id=rid and t.shared;
 if host is null or exists(select 1 from public.blocks b where (b.blocker_id=host and b.blocked_id=auth.uid()) or (b.blocker_id=auth.uid() and b.blocked_id=host)) then raise exception 'Room unavailable';end if;
 if host=auth.uid() or exists(select 1 from public.melo_music_room_members m where m.room_id=rid and m.user_id=auth.uid()) then return;end if;
 if (select count(*) from public.melo_music_room_members where room_id=rid)>=20 then raise exception 'Room is full';end if;
 insert into public.melo_music_room_members(room_id,user_id) values(rid,auth.uid()) on conflict do nothing;
end $$;
revoke all on function private.melo_join_music_room(uuid) from public,anon,authenticated;
grant execute on function private.melo_join_music_room(uuid) to authenticated;
create function public.melo_join_music_room(rid uuid) returns void language sql security invoker set search_path='' as $$select private.melo_join_music_room(rid)$$;
revoke all on function public.melo_join_music_room(uuid) from public,anon,authenticated;
grant execute on function public.melo_join_music_room(uuid) to authenticated;
create function private.melo_room_sync() returns trigger language plpgsql set search_path='' as $$begin new.sync_at=now();return new;end $$;
create trigger melo_room_sync before update of playing,position on public.melo_music_rooms for each row execute function private.melo_room_sync();
create function private.melo_push_clear_previous() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if old.user_id is distinct from new.user_id or old.session_id is distinct from new.session_id then delete from private.melo_push_jobs where subscription_id=new.id;end if;
 return new;
end $$;
revoke all on function private.melo_push_clear_previous() from public,anon,authenticated;
create trigger melo_push_clear_previous after update of user_id,session_id on private.melo_push_subscriptions for each row execute function private.melo_push_clear_previous();