-- Retire bot API access without deleting existing user data.
revoke all on table public.melo_bots from public,anon,authenticated;
revoke insert(owner_id,name,description,commands),update(name,description,commands) on public.melo_bots from public,anon,authenticated;