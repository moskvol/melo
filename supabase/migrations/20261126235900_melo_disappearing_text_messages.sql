alter table public.conversations add column auto_delete_seconds integer not null default 0 check(auto_delete_seconds in (0,3600,86400,604800));
alter table public.messages add column expires_at timestamptz;
create index melo_message_expiry on public.messages(expires_at) where expires_at is not null;
create function private.melo_set_auto_delete(cid uuid,seconds integer) returns void language plpgsql security definer set search_path='' as $$
begin
 if not private.melo_mfa_ok() or not private.is_member(cid,auth.uid()) or not exists(select 1 from public.conversations c where c.id=cid and (c.kind='direct' or private.is_admin(cid,auth.uid()))) then raise exception 'Permission denied' using errcode='42501';end if;
 if seconds is null or seconds not in (0,3600,86400,604800) then raise exception 'Invalid timer';end if;
 update public.conversations set auto_delete_seconds=seconds where id=cid;
end $$;
revoke all on function private.melo_set_auto_delete(uuid,integer) from public,anon,authenticated;
grant execute on function private.melo_set_auto_delete(uuid,integer) to authenticated;
create function public.melo_set_auto_delete(cid uuid,seconds integer) returns void language sql security invoker set search_path='' as $$select private.melo_set_auto_delete(cid,seconds)$$;
revoke all on function public.melo_set_auto_delete(uuid,integer) from public,anon,authenticated;
grant execute on function public.melo_set_auto_delete(uuid,integer) to authenticated;
create function private.melo_assign_expiry() returns trigger language plpgsql security definer set search_path='' as $$
declare duration integer;
begin
 select auto_delete_seconds into duration from public.conversations where id=new.conversation_id;
 new.expires_at:=case when duration>0 and new.kind='text' and new.attachment_path is null then now()+make_interval(secs=>duration) else null end;
 return new;
end $$;
revoke all on function private.melo_assign_expiry() from public,anon,authenticated;
create trigger melo_assign_expiry before insert on public.messages for each row execute function private.melo_assign_expiry();
create policy melo_unexpired_messages on public.messages as restrictive for select to authenticated using(expires_at is null or expires_at>now());
CREATE OR REPLACE FUNCTION private.check_message()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
      or (new.reply_to_id is distinct from old.reply_to_id and not (new.reply_to_id is null and old.reply_to_id is not null and not exists(select 1 from public.messages where id=old.reply_to_id))) or (new.forwarded_from_id is distinct from old.forwarded_from_id and not (new.forwarded_from_id is null and old.forwarded_from_id is not null and not exists(select 1 from public.messages where id=old.forwarded_from_id))) then
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
end $function$
;
create function private.melo_delete_expired_messages() returns void language sql security definer set search_path='' as $$delete from public.messages where id in (select id from public.messages where expires_at<=now() order by expires_at limit 500)$$;
revoke all on function private.melo_delete_expired_messages() from public,anon,authenticated;
select cron.schedule('melo-expired-messages','* * * * *','select private.melo_delete_expired_messages();');