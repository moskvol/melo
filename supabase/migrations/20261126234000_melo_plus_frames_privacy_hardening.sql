alter table public.profiles drop constraint profiles_frame_check;
alter table public.profiles add constraint profiles_frame_check check(frame in ('none','violet','mint','gold','aurora','prism'));
create or replace function private.melo_profile_extras_guard() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if new.pinned_gift is not null and not exists(select 1 from public.melo_collectibles c where c.serial=new.pinned_gift and c.recipient_id=new.id) then raise exception 'Gift not owned';end if;
 if not new.plus then
  if old.plus then
   if new.emoji_status in ('💎','👑','🌈') then new.emoji_status:='';end if;
   if new.frame in ('aurora','prism') then new.frame:='none';end if;
  elsif new.emoji_status in ('💎','👑','🌈') or new.frame in ('aurora','prism') then raise exception 'Melo Plus required';end if;
 end if;
 return new;
end $$;
drop trigger melo_profile_extras_guard on public.profiles;
create trigger melo_profile_extras_guard before update of pinned_gift,emoji_status,frame,plus on public.profiles for each row execute function private.melo_profile_extras_guard();
create policy private_channel_media_access on storage.objects as restrictive for select to authenticated using(bucket_id<>'channel-media' or private.melo_channel_visible(case when split_part(name,'/',1) ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then split_part(name,'/',1)::uuid else null end));
-- Restrict direct conversation membership changes to groups.
create policy group_member_insert_only on public.conversation_members as restrictive for insert to authenticated with check(exists(select 1 from public.conversations c where c.id=conversation_id and c.kind='group'));