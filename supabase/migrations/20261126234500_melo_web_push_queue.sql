create extension if not exists pg_cron;
create extension if not exists pg_net with schema extensions;
create table private.melo_push_config(singleton boolean primary key default true check(singleton),worker_key text not null default encode(extensions.gen_random_bytes(32),'hex'),vapid_public text,vapid_private text);
insert into private.melo_push_config(singleton) values(true);
create table private.melo_push_subscriptions(id uuid primary key default gen_random_uuid(),user_id uuid not null references public.profiles(id) on delete cascade,session_id uuid not null references auth.sessions(id) on delete cascade,endpoint text not null unique,p256dh text not null,auth_key text not null,created_at timestamptz not null default now(),updated_at timestamptz not null default now());
create table private.melo_push_jobs(id uuid primary key default gen_random_uuid(),message_id uuid not null references public.messages(id) on delete cascade,subscription_id uuid not null references private.melo_push_subscriptions(id) on delete cascade,attempts integer not null default 0,next_attempt_at timestamptz not null default now(),claimed_at timestamptz,created_at timestamptz not null default now(),unique(message_id,subscription_id));
create index melo_push_sub_user on private.melo_push_subscriptions(user_id);
create index melo_push_sub_session on private.melo_push_subscriptions(session_id);
create index melo_push_jobs_ready on private.melo_push_jobs(next_attempt_at);
alter table private.melo_push_config enable row level security;revoke all on private.melo_push_config from public,anon,authenticated;
alter table private.melo_push_subscriptions enable row level security;revoke all on private.melo_push_subscriptions from public,anon,authenticated;
alter table private.melo_push_jobs enable row level security;revoke all on private.melo_push_jobs from public,anon,authenticated;
create function private.melo_push_register(p_endpoint text,p_key text,p_auth text) returns boolean language plpgsql security definer set search_path='' as $$
declare sid uuid;
begin
 if not private.melo_mfa_ok() then raise exception 'Authentication required' using errcode='42501';end if;
 sid:=nullif(auth.jwt()->>'session_id','')::uuid;
 if not exists(select 1 from auth.sessions s where s.id=sid and s.user_id=auth.uid() and (s.not_after is null or s.not_after>now())) then raise exception 'Session expired' using errcode='42501';end if;
 if p_endpoint is null or char_length(p_endpoint)>2048 or p_endpoint !~ '^https://(fcm\.googleapis\.com|[a-z0-9.-]+\.push\.services\.mozilla\.com|([a-z0-9-]+\.)*web\.push\.apple\.com|([a-z0-9-]+\.)*notify\.windows\.com)/[^[:space:]]+$' or p_key is null or p_key !~ '^[A-Za-z0-9_-]{80,100}$' or p_auth is null or p_auth !~ '^[A-Za-z0-9_-]{16,64}$' then raise exception 'Unsupported push subscription';end if;
 if (select count(*) from private.melo_push_subscriptions where user_id=auth.uid())>=20 and not exists(select 1 from private.melo_push_subscriptions where endpoint=p_endpoint and user_id=auth.uid()) then raise exception 'Too many push subscriptions';end if;
 insert into private.melo_push_subscriptions(user_id,session_id,endpoint,p256dh,auth_key) values(auth.uid(),sid,p_endpoint,p_key,p_auth) on conflict(endpoint) do update set user_id=excluded.user_id,session_id=excluded.session_id,p256dh=excluded.p256dh,auth_key=excluded.auth_key,updated_at=now() where private.melo_push_subscriptions.auth_key=excluded.auth_key and private.melo_push_subscriptions.p256dh=excluded.p256dh;
 if not found then raise exception 'Subscription already in use';end if;
 return true;
end $$;
create function private.melo_push_unregister(p_endpoint text) returns boolean language plpgsql security definer set search_path='' as $$
begin
 if not private.melo_mfa_ok() then raise exception 'Authentication required' using errcode='42501';end if;
 delete from private.melo_push_subscriptions where user_id=auth.uid() and endpoint=p_endpoint;
 return true;
end $$;
create function private.melo_push_registered(p_endpoint text) returns boolean language sql stable security definer set search_path='' as $$select private.melo_mfa_ok() and exists(select 1 from private.melo_push_subscriptions s where s.user_id=auth.uid() and s.session_id::text=auth.jwt()->>'session_id' and s.endpoint=p_endpoint)$$;
revoke all on function private.melo_push_register(text,text,text) from public,anon,authenticated;
grant execute on function private.melo_push_register(text,text,text) to authenticated;
create function public.melo_push_register(p_endpoint text,p_key text,p_auth text) returns boolean language sql security invoker set search_path='' as $$select private.melo_push_register(p_endpoint,p_key,p_auth)$$;
revoke all on function public.melo_push_register(text,text,text) from public,anon,authenticated;
grant execute on function public.melo_push_register(text,text,text) to authenticated;
revoke all on function private.melo_push_unregister(text) from public,anon,authenticated;
grant execute on function private.melo_push_unregister(text) to authenticated;
create function public.melo_push_unregister(p_endpoint text) returns boolean language sql security invoker set search_path='' as $$select private.melo_push_unregister(p_endpoint)$$;
revoke all on function public.melo_push_unregister(text) from public,anon,authenticated;
grant execute on function public.melo_push_unregister(text) to authenticated;
revoke all on function private.melo_push_registered(text) from public,anon,authenticated;
grant execute on function private.melo_push_registered(text) to authenticated;
create function public.melo_push_registered(p_endpoint text) returns boolean language sql security invoker set search_path='' as $$select private.melo_push_registered(p_endpoint)$$;
revoke all on function public.melo_push_registered(text) from public,anon,authenticated;
grant execute on function public.melo_push_registered(text) to authenticated;
create function public.melo_push_worker_config(p_public text default null,p_private text default null) returns jsonb language plpgsql security definer set search_path='' as $$
declare cfg private.melo_push_config%rowtype;
begin
 if p_public is not null and p_private is not null then update private.melo_push_config set vapid_public=p_public,vapid_private=p_private where singleton and vapid_public is null;end if;
 select * into cfg from private.melo_push_config where singleton;
 return jsonb_build_object('worker',cfg.worker_key,'public',cfg.vapid_public,'private',cfg.vapid_private);
end $$;
create function private.melo_push_enqueue() returns trigger language plpgsql security definer set search_path='' as $$
begin
 insert into private.melo_push_jobs(message_id,subscription_id)
 select new.id,s.id from private.melo_push_subscriptions s join public.conversation_members cm on cm.user_id=s.user_id and cm.conversation_id=new.conversation_id join auth.sessions a on a.id=s.session_id and a.user_id=s.user_id
 where s.user_id<>new.sender_id and (a.not_after is null or a.not_after>now()) and not exists(select 1 from public.blocks b where b.blocker_id=s.user_id and b.blocked_id=new.sender_id) on conflict do nothing;
 return new;
end $$;
revoke all on function private.melo_push_enqueue() from public,anon,authenticated;
create trigger melo_push_enqueue after insert on public.messages for each row execute function private.melo_push_enqueue();
create function public.melo_push_claim() returns table(job_id uuid,endpoint text,p256dh text,auth_key text) language plpgsql security definer set search_path='' as $$
begin
 delete from private.melo_push_jobs j where j.attempts>=5 or j.created_at<now()-interval '1 day' or not exists(select 1 from private.melo_push_subscriptions s join public.messages m on m.id=j.message_id join public.conversation_members cm on cm.conversation_id=m.conversation_id and cm.user_id=s.user_id join auth.sessions a on a.id=s.session_id and a.user_id=s.user_id where s.id=j.subscription_id and m.deleted_at is null and s.user_id<>m.sender_id and (a.not_after is null or a.not_after>now()) and not exists(select 1 from public.blocks b where b.blocker_id=s.user_id and b.blocked_id=m.sender_id));
 return query with pending as (select j.id from private.melo_push_jobs j where j.next_attempt_at<=now() and (j.claimed_at is null or j.claimed_at<now()-interval '2 minutes') order by j.created_at limit 12 for update skip locked),claimed as (update private.melo_push_jobs j set attempts=j.attempts+1,claimed_at=now() from pending p where j.id=p.id returning j.id,j.subscription_id) select c.id,s.endpoint,s.p256dh,s.auth_key from claimed c join private.melo_push_subscriptions s on s.id=c.subscription_id;
end $$;
create function public.melo_push_finish(job uuid,outcome text) returns void language plpgsql security definer set search_path='' as $$
begin
 if outcome='expired' then delete from private.melo_push_subscriptions s where s.id=(select j.subscription_id from private.melo_push_jobs j where j.id=job);
 elsif outcome in ('sent','invalid') then delete from private.melo_push_jobs j where j.id=job;
 else update private.melo_push_jobs j set claimed_at=null,next_attempt_at=now()+make_interval(mins=>least(30,2*j.attempts)) where j.id=job;end if;
end $$;
revoke all on function public.melo_push_worker_config(text,text) from public,anon,authenticated;grant execute on function public.melo_push_worker_config(text,text) to service_role;
revoke all on function public.melo_push_claim() from public,anon,authenticated;grant execute on function public.melo_push_claim() to service_role;
revoke all on function public.melo_push_finish(uuid,text) from public,anon,authenticated;grant execute on function public.melo_push_finish(uuid,text) to service_role;
create function private.melo_push_tick() returns void language plpgsql security definer set search_path='' as $$
declare secret text;
begin
 if not exists(select 1 from private.melo_push_jobs j where j.next_attempt_at<=now() and (j.claimed_at is null or j.claimed_at<now()-interval '2 minutes')) then return;end if;
 select worker_key into secret from private.melo_push_config where singleton;
 perform net.http_post(url:='https://mzqpynvtlcotjfyjzamj.supabase.co/functions/v1/melo-push',headers=>jsonb_build_object('Content-Type','application/json','X-Melo-Worker-Key',secret),body=>'{"action":"dispatch"}'::jsonb,timeout_milliseconds=>30000);
end $$;
revoke all on function private.melo_push_tick() from public,anon,authenticated;
select cron.schedule('melo-push-dispatch','* * * * *','select private.melo_push_tick();');