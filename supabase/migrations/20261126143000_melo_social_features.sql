-- Melo 2: cosmetic profiles, administrator awards, public channels, stories and chat organization.
alter table public.profiles add column if not exists plus boolean not null default false,
 add column if not exists rare_badge text not null default '' check (rare_badge in ('','founder','developer','tester','legend')),
 add column if not exists banner_path text,
 add column if not exists frame text not null default 'none' check (frame in ('none','violet','mint','gold'));
grant update(banner_path,frame) on public.profiles to authenticated;

alter table public.conversation_members add column if not exists archived boolean not null default false,
 add column if not exists folder text not null default '' check (char_length(folder)<=40);
grant update(archived,folder) on public.conversation_members to authenticated;

create or replace function private.set_melo_awards(target_username text, make_plus boolean, badge text)
returns void language plpgsql security definer set search_path='' as $$
begin
 if auth.uid() is null or not exists(select 1 from public.melo_admins where user_id=auth.uid()) then
  raise exception 'Administrator access required' using errcode='42501';
 end if;
 if badge not in ('','founder','developer','tester','legend') then raise exception 'Invalid badge'; end if;
 update public.profiles set plus=make_plus, rare_badge=badge where username=lower(trim(leading '@' from trim(target_username)));
 if not found then raise exception 'Username not found'; end if;
end $$;
revoke all on function private.set_melo_awards(text,boolean,text) from public,anon,authenticated;
grant execute on function private.set_melo_awards(text,boolean,text) to authenticated;
create or replace function public.set_melo_awards(target_username text, make_plus boolean, badge text)
returns void language sql security invoker set search_path='' as $$select private.set_melo_awards(target_username,make_plus,badge)$$;
revoke all on function public.set_melo_awards(text,boolean,text) from public,anon,authenticated;
grant execute on function public.set_melo_awards(text,boolean,text) to authenticated;

create table public.melo_channels(
 id uuid primary key default gen_random_uuid(), owner_id uuid not null references public.profiles(id) on delete cascade,
 name text not null check(char_length(trim(name)) between 1 and 80), description text not null default '' check(char_length(description)<=500),
 created_at timestamptz not null default now()
);
create table public.melo_channel_posts(
 id uuid primary key default gen_random_uuid(), channel_id uuid not null references public.melo_channels(id) on delete cascade,
 body text not null check(char_length(trim(body)) between 1 and 4096), created_at timestamptz not null default now()
);
create index melo_channel_posts_channel on public.melo_channel_posts(channel_id,created_at desc);
create table public.melo_stories(
 id uuid primary key default gen_random_uuid(), user_id uuid not null references public.profiles(id) on delete cascade,
 body text not null check(char_length(trim(body)) between 1 and 500), created_at timestamptz not null default now(),
 expires_at timestamptz not null default (now()+interval '24 hours')
);

create index melo_stories_expiry on public.melo_stories(expires_at);
alter table public.melo_channels enable row level security;
alter table public.melo_channel_posts enable row level security;
alter table public.melo_stories enable row level security;
revoke all on public.melo_channels,public.melo_channel_posts,public.melo_stories from public,anon,authenticated;
grant select,delete on public.melo_channels,public.melo_channel_posts,public.melo_stories to authenticated;
grant insert(owner_id,name,description) on public.melo_channels to authenticated;
grant update(name,description) on public.melo_channels to authenticated;
grant insert(channel_id,body) on public.melo_channel_posts to authenticated;
grant insert(user_id,body) on public.melo_stories to authenticated;
create policy channel_read on public.melo_channels for select to authenticated using(true);
create policy channel_create on public.melo_channels for insert to authenticated with check(owner_id=(select auth.uid()));
create policy channel_edit on public.melo_channels for update to authenticated using(owner_id=(select auth.uid())) with check(owner_id=(select auth.uid()));
create policy channel_delete on public.melo_channels for delete to authenticated using(owner_id=(select auth.uid()));
create policy channel_post_read on public.melo_channel_posts for select to authenticated using(true);
create policy channel_post_create on public.melo_channel_posts for insert to authenticated with check(exists(select 1 from public.melo_channels c where c.id=channel_id and c.owner_id=(select auth.uid())));
create policy channel_post_delete on public.melo_channel_posts for delete to authenticated using(exists(select 1 from public.melo_channels c where c.id=channel_id and c.owner_id=(select auth.uid())));
create policy story_read on public.melo_stories for select to authenticated using(expires_at>now() and not exists(select 1 from public.blocks b where b.blocker_id=(select auth.uid()) and b.blocked_id=user_id));
create policy story_add on public.melo_stories for insert to authenticated with check(user_id=(select auth.uid()));
create policy story_delete on public.melo_stories for delete to authenticated using(user_id=(select auth.uid()));
alter publication supabase_realtime add table public.melo_channels,public.melo_channel_posts,public.melo_stories;
