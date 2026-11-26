alter table public.melo_channels add column is_private boolean not null default false;
grant insert(is_private) on public.melo_channels to authenticated;
create function private.melo_channel_visible(cid uuid) returns boolean language sql stable security definer set search_path='' as $$
 select private.melo_mfa_ok() and exists(select 1 from public.melo_channels c where c.id=cid and (not c.is_private or c.owner_id=auth.uid() or exists(select 1 from public.melo_channel_subscriptions s where s.channel_id=cid and s.user_id=auth.uid()) or exists(select 1 from public.melo_channel_admins a where a.channel_id=cid and a.user_id=auth.uid())))
$$;
revoke all on function private.melo_channel_visible(uuid) from public,anon,authenticated;
grant execute on function private.melo_channel_visible(uuid) to authenticated;
create policy melo_private_channel_read on public.melo_channels as restrictive for select to authenticated using(not is_private or owner_id=(select auth.uid()) or private.melo_channel_visible(id));
create policy melo_private_post_access on public.melo_channel_posts as restrictive for all to authenticated using(private.melo_channel_visible(channel_id)) with check(private.melo_channel_visible(channel_id));
create policy melo_public_subscription_insert on public.melo_channel_subscriptions as restrictive for insert to authenticated with check(exists(select 1 from public.melo_channels c where c.id=channel_id and not c.is_private));
create policy melo_private_post_access on public.melo_post_comments as restrictive for all to authenticated using(exists(select 1 from public.melo_channel_posts p where p.id=post_id and private.melo_channel_visible(p.channel_id))) with check(exists(select 1 from public.melo_channel_posts p where p.id=post_id and private.melo_channel_visible(p.channel_id)));
create policy melo_private_post_access on public.melo_post_reactions as restrictive for all to authenticated using(exists(select 1 from public.melo_channel_posts p where p.id=post_id and private.melo_channel_visible(p.channel_id))) with check(exists(select 1 from public.melo_channel_posts p where p.id=post_id and private.melo_channel_visible(p.channel_id)));
create policy melo_private_post_access on public.melo_post_views as restrictive for all to authenticated using(exists(select 1 from public.melo_channel_posts p where p.id=post_id and private.melo_channel_visible(p.channel_id))) with check(exists(select 1 from public.melo_channel_posts p where p.id=post_id and private.melo_channel_visible(p.channel_id)));
create or replace function private.melo_view_counts(ids uuid[]) returns table(post_id uuid,views bigint) language sql stable security definer set search_path='' as $$select v.post_id,count(*) from public.melo_post_views v join public.melo_channel_posts p on p.id=v.post_id where private.melo_channel_visible(p.channel_id) and cardinality(ids)<=150 and v.post_id=any(ids) group by v.post_id$$;
create function private.melo_private_member(cid uuid,member uuid,add_member boolean) returns void language plpgsql security definer set search_path='' as $$
begin
 if not private.melo_mfa_ok() or not exists(select 1 from public.melo_channels c where c.id=cid and c.owner_id=auth.uid() and c.is_private) then raise exception 'Channel owner required' using errcode='42501';end if;
 if member=auth.uid() or member is null then raise exception 'Invalid member';end if;
 if add_member then insert into public.melo_channel_subscriptions(channel_id,user_id) values(cid,member) on conflict do nothing;
 else delete from public.melo_channel_admins where channel_id=cid and user_id=member;delete from public.melo_channel_subscriptions where channel_id=cid and user_id=member;end if;
end $$;
revoke all on function private.melo_private_member(uuid,uuid,boolean) from public,anon,authenticated;
grant execute on function private.melo_private_member(uuid,uuid,boolean) to authenticated;
create function public.melo_private_member(cid uuid,member uuid,add_member boolean) returns void language sql security invoker set search_path='' as $$select private.melo_private_member(cid,member,add_member)$$;
revoke all on function public.melo_private_member(uuid,uuid,boolean) from public,anon,authenticated;
grant execute on function public.melo_private_member(uuid,uuid,boolean) to authenticated;
create policy private_channel_owner_subscriber_read on public.melo_channel_subscriptions for select to authenticated using(exists(select 1 from public.melo_channels c where c.id=channel_id and c.owner_id=(select auth.uid()) and c.is_private));
-- Avoid recursive policy evaluation: channel visibility is checked by a private definer.
alter table public.profiles add column emoji_status text not null default '' check(emoji_status in ('','💜','⭐','🔥','🌙','🎧','💻','🎮','✨','🚀','💎','👑','🌈')),
 add column allow_new_chats boolean not null default true,
 add column pinned_gift bigint;
grant update(emoji_status,allow_new_chats,pinned_gift) on public.profiles to authenticated;
create function private.melo_profile_extras_guard() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if new.pinned_gift is not null and not exists(select 1 from public.melo_collectibles c where c.serial=new.pinned_gift and c.recipient_id=new.id) then raise exception 'Gift not owned';end if;
 if new.emoji_status in ('💎','👑','🌈') and not new.plus then raise exception 'Melo Plus required';end if;
 return new;
end $$;
revoke all on function private.melo_profile_extras_guard() from public,anon,authenticated;
create trigger melo_profile_extras_guard before update of pinned_gift,emoji_status on public.profiles for each row execute function private.melo_profile_extras_guard();
create table public.melo_saved(id uuid primary key default gen_random_uuid(),user_id uuid not null references public.profiles(id) on delete cascade,body text not null check(char_length(trim(body)) between 1 and 4096),source_message uuid references public.messages(id) on delete set null,created_at timestamptz not null default now(),unique(user_id,source_message));
alter table public.melo_saved enable row level security;
revoke all on public.melo_saved from public,anon,authenticated;
grant select,delete on public.melo_saved to authenticated;
grant insert(user_id,body,source_message) on public.melo_saved to authenticated;
create policy saved_own_read on public.melo_saved for select to authenticated using(user_id=(select auth.uid()));
create policy saved_own_insert on public.melo_saved for insert to authenticated with check(user_id=(select auth.uid()) and (source_message is null or exists(select 1 from public.messages m where m.id=source_message and m.deleted_at is null)));
create policy saved_own_delete on public.melo_saved for delete to authenticated using(user_id=(select auth.uid()));
create table public.melo_wallet_events(id bigint generated always as identity primary key,user_id uuid not null references public.profiles(id) on delete cascade,delta bigint not null,balance_after bigint not null,kind text not null,created_at timestamptz not null default now());
alter table public.melo_wallet_events enable row level security;
revoke all on public.melo_wallet_events from public,anon,authenticated;
grant select on public.melo_wallet_events to authenticated;
create policy wallet_own_read on public.melo_wallet_events for select to authenticated using(user_id=(select auth.uid()));
insert into public.melo_wallet_events(user_id,delta,balance_after,kind) select user_id,balance,balance,'opening' from public.melo_credits where balance<>0;
create function private.melo_wallet_log() returns trigger language plpgsql security definer set search_path='' as $$
declare diff bigint;
begin
 diff:=new.balance-case when tg_op='INSERT' then 0 else old.balance end;
 if diff<>0 then insert into public.melo_wallet_events(user_id,delta,balance_after,kind) values(new.user_id,diff,new.balance,case when diff>0 then 'credit' else 'purchase' end);end if;
 return new;
end $$;
revoke all on function private.melo_wallet_log() from public,anon,authenticated;
create trigger melo_wallet_log after insert or update of balance on public.melo_credits for each row execute function private.melo_wallet_log();
create table public.melo_themes(id uuid primary key default gen_random_uuid(),user_id uuid not null references public.profiles(id) on delete cascade,name text not null check(char_length(trim(name)) between 1 and 50),accent text not null check(accent ~ '^#[0-9a-fA-F]{6}$'),mode text not null check(mode in ('system','dark','light')),wall text not null check(wall in ('dots','gradient','plain','aurora')),created_at timestamptz not null default now());
alter table public.melo_themes enable row level security;
revoke all on public.melo_themes from public,anon,authenticated;
grant select,delete on public.melo_themes to authenticated;
grant insert(user_id,name,accent,mode,wall) on public.melo_themes to authenticated;
create policy themes_read on public.melo_themes for select to authenticated using(true);
create policy themes_create on public.melo_themes for insert to authenticated with check(user_id=(select auth.uid()));
create policy themes_remove on public.melo_themes for delete to authenticated using(user_id=(select auth.uid()));
create policy melo_require_mfa on public.melo_saved as restrictive for all to authenticated using((select private.melo_mfa_ok())) with check((select private.melo_mfa_ok()));
create policy melo_require_mfa on public.melo_wallet_events as restrictive for all to authenticated using((select private.melo_mfa_ok())) with check((select private.melo_mfa_ok()));
create policy melo_require_mfa on public.melo_themes as restrictive for all to authenticated using((select private.melo_mfa_ok())) with check((select private.melo_mfa_ok()));
create index melo_saved_user_date on public.melo_saved(user_id,created_at desc);
create index melo_wallet_user_date on public.melo_wallet_events(user_id,created_at desc);
create index melo_themes_date on public.melo_themes(created_at desc);