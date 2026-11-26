alter table public.melo_channels add column username text not null default ('channel_'||left(replace(gen_random_uuid()::text,'-',''),16)), add column avatar_path text, add column subscriber_count integer not null default 0 check(subscriber_count>=0), add column latest_post text, add column latest_post_at timestamptz;
alter table public.melo_channels add constraint melo_channel_username_format check(username ~ '^[a-z][a-z0-9_]{3,31}$');
create unique index melo_channel_username_unique on public.melo_channels(username);
grant insert(username,avatar_path) on public.melo_channels to authenticated;
grant update(username,avatar_path) on public.melo_channels to authenticated;
create table public.melo_channel_subscriptions(channel_id uuid not null references public.melo_channels(id) on delete cascade,user_id uuid not null references public.profiles(id) on delete cascade,created_at timestamptz not null default now(),primary key(channel_id,user_id));
create index melo_channel_subscriptions_user on public.melo_channel_subscriptions(user_id);
alter table public.melo_channel_subscriptions enable row level security;
revoke all on public.melo_channel_subscriptions from public,anon,authenticated;
grant select,delete on public.melo_channel_subscriptions to authenticated;
grant insert(channel_id,user_id) on public.melo_channel_subscriptions to authenticated;
create policy own_channel_subscriptions_read on public.melo_channel_subscriptions for select to authenticated using(user_id=(select auth.uid()));
create policy own_channel_subscriptions_create on public.melo_channel_subscriptions for insert to authenticated with check(user_id=(select auth.uid()));
create policy own_channel_subscriptions_remove on public.melo_channel_subscriptions for delete to authenticated using(user_id=(select auth.uid()));
create function private.melo_channel_count_change() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if tg_op='INSERT' then update public.melo_channels set subscriber_count=subscriber_count+1 where id=new.channel_id;
 else update public.melo_channels set subscriber_count=greatest(0,subscriber_count-1) where id=old.channel_id; end if;
 return null;
end $$;
revoke all on function private.melo_channel_count_change() from public,anon,authenticated;
create trigger melo_channel_count_change after insert or delete on public.melo_channel_subscriptions for each row execute function private.melo_channel_count_change();
create function private.melo_channel_latest_change() returns trigger language plpgsql security definer set search_path='' as $$
declare cid uuid; begin
 if tg_op='DELETE' then cid=old.channel_id; else cid=new.channel_id; end if;
 perform 1 from public.melo_channels where id=cid for update;
 update public.melo_channels c set (latest_post,latest_post_at)=(select p.body,p.created_at from public.melo_channel_posts p where p.channel_id=cid order by p.created_at desc,p.id desc limit 1) where c.id=cid;
 return null;
end $$;
revoke all on function private.melo_channel_latest_change() from public,anon,authenticated;
create trigger melo_channel_latest_change after insert or delete on public.melo_channel_posts for each row execute function private.melo_channel_latest_change();
update public.melo_channels c set (latest_post,latest_post_at)=(select p.body,p.created_at from public.melo_channel_posts p where p.channel_id=c.id order by p.created_at desc,p.id desc limit 1);
alter publication supabase_realtime add table public.melo_channel_subscriptions;