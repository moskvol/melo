-- Storage removal and replacement need the owner to select their own object.
create policy avatar_owner_read on storage.objects for select to authenticated
using (bucket_id = 'avatars' and split_part(name, '/', 1) = (select auth.uid())::text);
