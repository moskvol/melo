alter table public.profiles add column custom_badges jsonb not null default '[]'::jsonb check(jsonb_typeof(custom_badges)='array' and jsonb_array_length(custom_badges)<=3);
revoke insert(custom_badges),update(custom_badges) on public.profiles from public,anon,authenticated;
create function private.manage_melo_badge(target_id uuid, badge_id uuid, badge_label text, badge_icon text, badge_bg text, badge_fg text, badge_description text, remove_badge boolean)
returns jsonb language plpgsql security definer set search_path='' as $$
declare badges jsonb; item jsonb; label_clean text:=trim(badge_label); descr text:=trim(coalesce(badge_description,'')); normalized text;
begin
 if auth.uid() is null or not exists(select 1 from public.melo_admins where user_id=auth.uid()) then raise exception 'Administrator access required' using errcode='42501'; end if;
 select custom_badges into badges from public.profiles where id=target_id for update;
 if not found then raise exception 'User not found'; end if;
 if remove_badge then
  select coalesce(jsonb_agg(x.value order by x.ordinality),'[]'::jsonb) into badges from jsonb_array_elements(badges) with ordinality x(value,ordinality) where x.value->>'id'<>badge_id::text;
 else
  if label_clean is null or char_length(label_clean) not between 1 and 20 or label_clean !~ '^[[:alnum:][:space:]_+.-]+$' or label_clean ~ '[[:cntrl:]]' then raise exception 'Название: 1–20 букв, цифр или обычных символов'; end if;
  normalized:=lower(regexp_replace(label_clean,'[[:space:]_+.-]','','g'));
  if normalized ~ '(админ|admin|владелец|owner|moderator|модератор|verified|верифиц|подтвержд|meloplus)' then raise exception 'Это название зарезервировано для системных статусов'; end if;
  if badge_icon is null or badge_icon not in ('','star','favorite','bolt','diamond','code','science','rocket_launch','palette','workspace_premium','emoji_events','local_fire_department','music_note','sports_esports','auto_awesome','flutter_dash','pets','public','brush','lightbulb','celebration') then raise exception 'Invalid icon'; end if;
  if badge_bg is null or badge_fg is null or badge_bg !~ '^#[0-9a-fA-F]{6}$' or badge_fg !~ '^#[0-9a-fA-F]{6}$' or char_length(descr)>120 then raise exception 'Invalid colors or description'; end if;
  item:=jsonb_build_object('id',coalesce(badge_id,gen_random_uuid()),'label',label_clean,'icon',badge_icon,'bg',badge_bg,'fg',badge_fg,'description',descr);
  if badge_id is not null then
   if not exists(select 1 from jsonb_array_elements(badges) x where x->>'id'=badge_id::text) then raise exception 'Badge not found'; end if;
   select jsonb_agg(case when x.value->>'id'=badge_id::text then item else x.value end order by x.ordinality) into badges from jsonb_array_elements(badges) with ordinality x(value,ordinality);
  else
   if jsonb_array_length(badges)>=3 then raise exception 'Максимум 3 кастомных бейджа на пользователя'; end if;
   badges:=badges||jsonb_build_array(item);
  end if;
 end if;
 update public.profiles set custom_badges=badges where id=target_id;
 return badges;
end $$;
revoke all on function private.manage_melo_badge(uuid,uuid,text,text,text,text,text,boolean) from public,anon,authenticated;
grant execute on function private.manage_melo_badge(uuid,uuid,text,text,text,text,text,boolean) to authenticated;
create function public.manage_melo_badge(target_id uuid,badge_id uuid,badge_label text,badge_icon text,badge_bg text,badge_fg text,badge_description text,remove_badge boolean)
returns jsonb language sql security invoker set search_path='' as $$select private.manage_melo_badge(target_id,badge_id,badge_label,badge_icon,badge_bg,badge_fg,badge_description,remove_badge)$$;
revoke all on function public.manage_melo_badge(uuid,uuid,text,text,text,text,text,boolean) from public,anon,authenticated;
grant execute on function public.manage_melo_badge(uuid,uuid,text,text,text,text,text,boolean) to authenticated;