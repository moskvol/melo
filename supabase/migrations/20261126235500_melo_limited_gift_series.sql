create table public.melo_gift_series(id uuid primary key default gen_random_uuid(),title text not null check(char_length(trim(title)) between 1 and 60),icon text not null check(icon in ('redeem','diamond','star','favorite','rocket_launch','workspace_premium','local_fire_department','pets','cake','auto_awesome','emoji_events')),color text not null check(color ~ '^#[0-9a-fA-F]{6}$'),rarity text not null check(rarity in ('common','rare','epic','legendary')),description text not null default '' check(char_length(description)<=240),pattern text not null check(pattern in ('dots','waves','stars','grid')),max_supply integer not null check(max_supply between 1 and 10000),issued_count integer not null default 0 check(issued_count between 0 and max_supply),created_at timestamptz not null default now());
alter table public.melo_gift_series enable row level security;
revoke all on public.melo_gift_series from public,anon,authenticated;
grant select on public.melo_gift_series to authenticated;
create policy series_read on public.melo_gift_series for select to authenticated using((select private.melo_mfa_ok()));
alter table public.melo_collectibles add column series_id uuid references public.melo_gift_series(id) on delete restrict,add column series_number integer,add column pattern text check(pattern in ('dots','waves','stars','grid')),add constraint melo_series_pair check((series_id is null and series_number is null) or (series_id is not null and series_number>0)),add constraint melo_series_item_unique unique(series_id,series_number);
create function private.melo_series_owner(action text,series uuid default null,target uuid default null,params jsonb default '{}'::jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare row_data public.melo_gift_series%rowtype; sn bigint;
begin
 if not private.melo_mfa_ok() or not exists(select 1 from public.melo_admins where user_id=auth.uid() and is_owner) then raise exception 'Owner access required' using errcode='42501';end if;
 if action='create' then
 insert into public.melo_gift_series(title,icon,color,rarity,description,pattern,max_supply) values(trim(params->>'title'),params->>'icon',params->>'color',params->>'rarity',coalesce(params->>'description',''),params->>'pattern',(params->>'max_supply')::integer) returning * into row_data;
 return to_jsonb(row_data);
 elsif action='issue' then
 if target is null or not exists(select 1 from public.profiles where id=target) then raise exception 'Recipient required';end if;
 update public.melo_gift_series set issued_count=issued_count+1 where id=series and issued_count<max_supply returning * into row_data;
 if not found then raise exception 'Series sold out or unavailable';end if;
 insert into public.melo_collectibles(recipient_id,kind,title,icon,color,rarity,description,series_id,series_number,pattern) values(target,'collectible',row_data.title,row_data.icon,row_data.color,row_data.rarity,row_data.description,series,row_data.issued_count,row_data.pattern) returning serial into sn;
 return jsonb_build_object('serial',sn,'number',row_data.issued_count);
 else raise exception 'Invalid action';end if;
end $$;
revoke all on function private.melo_series_owner(text,uuid,uuid,jsonb) from public,anon,authenticated;
grant execute on function private.melo_series_owner(text,uuid,uuid,jsonb) to authenticated;
create function public.melo_series_owner(action text,series uuid default null,target uuid default null,params jsonb default '{}'::jsonb) returns jsonb language sql security invoker set search_path='' as $$select private.melo_series_owner(action,series,target,params)$$;
revoke all on function public.melo_series_owner(text,uuid,uuid,jsonb) from public,anon,authenticated;
grant execute on function public.melo_series_owner(text,uuid,uuid,jsonb) to authenticated;