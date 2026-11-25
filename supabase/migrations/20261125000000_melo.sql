-- Apply in Supabase SQL Editor. All exposed tables have RLS.
create schema if not exists private;
revoke all on schema private from public, anon, authenticated;
grant usage on schema private to authenticated;

create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  username text not null unique check (username ~ '^[a-z][a-z0-9_]{3,23}$'),
  first_name text not null default '' check (char_length(first_name) <= 50),
  last_name text not null default '' check (char_length(last_name) <= 50),
  bio text not null default '' check (char_length(bio) <= 240),
  avatar_path text,
  show_online boolean not null default true,
  show_last_seen boolean not null default true,
  last_seen_at timestamptz,
  created_at timestamptz not null default now()
);
create index profiles_name_idx on public.profiles (lower(first_name), lower(last_name));

create table public.conversations (
  id uuid primary key default gen_random_uuid(),
  kind text not null check (kind in ('direct','group')),
  name text check (char_length(name) <= 80),
  description text check (char_length(description) <= 500),
  avatar_path text,
  owner_id uuid references public.profiles(id) on delete set null,
  invite_token uuid not null default gen_random_uuid() unique,
  only_admins_can_post boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check ((kind = 'direct' and name is null) or (kind = 'group' and nullif(trim(name), '') is not null))
);
create index conversations_updated_idx on public.conversations(updated_at desc);

create table public.conversation_members (
  conversation_id uuid not null references public.conversations(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  role text not null default 'member' check (role in ('owner','admin','member')),
  joined_at timestamptz not null default now(),
  last_read_at timestamptz not null default now(),
  primary key (conversation_id, user_id)
);
create index conversation_members_user_idx on public.conversation_members(user_id, conversation_id);
create or replace function private.normalize_read_receipt() returns trigger language plpgsql set search_path = '' as $$
begin
  if new.last_read_at is distinct from old.last_read_at then
    if new.user_id <> auth.uid() then raise exception 'Cannot mark another member as read'; end if;
    new.last_read_at := now();
  end if;
  return new;
end $$;
create trigger normalize_read_receipt before update on public.conversation_members for each row execute function private.normalize_read_receipt();

create table public.blocks (
  blocker_id uuid not null references public.profiles(id) on delete cascade,
  blocked_id uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (blocker_id, blocked_id), check (blocker_id <> blocked_id)
);
create index blocks_blocked_idx on public.blocks(blocked_id);

create table public.messages (
  id uuid primary key default gen_random_uuid(),
  conversation_id uuid not null references public.conversations(id) on delete cascade,
  sender_id uuid not null references public.profiles(id) on delete cascade,
  body text not null default '' check (char_length(body) <= 4096),
  kind text not null default 'text' check (kind in ('text','image','video','file','voice')),
  attachment_path text,
  attachment_name text,
  attachment_mime text,
  reply_to_id uuid references public.messages(id) on delete set null,
  forwarded_from_id uuid references public.messages(id) on delete set null,
  pinned boolean not null default false,
  reaction_version integer not null default 0,
  edited_at timestamptz,
  deleted_at timestamptz,
  created_at timestamptz not null default now(),
  check (kind = 'text' or attachment_path is not null),
  check (kind <> 'text' or deleted_at is not null or nullif(trim(body), '') is not null)
);
create index messages_chat_time_idx on public.messages(conversation_id, created_at desc);
create index messages_sender_time_idx on public.messages(sender_id, created_at desc);

create table public.reactions (
  message_id uuid not null references public.messages(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  emoji text not null check (char_length(emoji) between 1 and 16),
  created_at timestamptz not null default now(),
  primary key (message_id, user_id, emoji)
);
create index reactions_user_idx on public.reactions(user_id);

create or replace function private.is_member(chat_id uuid, who uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.conversation_members where conversation_id = chat_id and user_id = who)
$$;
create or replace function private.is_admin(chat_id uuid, who uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.conversation_members where conversation_id = chat_id and user_id = who and role in ('owner','admin'))
$$;
create or replace function private.can_send(chat_id uuid, who uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select private.is_member(chat_id, who)
    and not exists (
      select 1 from public.conversation_members other_member
      join public.blocks b on (b.blocker_id = who and b.blocked_id = other_member.user_id)
        or (b.blocked_id = who and b.blocker_id = other_member.user_id)
      where other_member.conversation_id = chat_id and other_member.user_id <> who
      and (select kind from public.conversations where id = chat_id) = 'direct'
    )
    and exists (select 1 from public.conversations c where c.id = chat_id and
      (not c.only_admins_can_post or private.is_admin(chat_id, who)))
$$;
create or replace function private.path_chat_id(path text) returns uuid language plpgsql immutable set search_path = '' as $$
begin return split_part(path,'/',1)::uuid;
exception when invalid_text_representation then return null;
end $$;
revoke all on function private.is_member(uuid,uuid), private.is_admin(uuid,uuid), private.can_send(uuid,uuid), private.path_chat_id(text) from public, anon;
grant execute on function private.is_member(uuid,uuid), private.is_admin(uuid,uuid), private.can_send(uuid,uuid), private.path_chat_id(text) to authenticated;

create or replace function private.new_profile() returns trigger language plpgsql security definer set search_path = '' as $$
begin
  insert into public.profiles(id, username, first_name)
  values (new.id, 'user_' || substr(replace(new.id::text,'-',''),1,16), left(coalesce(new.raw_user_meta_data->>'first_name',''),50));
  return new;
end $$;
create trigger on_auth_user_created after insert on auth.users for each row execute function private.new_profile();

create or replace function private.check_message() returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if tg_op = 'INSERT' then
    if new.sender_id <> auth.uid() or not private.can_send(new.conversation_id, new.sender_id) then
      raise exception 'No permission to send';
    end if;
    if exists (select 1 from public.messages where sender_id = new.sender_id and created_at > now() - interval '1 second') then
      raise exception 'Please wait before sending another message';
    end if;
    if new.attachment_path is not null and split_part(new.attachment_path,'/',1) <> new.conversation_id::text then
      raise exception 'Invalid attachment path';
    end if;
    if new.reply_to_id is not null and not exists (select 1 from public.messages where id = new.reply_to_id and conversation_id = new.conversation_id) then
      raise exception 'Reply must be in this chat';
    end if;
    if new.forwarded_from_id is not null and not exists (select 1 from public.messages where id = new.forwarded_from_id and private.is_member(conversation_id, new.sender_id)) then
      raise exception 'Cannot forward this message';
    end if;
    new.created_at := now();
    new.edited_at := null;
    new.deleted_at := null;
    new.pinned := false;
  else
    if new.id <> old.id or new.sender_id <> old.sender_id or new.conversation_id <> old.conversation_id
      or new.created_at <> old.created_at or new.kind <> old.kind or new.attachment_path is distinct from old.attachment_path
      or new.reply_to_id is distinct from old.reply_to_id or new.forwarded_from_id is distinct from old.forwarded_from_id then
      raise exception 'Message identity cannot change';
    end if;
    if new.pinned is distinct from old.pinned and not private.is_admin(old.conversation_id, auth.uid()) then
      raise exception 'Only admins can pin messages';
    end if;
    if (new.body is distinct from old.body or new.deleted_at is distinct from old.deleted_at) and old.sender_id <> auth.uid() then
      raise exception 'Only the sender can edit or delete';
    end if;
    if old.deleted_at is not null and new.deleted_at is distinct from old.deleted_at then raise exception 'Cannot restore a deleted message'; end if;
    if new.deleted_at is not null then new.body := ''; end if;
    if new.body is distinct from old.body then new.edited_at := now(); end if;
  end if;
  return new;
end $$;
create trigger validate_message before insert or update on public.messages for each row execute function private.check_message();
create or replace function private.bump_chat() returns trigger language plpgsql security definer set search_path = '' as $$
begin update public.conversations set updated_at = now() where id = new.conversation_id; return new; end $$;
create trigger message_bumps_chat after insert on public.messages for each row execute function private.bump_chat();
create or replace function private.touch_message_delete() returns trigger language plpgsql security definer set search_path = '' as $$
begin update public.conversations set updated_at = now() where id = old.conversation_id; return old; end $$;
create trigger deleted_message_bumps_chat after delete on public.messages for each row execute function private.touch_message_delete();
create or replace function private.touch_membership() returns trigger language plpgsql security definer set search_path = '' as $$
begin update public.conversations set updated_at = now() where id = coalesce(new.conversation_id, old.conversation_id); return coalesce(new, old); end $$;
create trigger membership_bumps_chat after insert or delete on public.conversation_members for each row execute function private.touch_membership();
create or replace function private.touch_reaction() returns trigger language plpgsql security definer set search_path = '' as $$
begin update public.messages set reaction_version = reaction_version + 1 where id = coalesce(new.message_id, old.message_id); return coalesce(new,old); end $$;
create trigger reaction_bumps_message after insert or delete on public.reactions for each row execute function private.touch_reaction();

alter table public.profiles enable row level security;
alter table public.conversations enable row level security;
alter table public.conversation_members enable row level security;
alter table public.blocks enable row level security;
alter table public.messages enable row level security;
alter table public.reactions enable row level security;

create policy profiles_read on public.profiles for select to authenticated using (true);
create policy profiles_update on public.profiles for update to authenticated using (id = (select auth.uid())) with check (id = (select auth.uid()));
create policy chats_read on public.conversations for select to authenticated using (private.is_member(id, (select auth.uid())));
create policy chats_update on public.conversations for update to authenticated using (private.is_admin(id, (select auth.uid()))) with check (private.is_admin(id, (select auth.uid())));
create policy members_read on public.conversation_members for select to authenticated using (private.is_member(conversation_id, (select auth.uid())));
create policy members_add on public.conversation_members for insert to authenticated with check (private.is_admin(conversation_id, (select auth.uid())) and role = 'member');
create policy members_leave on public.conversation_members for delete to authenticated using (user_id = (select auth.uid()) and role <> 'owner');
create policy members_read_update on public.conversation_members for update to authenticated using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));
create policy blocks_read on public.blocks for select to authenticated using (blocker_id = (select auth.uid()));
create policy blocks_add on public.blocks for insert to authenticated with check (blocker_id = (select auth.uid()));
create policy blocks_remove on public.blocks for delete to authenticated using (blocker_id = (select auth.uid()));
create policy messages_read on public.messages for select to authenticated using (private.is_member(conversation_id, (select auth.uid())));
create policy messages_add on public.messages for insert to authenticated with check (sender_id = (select auth.uid()) and private.can_send(conversation_id, (select auth.uid())));
create policy messages_update on public.messages for update to authenticated using (private.is_member(conversation_id, (select auth.uid())) and (sender_id = (select auth.uid()) or private.is_admin(conversation_id, (select auth.uid())))) with check (private.is_member(conversation_id, (select auth.uid())));
create policy reactions_read on public.reactions for select to authenticated using (exists (select 1 from public.messages m where m.id = message_id and private.is_member(m.conversation_id, (select auth.uid()))));
create policy reactions_add on public.reactions for insert to authenticated with check (user_id = (select auth.uid()) and exists (select 1 from public.messages m where m.id = message_id and private.is_member(m.conversation_id, (select auth.uid()))));
create policy reactions_remove on public.reactions for delete to authenticated using (user_id = (select auth.uid()));

revoke all on public.profiles, public.conversations, public.conversation_members, public.blocks, public.messages, public.reactions from anon, authenticated;
grant select on public.profiles, public.conversations, public.conversation_members, public.blocks, public.messages, public.reactions to authenticated;
grant update (username, first_name, last_name, bio, avatar_path, show_online, show_last_seen, last_seen_at) on public.profiles to authenticated;
grant update (name, description, avatar_path, only_admins_can_post) on public.conversations to authenticated;
grant update (last_read_at) on public.conversation_members to authenticated;
grant insert, delete on public.blocks, public.reactions to authenticated;
grant insert on public.conversation_members to authenticated;
grant delete on public.conversation_members to authenticated;
grant insert on public.messages to authenticated;
grant update (body, pinned, deleted_at) on public.messages to authenticated;

create or replace function public.create_direct_chat(other_user uuid) returns uuid language plpgsql security definer set search_path = '' as $$
declare chat_id uuid; me uuid := auth.uid();
begin
  if me is null or other_user = me or not exists (select 1 from public.profiles where id = other_user) then raise exception 'Invalid recipient'; end if;
  if exists (select 1 from public.blocks where (blocker_id = me and blocked_id = other_user) or (blocker_id = other_user and blocked_id = me)) then raise exception 'Conversation unavailable'; end if;
  perform pg_advisory_xact_lock(hashtext(least(me::text,other_user::text) || greatest(me::text,other_user::text)));
  select c.id into chat_id from public.conversations c
  join public.conversation_members a on a.conversation_id = c.id and a.user_id = me
  join public.conversation_members b on b.conversation_id = c.id and b.user_id = other_user
  where c.kind = 'direct' limit 1;
  if chat_id is not null then return chat_id; end if;
  insert into public.conversations(kind, owner_id) values ('direct', me) returning id into chat_id;
  insert into public.conversation_members(conversation_id,user_id) values (chat_id,me),(chat_id,other_user);
  return chat_id;
end $$;
create or replace function public.create_group_chat(group_name text, group_description text default '') returns uuid language plpgsql security definer set search_path = '' as $$
declare chat_id uuid; me uuid := auth.uid();
begin
  if me is null or nullif(trim(group_name),'') is null or char_length(group_name) > 80 then raise exception 'Invalid group name'; end if;
  insert into public.conversations(kind,name,description,owner_id) values ('group',trim(group_name),left(coalesce(group_description,''),500),me) returning id into chat_id;
  insert into public.conversation_members(conversation_id,user_id,role) values (chat_id,me,'owner');
  return chat_id;
end $$;
create or replace function public.join_group(invite uuid) returns uuid language plpgsql security definer set search_path = '' as $$
declare chat_id uuid; me uuid := auth.uid();
begin
  if me is null then raise exception 'Sign in first'; end if;
  select id into chat_id from public.conversations where invite_token = invite and kind = 'group';
  if chat_id is null then raise exception 'Invalid invitation'; end if;
  if (select count(*) from public.conversation_members where conversation_id = chat_id) >= 200 then raise exception 'Group is full'; end if;
  insert into public.conversation_members(conversation_id,user_id) values (chat_id,me) on conflict do nothing;
  return chat_id;
end $$;
create or replace function public.remove_group_member(chat_id uuid, member_id uuid) returns void language plpgsql security definer set search_path = '' as $$
begin
  if auth.uid() is null or not private.is_admin(chat_id,auth.uid()) or (select kind from public.conversations where id=chat_id) <> 'group' then raise exception 'Admins only'; end if;
  if (select role from public.conversation_members where conversation_id=chat_id and user_id=member_id) = 'owner' then raise exception 'Cannot remove owner'; end if;
  delete from public.conversation_members where conversation_id=chat_id and user_id=member_id;
end $$;
create or replace function public.set_group_admin(chat_id uuid, member_id uuid, make_admin boolean) returns void language plpgsql security definer set search_path = '' as $$
begin
  if auth.uid() is null or (select owner_id from public.conversations where id=chat_id and kind='group') is distinct from auth.uid() then raise exception 'Owner only'; end if;
  update public.conversation_members set role = case when make_admin then 'admin' else 'member' end where conversation_id=chat_id and user_id=member_id and role <> 'owner';
end $$;
create or replace function public.leave_group(chat_id uuid) returns void language plpgsql security definer set search_path = '' as $$
declare me uuid := auth.uid(); successor uuid;
begin
  if me is null or (select kind from public.conversations where id = chat_id) <> 'group' or not private.is_member(chat_id, me) then raise exception 'Not a group member'; end if;
  if (select owner_id from public.conversations where id = chat_id) = me then
    select user_id into successor from public.conversation_members where conversation_id = chat_id and user_id <> me
      order by case role when 'admin' then 0 else 1 end, joined_at limit 1;
    if successor is null then delete from public.conversations where id = chat_id; return; end if;
    update public.conversations set owner_id = successor where id = chat_id;
    update public.conversation_members set role = 'owner' where conversation_id = chat_id and user_id = successor;
  end if;
  delete from public.conversation_members where conversation_id = chat_id and user_id = me;
end $$;
create or replace function public.delete_my_account() returns void language plpgsql security definer set search_path = '' as $$
declare item record; successor uuid;
begin
  if auth.uid() is null then raise exception 'Sign in first'; end if;
  for item in select id from public.conversations where kind = 'group' and owner_id = auth.uid() loop
    select user_id into successor from public.conversation_members
      where conversation_id = item.id and user_id <> auth.uid()
      order by case role when 'admin' then 0 else 1 end, joined_at limit 1;
    if successor is null then
      delete from public.conversations where id = item.id;
    else
      update public.conversations set owner_id = successor where id = item.id;
      update public.conversation_members set role = 'owner' where conversation_id = item.id and user_id = successor;
    end if;
  end loop;
  delete from auth.users where id = auth.uid();
end $$;
revoke all on function public.create_direct_chat(uuid), public.create_group_chat(text,text), public.join_group(uuid), public.remove_group_member(uuid,uuid), public.set_group_admin(uuid,uuid,boolean), public.leave_group(uuid), public.delete_my_account() from public, anon;
grant execute on function public.create_direct_chat(uuid), public.create_group_chat(text,text), public.join_group(uuid), public.remove_group_member(uuid,uuid), public.set_group_admin(uuid,uuid,boolean), public.leave_group(uuid), public.delete_my_account() to authenticated;

insert into storage.buckets (id,name,public,file_size_limit,allowed_mime_types)
values ('avatars','avatars',true,5242880,array['image/jpeg','image/png','image/webp','image/gif']) on conflict (id) do nothing;
insert into storage.buckets (id,name,public,file_size_limit)
values ('chat-files','chat-files',false,26214400) on conflict (id) do nothing;
create policy avatar_upload on storage.objects for insert to authenticated with check (bucket_id='avatars' and split_part(name,'/',1)=(select auth.uid())::text);
create policy avatar_update on storage.objects for update to authenticated using (bucket_id='avatars' and split_part(name,'/',1)=(select auth.uid())::text) with check (bucket_id='avatars' and split_part(name,'/',1)=(select auth.uid())::text);
create policy avatar_delete on storage.objects for delete to authenticated using (bucket_id='avatars' and split_part(name,'/',1)=(select auth.uid())::text);
create policy file_read on storage.objects for select to authenticated using (bucket_id='chat-files' and private.is_member(private.path_chat_id(name),(select auth.uid())));
create policy file_upload on storage.objects for insert to authenticated with check (bucket_id='chat-files' and split_part(name,'/',2)=(select auth.uid())::text and private.can_send(private.path_chat_id(name),(select auth.uid())));
create policy file_delete on storage.objects for delete to authenticated using (bucket_id='chat-files' and split_part(name,'/',2)=(select auth.uid())::text);

alter publication supabase_realtime add table public.messages, public.conversation_members, public.conversations;

create policy chat_typing_read on realtime.messages for select to authenticated
using (extension = 'broadcast' and (select realtime.topic()) ~ '^typing-[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
  and private.is_member(substring((select realtime.topic()) from 8)::uuid, (select auth.uid())));
create policy chat_typing_write on realtime.messages for insert to authenticated
with check (extension = 'broadcast' and (select realtime.topic()) ~ '^typing-[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
  and private.is_member(substring((select realtime.topic()) from 8)::uuid, (select auth.uid())));
create policy user_changes_read on realtime.messages for select to authenticated
using ((select realtime.topic()) = 'changes-' || (select auth.uid())::text);
