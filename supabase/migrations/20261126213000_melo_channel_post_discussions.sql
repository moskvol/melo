create table public.melo_post_reactions (
 post_id uuid not null references public.melo_channel_posts(id) on delete cascade,
 user_id uuid not null references public.profiles(id) on delete cascade,
 emoji text not null check(emoji in ('👍','❤️','🔥','😂','😮','😢','👎','🎉')),
 primary key(post_id,user_id)
);
create table public.melo_post_comments (
 id uuid primary key default gen_random_uuid(),
 post_id uuid not null references public.melo_channel_posts(id) on delete cascade,
 user_id uuid not null references public.profiles(id) on delete cascade,
 body text not null check(char_length(trim(body)) between 1 and 2000),
 created_at timestamptz not null default now()
);
create index melo_post_comments_post_time on public.melo_post_comments(post_id,created_at desc);
create index melo_post_comments_author on public.melo_post_comments(user_id);
create index melo_post_reactions_author on public.melo_post_reactions(user_id);
alter table public.melo_post_reactions enable row level security;
alter table public.melo_post_comments enable row level security;
revoke all on public.melo_post_reactions,public.melo_post_comments from public,anon,authenticated;
grant select,delete on public.melo_post_reactions,public.melo_post_comments to authenticated;
grant insert(post_id,user_id,emoji),update(emoji) on public.melo_post_reactions to authenticated;
grant insert(post_id,user_id,body) on public.melo_post_comments to authenticated;
create policy post_reactions_read on public.melo_post_reactions for select to authenticated using(true);
create policy post_reactions_insert on public.melo_post_reactions for insert to authenticated with check(user_id=(select auth.uid()));
create policy post_reactions_update on public.melo_post_reactions for update to authenticated using(user_id=(select auth.uid())) with check(user_id=(select auth.uid()));
create policy post_reactions_delete on public.melo_post_reactions for delete to authenticated using(user_id=(select auth.uid()));
create policy post_comments_read on public.melo_post_comments for select to authenticated using(true);
create policy post_comments_insert on public.melo_post_comments for insert to authenticated with check(user_id=(select auth.uid()));
create policy post_comments_delete on public.melo_post_comments for delete to authenticated using(user_id=(select auth.uid()) or exists(select 1 from public.melo_channel_posts p join public.melo_channels c on c.id=p.channel_id where p.id=melo_post_comments.post_id and c.owner_id=(select auth.uid())));
create function public.melo_post_stats(post_ids uuid[]) returns table(post_id uuid,reactions jsonb,my_emoji text,comment_count bigint)
language sql stable security invoker set search_path='' as $$
 select p.id,coalesce((select jsonb_object_agg(r.emoji,r.n) from (select emoji,count(*) n from public.melo_post_reactions where post_id=p.id group by emoji) r),'{}'::jsonb),
 (select r.emoji from public.melo_post_reactions r where r.post_id=p.id and r.user_id=(select auth.uid())),
 (select count(*) from public.melo_post_comments c where c.post_id=p.id)
 from public.melo_channel_posts p where p.id=any(post_ids) and cardinality(post_ids)<=200
$$;
revoke all on function public.melo_post_stats(uuid[]) from public,anon,authenticated;
grant execute on function public.melo_post_stats(uuid[]) to authenticated;
create function public.melo_set_post_reaction(target_post uuid, reaction text) returns void language plpgsql security invoker set search_path='' as $$
begin
 if auth.uid() is null then raise exception 'Authentication required' using errcode='42501'; end if;
 if reaction is null then delete from public.melo_post_reactions where post_id=target_post and user_id=auth.uid();
 else insert into public.melo_post_reactions(post_id,user_id,emoji) values(target_post,auth.uid(),reaction) on conflict(post_id,user_id) do update set emoji=excluded.emoji; end if;
end $$;
revoke all on function public.melo_set_post_reaction(uuid,text) from public,anon,authenticated;
grant execute on function public.melo_set_post_reaction(uuid,text) to authenticated;
alter publication supabase_realtime add table public.melo_post_reactions,public.melo_post_comments;