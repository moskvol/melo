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
  if not exists(select 1 from public.profiles where id=other_user and allow_new_chats) then raise exception 'Этот пользователь не принимает новые личные чаты'; end if;
  insert into public.conversations(kind, owner_id) values ('direct', me) returning id into chat_id;
  insert into public.conversation_members(conversation_id,user_id) values (chat_id,me),(chat_id,other_user);
  return chat_id;
end $function$
;
alter table public.melo_channel_posts add column poll_options jsonb check(poll_options is null or (jsonb_typeof(poll_options)='array' and jsonb_array_length(poll_options) between 2 and 8));
grant insert(poll_options) on public.melo_channel_posts to authenticated;
create table public.melo_poll_votes(post_id uuid not null references public.melo_channel_posts(id) on delete cascade,user_id uuid not null references public.profiles(id) on delete cascade,choice integer not null check(choice between 0 and 7),primary key(post_id,user_id));
alter table public.melo_poll_votes enable row level security;
revoke all on public.melo_poll_votes from public,anon,authenticated;
grant select,delete on public.melo_poll_votes to authenticated;
grant insert(post_id,user_id,choice),update(choice) on public.melo_poll_votes to authenticated;
create policy poll_own_read on public.melo_poll_votes for select to authenticated using(user_id=(select auth.uid()));
create policy poll_own_insert on public.melo_poll_votes for insert to authenticated with check(user_id=(select auth.uid()) and exists(select 1 from public.melo_channel_posts p where p.id=post_id and p.poll_options is not null and choice<jsonb_array_length(p.poll_options)));
create policy poll_own_update on public.melo_poll_votes for update to authenticated using(user_id=(select auth.uid())) with check(user_id=(select auth.uid()) and exists(select 1 from public.melo_channel_posts p where p.id=post_id and p.poll_options is not null and choice<jsonb_array_length(p.poll_options)));
create policy poll_own_delete on public.melo_poll_votes for delete to authenticated using(user_id=(select auth.uid()));
create policy poll_visible on public.melo_poll_votes as restrictive for all to authenticated using(exists(select 1 from public.melo_channel_posts p where p.id=post_id)) with check(exists(select 1 from public.melo_channel_posts p where p.id=post_id));
create function private.melo_poll_stats(pid uuid) returns jsonb language sql stable security definer set search_path='' as $$
 select jsonb_build_object('counts',coalesce((select jsonb_object_agg(v.choice,v.n) from (select choice,count(*) n from public.melo_poll_votes where post_id=pid group by choice) v),'{}'::jsonb),'mine',(select choice from public.melo_poll_votes where post_id=pid and user_id=auth.uid())) from public.melo_channel_posts p where p.id=pid and p.poll_options is not null and private.melo_channel_visible(p.channel_id)
$$;
revoke all on function private.melo_poll_stats(uuid) from public,anon,authenticated;
grant execute on function private.melo_poll_stats(uuid) to authenticated;
create function public.melo_poll_stats(pid uuid) returns jsonb language sql stable security invoker set search_path='' as $$select private.melo_poll_stats(pid)$$;
revoke all on function public.melo_poll_stats(uuid) from public,anon,authenticated;
grant execute on function public.melo_poll_stats(uuid) to authenticated;
create function private.melo_validate_poll() returns trigger language plpgsql set search_path='' as $$
begin
 if new.poll_options is not null and exists(select 1 from jsonb_array_elements(new.poll_options) e where jsonb_typeof(e)<>'string' or char_length(trim(e#>>'{}')) not between 1 and 120) then raise exception 'Invalid poll options';end if;
 return new;
end $$;
create trigger melo_validate_poll before insert on public.melo_channel_posts for each row execute function private.melo_validate_poll();
create table public.melo_music(id uuid primary key default gen_random_uuid(),user_id uuid not null references public.profiles(id) on delete cascade,title text not null check(char_length(trim(title)) between 1 and 80),artist text not null default '' check(char_length(artist)<=80),path text not null unique,shared boolean not null default false,created_at timestamptz not null default now(),check(split_part(path,'/',1)=user_id::text));
create table public.melo_sticker_packs(id uuid primary key default gen_random_uuid(),user_id uuid not null references public.profiles(id) on delete cascade,name text not null check(char_length(trim(name)) between 1 and 50),created_at timestamptz not null default now());
create table public.melo_stickers(id uuid primary key default gen_random_uuid(),pack_id uuid not null references public.melo_sticker_packs(id) on delete cascade,user_id uuid not null references public.profiles(id) on delete cascade,path text not null unique,label text not null check(char_length(trim(label)) between 1 and 40),created_at timestamptz not null default now(),check(split_part(path,'/',1)=user_id::text));
alter table public.melo_music enable row level security;revoke all on public.melo_music from public,anon,authenticated;grant select,delete on public.melo_music to authenticated;create policy melo_own_remove on public.melo_music for delete to authenticated using(user_id=(select auth.uid()));
alter table public.melo_sticker_packs enable row level security;revoke all on public.melo_sticker_packs from public,anon,authenticated;grant select,delete on public.melo_sticker_packs to authenticated;create policy melo_own_remove on public.melo_sticker_packs for delete to authenticated using(user_id=(select auth.uid()));
alter table public.melo_stickers enable row level security;revoke all on public.melo_stickers from public,anon,authenticated;grant select,delete on public.melo_stickers to authenticated;create policy melo_own_remove on public.melo_stickers for delete to authenticated using(user_id=(select auth.uid()));
grant insert(user_id,title,artist,path,shared),update(shared,title,artist) on public.melo_music to authenticated;
grant insert(user_id,name) on public.melo_sticker_packs to authenticated;
grant insert(pack_id,user_id,path,label) on public.melo_stickers to authenticated;
create policy music_read on public.melo_music for select to authenticated using(shared or user_id=(select auth.uid()));
create policy music_insert on public.melo_music for insert to authenticated with check(user_id=(select auth.uid()));
create policy music_edit on public.melo_music for update to authenticated using(user_id=(select auth.uid())) with check(user_id=(select auth.uid()));
create policy packs_read on public.melo_sticker_packs for select to authenticated using(true);
create policy packs_create on public.melo_sticker_packs for insert to authenticated with check(user_id=(select auth.uid()));
create policy stickers_read on public.melo_stickers for select to authenticated using(true);
create policy stickers_create on public.melo_stickers for insert to authenticated with check(user_id=(select auth.uid()) and exists(select 1 from public.melo_sticker_packs p where p.id=pack_id and p.user_id=(select auth.uid())));
create policy melo_require_mfa on public.melo_poll_votes as restrictive for all to authenticated using((select private.melo_mfa_ok())) with check((select private.melo_mfa_ok()));
create policy melo_require_mfa on public.melo_music as restrictive for all to authenticated using((select private.melo_mfa_ok())) with check((select private.melo_mfa_ok()));
create policy melo_require_mfa on public.melo_sticker_packs as restrictive for all to authenticated using((select private.melo_mfa_ok())) with check((select private.melo_mfa_ok()));
create policy melo_require_mfa on public.melo_stickers as restrictive for all to authenticated using((select private.melo_mfa_ok())) with check((select private.melo_mfa_ok()));
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types) values('melo-music','melo-music',false,15728640,array['audio/mpeg','audio/mp4','audio/ogg','audio/wav','audio/webm']),('melo-stickers','melo-stickers',false,2097152,array['image/png','image/webp','image/gif']);
create policy melo_assets_upload on storage.objects for insert to authenticated with check(bucket_id in ('melo-music','melo-stickers') and split_part(name,'/',1)=(select auth.uid())::text);
create policy melo_assets_delete on storage.objects for delete to authenticated using(bucket_id in ('melo-music','melo-stickers') and split_part(name,'/',1)=(select auth.uid())::text);
create policy melo_assets_read on storage.objects for select to authenticated using((bucket_id='melo-music' and (split_part(name,'/',1)=(select auth.uid())::text or exists(select 1 from public.melo_music m where m.path=name and m.shared))) or (bucket_id='melo-stickers' and (split_part(name,'/',1)=(select auth.uid())::text or exists(select 1 from public.melo_stickers s where s.path=name))));
create index melo_music_user_date on public.melo_music(user_id,created_at desc);
create index melo_stickers_pack on public.melo_stickers(pack_id);
create index melo_stickers_user on public.melo_stickers(user_id);