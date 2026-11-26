create table public.melo_channel_admins(channel_id uuid not null references public.melo_channels(id) on delete cascade,user_id uuid not null references public.profiles(id) on delete cascade,primary key(channel_id,user_id));
alter table public.melo_channel_admins enable row level security;
revoke all on public.melo_channel_admins from public,anon,authenticated;
grant select,delete on public.melo_channel_admins to authenticated;
grant insert(channel_id,user_id) on public.melo_channel_admins to authenticated;
create policy channel_admin_read on public.melo_channel_admins for select to authenticated using(user_id=(select auth.uid()) or exists(select 1 from public.melo_channels c where c.id=channel_id and c.owner_id=(select auth.uid())));
create policy channel_admin_add on public.melo_channel_admins for insert to authenticated with check(exists(select 1 from public.melo_channels c where c.id=channel_id and c.owner_id=(select auth.uid()) and c.owner_id<>user_id));
create policy channel_admin_remove on public.melo_channel_admins for delete to authenticated using(exists(select 1 from public.melo_channels c where c.id=channel_id and c.owner_id=(select auth.uid())));
create policy melo_require_mfa on public.melo_channel_admins as restrictive for all to authenticated using((select private.melo_mfa_ok())) with check((select private.melo_mfa_ok()));
create function private.melo_channel_can_post(cid uuid) returns boolean language sql stable security definer set search_path='' as $$select private.melo_mfa_ok() and (exists(select 1 from public.melo_channels c where c.id=cid and c.owner_id=auth.uid()) or exists(select 1 from public.melo_channel_admins a where a.channel_id=cid and a.user_id=auth.uid()))$$;
revoke all on function private.melo_channel_can_post(uuid) from public,anon,authenticated;
grant execute on function private.melo_channel_can_post(uuid) to authenticated;
create policy channel_admin_post_insert on public.melo_channel_posts for insert to authenticated with check(private.melo_channel_can_post(channel_id));
create policy channel_admin_post_edit on public.melo_channel_posts for update to authenticated using(private.melo_channel_can_post(channel_id)) with check(private.melo_channel_can_post(channel_id));
create policy channel_admin_post_delete on public.melo_channel_posts for delete to authenticated using(private.melo_channel_can_post(channel_id));
alter table public.melo_channel_posts add column media_path text,add column media_type text check(media_type in ('image','video')),add constraint melo_post_media_pair check((media_path is null)=(media_type is null));
grant insert(media_path,media_type) on public.melo_channel_posts to authenticated;
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types) values('channel-media','channel-media',false,26214400,array['image/png','image/jpeg','image/webp','image/gif','video/mp4','video/webm']);
create policy melo_channel_media_upload on storage.objects for insert to authenticated with check(bucket_id='channel-media' and split_part(name,'/',2)=(select auth.uid())::text and private.melo_channel_can_post(case when split_part(name,'/',1) ~ '^[0-9a-f-]{36}$' then split_part(name,'/',1)::uuid else null end));
create policy melo_channel_media_read on storage.objects for select to authenticated using(bucket_id='channel-media' and (split_part(name,'/',2)=(select auth.uid())::text or exists(select 1 from public.melo_channel_posts p where p.media_path=name)));
create policy melo_channel_media_delete on storage.objects for delete to authenticated using(bucket_id='channel-media' and split_part(name,'/',2)=(select auth.uid())::text);
create function private.melo_check_post_media() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if new.media_path is null then return new; end if;
 if split_part(new.media_path,'/',1)<>new.channel_id::text or split_part(new.media_path,'/',2)<>coalesce(auth.uid()::text,'') or not exists(select 1 from storage.objects o where o.bucket_id='channel-media' and o.name=new.media_path and (o.metadata->>'mimetype') like new.media_type||'/%') then raise exception 'Invalid media';end if;
 return new;
end $$;
revoke all on function private.melo_check_post_media() from public,anon,authenticated;
create trigger melo_post_media_guard before insert on public.melo_channel_posts for each row execute function private.melo_check_post_media();