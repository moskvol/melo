-- Index foreign keys used by ownership transfer, replies and forwards.
create index if not exists conversations_owner_id_idx on public.conversations(owner_id);
create index if not exists messages_reply_to_id_idx on public.messages(reply_to_id);
create index if not exists messages_forwarded_from_id_idx on public.messages(forwarded_from_id);
