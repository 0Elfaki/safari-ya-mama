-- Content management for the website and the mother app (platform admins with MFA).
--   lessons            + channels ('web', 'app'), step pictures, draft / published / retired, versions
--   site_content       website pages (hero, about, FAQs, news, partners), draft copy + published versions
--   app_content        app announcements, emergency numbers, Learn cover, draft copy + published versions
--   app-media/site-media  Storage buckets (public read, admin write)
--   app_content_manifest()  everything published for the app, with content_version (stable contract)
-- Publishing always needs both English and Kiswahili. Lessons, and announcements that mention
-- symptoms, also need clinical sign-off (reviewer role and date).

-- ───────────── content version (bumped by every publish / unpublish / restore)
create table if not exists public.content_meta (
  id smallint primary key default 1 check (id = 1),
  content_version bigint not null default 1,
  updated_at timestamptz not null default now()
);
insert into public.content_meta (id) values (1) on conflict (id) do nothing;
alter table public.content_meta enable row level security; -- read through app_content_manifest()

create or replace function public.bump_content_version()
returns bigint language sql security definer set search_path = public as $$
  update content_meta set content_version = content_version + 1, updated_at = now() where id = 1 returning content_version
$$;

-- Picture IDs follow the app convention, e.g. NB-SLEEP-P1
create or replace function public.valid_picture_ids(p text[])
returns boolean language sql immutable set search_path = public as $$
  select coalesce(bool_and(x = '' or x ~ '^[A-Z]{2,5}(-[A-Z0-9]+)+-P[0-9]{1,2}$'), true) from unnest(p) x
$$;

-- Words that mean an announcement talks about symptoms (English and Kiswahili).
create or replace function public.mentions_symptoms(p text)
returns boolean language sql immutable set search_path = public as $$
  select coalesce(p, '') ~* '(bleed|blood|fever|pain|headache|convuls|fits|seizure|swell|vision|breath|vomit|diarrh|rash|jaundice|discharge|faint|danger sign|damu|homa|maumivu|kichwa|degedege|kifafa|kuvimba|kutapika|kuhara|manjano|kupumua|kuzimia)'
$$;

-- ───────────── lessons
alter table public.lessons
  add column if not exists channels text[] not null default '{web,app}',
  add column if not exists step_pictures text[] not null default '{}',
  add column if not exists status text not null default 'draft',
  add column if not exists version integer not null default 0,
  add column if not exists updated_by uuid references public.profiles(id) on delete set null,
  add column if not exists updated_at timestamptz not null default now();
do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'lessons_channels_check' and conrelid = 'public.lessons'::regclass) then
    alter table public.lessons add constraint lessons_channels_check check (channels <@ array['web', 'app'] and cardinality(channels) >= 1);
  end if;
end $$;
do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'lessons_status_check' and conrelid = 'public.lessons'::regclass) then
    alter table public.lessons add constraint lessons_status_check check (status in ('draft', 'published', 'retired'));
  end if;
end $$;
do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'lessons_step_pictures_check' and conrelid = 'public.lessons'::regclass) then
    alter table public.lessons add constraint lessons_step_pictures_check check (public.valid_picture_ids(step_pictures));
  end if;
end $$;

-- Existing lessons keep their state (published ones stay live; their review stays "pending").
update public.lessons set status = case when published then 'published' else 'draft' end,
                          version = case when published then 1 else 0 end
where version = 0;

create table if not exists public.lesson_versions (
  id bigint generated always as identity primary key,
  lesson_id text not null references public.lessons(id) on delete cascade,
  version integer not null,
  snapshot jsonb not null,
  published_at timestamptz not null default now(),
  published_by uuid references public.profiles(id) on delete set null,
  unique (lesson_id, version)
);
alter table public.lesson_versions enable row level security;
do $$
begin
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'lesson_versions' and policyname = 'lesson_versions_admin') then
    create policy lesson_versions_admin on public.lesson_versions for select to authenticated using (public.is_platform_admin());
  end if;
end $$;

-- Guard: a published lesson cannot be edited (unpublish first); only lesson_publish() publishes;
-- `published` always mirrors status, so the website's existing read keeps working.
create or replace function public.lessons_guard()
returns trigger language plpgsql set search_path = public as $$
declare v_pub boolean := coalesce(current_setting('sym.publishing', true), '') = 'on';
begin
  if new.status = 'published' and (tg_op = 'INSERT' or old.status <> 'published') and not v_pub then
    raise exception 'use Publish: it checks both languages and clinical sign-off' using errcode = '42501';
  end if;
  if tg_op = 'UPDATE' and old.status = 'published' and new.status = 'published' and not v_pub
     and (new.category, new.format, new.minutes, new.stage, new.art_keys, new.step_pictures, new.channels)
         is distinct from (old.category, old.format, old.minutes, old.stage, old.art_keys, old.step_pictures, old.channels) then
    raise exception 'this lesson is live: unpublish it to edit, then publish again' using errcode = '42501';
  end if;
  new.published := new.status = 'published';
  new.updated_at := now();
  new.updated_by := coalesce(auth.uid(), new.updated_by);
  return new;
end $$;
create or replace trigger lessons_guard before insert or update on public.lessons for each row execute function public.lessons_guard();

-- Guard: translation text of a live lesson is locked; changing text clears its clinical review.
create or replace function public.lesson_translations_guard()
returns trigger language plpgsql set search_path = public as $$
declare
  v_pub boolean := coalesce(current_setting('sym.publishing', true), '') = 'on';
  v_status text;
begin
  select status into v_status from lessons where id = coalesce(new.lesson_id, old.lesson_id);
  if v_status = 'published' and not v_pub then
    raise exception 'this lesson is live: unpublish it to edit, then publish again' using errcode = '42501';
  end if;
  if tg_op = 'DELETE' then
    return old;
  end if;
  if not v_pub and (tg_op = 'INSERT' or (new.title, new.steps) is distinct from (old.title, old.steps)) then
    new.reviewed_by := null;
    new.reviewed_on := null;
  end if;
  return new;
end $$;
create or replace trigger lesson_translations_guard before insert or update or delete on public.lesson_translations
  for each row execute function public.lesson_translations_guard();

create or replace function public.lesson_snapshot(p_id text)
returns jsonb language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'lesson', (select to_jsonb(l) - array['published', 'status', 'version', 'updated_by', 'updated_at'] from lessons l where l.id = p_id),
    'tr', (select coalesce(jsonb_object_agg(t.lang, jsonb_build_object('title', t.title, 'steps', t.steps, 'audio_path', t.audio_path,
                                                                        'reviewed_by', t.reviewed_by, 'reviewed_on', t.reviewed_on)), '{}'::jsonb)
           from lesson_translations t where t.lesson_id = p_id))
$$;

create or replace function public.lesson_publish(p_id text, p_reviewer text default null, p_reviewed_on date default null)
returns integer language plpgsql security definer set search_path = public as $$
declare
  l lessons;
  v_version integer;
begin
  if not public.is_platform_admin() then
    raise exception 'not allowed' using errcode = '42501';
  end if;
  select * into l from lessons where id = p_id for update;
  if not found then
    raise exception 'lesson not found' using errcode = 'P0002';
  end if;
  if l.status = 'published' then
    raise exception 'already published' using errcode = '22023';
  end if;
  if (select count(*) from lesson_translations t where t.lesson_id = p_id and t.lang in ('en', 'sw')
        and char_length(trim(t.title)) >= 3 and cardinality(t.steps) >= 1
        and not exists (select 1 from unnest(t.steps) s where trim(s) = '')) < 2
     or (select count(distinct cardinality(t.steps)) from lesson_translations t where t.lesson_id = p_id and t.lang in ('en', 'sw')) <> 1 then
    raise exception 'English and Kiswahili both need a title and the same number of steps' using errcode = '22023';
  end if;
  if cardinality(l.step_pictures) > 0 and cardinality(l.step_pictures) <> (select cardinality(t.steps) from lesson_translations t where t.lesson_id = p_id and t.lang = 'en') then
    raise exception 'give one picture ID per step, or leave a step''s picture empty' using errcode = '22023';
  end if;
  perform set_config('sym.publishing', 'on', true);
  if p_reviewer is not null then
    if char_length(trim(p_reviewer)) < 3 or p_reviewed_on is null or p_reviewed_on > current_date then
      raise exception 'clinical sign-off needs the reviewer''s role and a review date that is not in the future' using errcode = '22023';
    end if;
    update lesson_translations set reviewed_by = trim(p_reviewer), reviewed_on = p_reviewed_on
    where lesson_id = p_id and lang in ('en', 'sw');
  end if;
  if exists (select 1 from lesson_translations t where t.lesson_id = p_id and t.lang in ('en', 'sw') and (t.reviewed_by is null or t.reviewed_on is null)) then
    raise exception 'clinical sign-off needed: reviewer role and date' using errcode = '22023';
  end if;
  update lessons set status = 'published', version = version + 1 where id = p_id returning version into v_version;
  insert into lesson_versions (lesson_id, version, snapshot, published_by) values (p_id, v_version, public.lesson_snapshot(p_id), auth.uid());
  perform public.bump_content_version();
  perform set_config('sym.publishing', 'off', true);
  insert into audit_log (actor_id, action, details) values (auth.uid(), 'lesson_publish', jsonb_build_object('lesson', p_id, 'version', v_version));
  return v_version;
end $$;

-- Unpublish (to edit) or retire. Both take it off the website and the app.
create or replace function public.lesson_set_status(p_id text, p_status text)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.is_platform_admin() then
    raise exception 'not allowed' using errcode = '42501';
  end if;
  if p_status not in ('draft', 'retired') then
    raise exception 'use lesson_publish to publish' using errcode = '22023';
  end if;
  update lessons set status = p_status where id = p_id;
  if not found then
    raise exception 'lesson not found' using errcode = 'P0002';
  end if;
  perform public.bump_content_version();
  insert into audit_log (actor_id, action, details)
  values (auth.uid(), case when p_status = 'retired' then 'lesson_retire' else 'lesson_unpublish' end, jsonb_build_object('lesson', p_id));
end $$;

-- Restore a published version into the draft (then publish it again).
create or replace function public.lesson_restore(p_id text, p_version integer)
returns void language plpgsql security definer set search_path = public as $$
declare
  s jsonb;
  g text;
begin
  if not public.is_platform_admin() then
    raise exception 'not allowed' using errcode = '42501';
  end if;
  select snapshot into s from lesson_versions where lesson_id = p_id and version = p_version;
  if s is null then
    raise exception 'version not found' using errcode = 'P0002';
  end if;
  update lessons set status = 'draft' where id = p_id and status <> 'draft';
  update lessons set category = s #>> '{lesson,category}', format = s #>> '{lesson,format}', minutes = (s #>> '{lesson,minutes}')::smallint,
         stage = s #>> '{lesson,stage}', sort = coalesce((s #>> '{lesson,sort}')::smallint, sort),
         art_keys = coalesce(array(select jsonb_array_elements_text(s #> '{lesson,art_keys}')), '{}'),
         step_pictures = coalesce(array(select jsonb_array_elements_text(s #> '{lesson,step_pictures}')), '{}'),
         channels = coalesce(nullif(array(select jsonb_array_elements_text(s #> '{lesson,channels}')), '{}'), '{web,app}')
  where id = p_id;
  -- the restored text is exactly the reviewed text, so its sign-off is restored with it
  perform set_config('sym.publishing', 'on', true);
  for g in select jsonb_object_keys(s -> 'tr') loop
    insert into lesson_translations (lesson_id, lang, title, steps, audio_path, reviewed_by, reviewed_on)
    values (p_id, g, s #>> array['tr', g, 'title'], array(select jsonb_array_elements_text(s #> array['tr', g, 'steps'])),
            s #>> array['tr', g, 'audio_path'], s #>> array['tr', g, 'reviewed_by'], (s #>> array['tr', g, 'reviewed_on'])::date)
    on conflict (lesson_id, lang) do update set title = excluded.title, steps = excluded.steps, audio_path = excluded.audio_path,
      reviewed_by = excluded.reviewed_by, reviewed_on = excluded.reviewed_on;
  end loop;
  perform set_config('sym.publishing', 'off', true);
  perform public.bump_content_version();
  insert into audit_log (actor_id, action, details) values (auth.uid(), 'lesson_restore', jsonb_build_object('lesson', p_id, 'version', p_version));
end $$;

-- The website reads lessons published for the web channel (same query it uses today).
alter policy lessons_read on public.lessons using (published and 'web' = any(channels));
alter policy lessons_read on public.lesson_translations
  using (exists (select 1 from lessons l where l.id = lesson_translations.lesson_id and l.published and 'web' = any(l.channels)));

-- ───────────── website pages
create table if not exists public.site_content (
  key text not null check (key ~ '^[a-z0-9][a-z0-9._-]{1,62}$'),
  lang text not null check (lang in ('en', 'sw')),
  section text not null default 'page' check (section in ('hero', 'about', 'faq', 'news', 'partner', 'page')),
  title text not null default '' check (char_length(title) <= 200),
  body_md text not null default '' check (char_length(body_md) <= 20000),
  image_path text check (image_path is null or image_path ~ '^[A-Za-z0-9][A-Za-z0-9/_.-]{0,199}$'),
  sort integer not null default 0,
  published boolean not null default false,
  version integer not null default 0,
  updated_by uuid references public.profiles(id) on delete set null,
  updated_at timestamptz not null default now(),
  archived boolean not null default false,
  primary key (key, lang)
);
create table if not exists public.site_content_versions (
  id bigint generated always as identity primary key,
  key text not null,
  lang text not null,
  version integer not null,
  section text not null,
  title text not null,
  body_md text not null,
  image_path text,
  sort integer not null,
  published_at timestamptz not null default now(),
  published_by uuid references public.profiles(id) on delete set null,
  unique (key, lang, version)
);
alter table public.site_content enable row level security;
alter table public.site_content_versions enable row level security;
do $$
begin
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'site_content' and policyname = 'site_content_admin') then
    create policy site_content_admin on public.site_content for select to authenticated using (public.is_platform_admin());
  end if;
end $$;
do $$
begin
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'site_content_versions' and policyname = 'site_content_versions_admin') then
    create policy site_content_versions_admin on public.site_content_versions for select to authenticated using (public.is_platform_admin());
  end if;
end $$;

-- Save the draft of both languages at once (the live version is untouched until Publish).
create or replace function public.site_content_save(p_key text, p_section text, p_sort integer, p_image_path text,
                                                    p_en_title text, p_en_body text, p_sw_title text, p_sw_body text)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.is_platform_admin() then
    raise exception 'not allowed' using errcode = '42501';
  end if;
  insert into site_content (key, lang, section, title, body_md, image_path, sort, updated_by, updated_at)
  values (p_key, 'en', p_section, coalesce(p_en_title, ''), coalesce(p_en_body, ''), nullif(p_image_path, ''), coalesce(p_sort, 0), auth.uid(), now()),
         (p_key, 'sw', p_section, coalesce(p_sw_title, ''), coalesce(p_sw_body, ''), nullif(p_image_path, ''), coalesce(p_sort, 0), auth.uid(), now())
  on conflict (key, lang) do update set section = excluded.section, title = excluded.title, body_md = excluded.body_md,
    image_path = excluded.image_path, sort = excluded.sort, updated_by = excluded.updated_by, updated_at = now();
  insert into audit_log (actor_id, action, details) values (auth.uid(), 'site_content_save', jsonb_build_object('key', p_key));
end $$;

create or replace function public.site_content_publish(p_key text)
returns integer language plpgsql security definer set search_path = public as $$
declare v integer;
begin
  if not public.is_platform_admin() then
    raise exception 'not allowed' using errcode = '42501';
  end if;
  if (select count(*) from site_content where key = p_key and char_length(trim(title)) > 0
        and (char_length(trim(body_md)) > 0 or image_path is not null)) < 2 then
    raise exception 'English and Kiswahili both need a title and text (or an image) before publishing' using errcode = '22023';
  end if;
  select coalesce(max(version), 0) + 1 into v from site_content_versions where key = p_key;
  insert into site_content_versions (key, lang, version, section, title, body_md, image_path, sort, published_by)
  select key, lang, v, section, title, body_md, image_path, sort, auth.uid() from site_content where key = p_key;
  update site_content set published = true, version = v where key = p_key;
  insert into audit_log (actor_id, action, details) values (auth.uid(), 'site_content_publish', jsonb_build_object('key', p_key, 'version', v));
  return v;
end $$;

create or replace function public.site_content_unpublish(p_key text)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.is_platform_admin() then
    raise exception 'not allowed' using errcode = '42501';
  end if;
  update site_content set published = false where key = p_key;
  insert into audit_log (actor_id, action, details) values (auth.uid(), 'site_content_unpublish', jsonb_build_object('key', p_key));
end $$;

create or replace function public.site_content_restore(p_key text, p_version integer)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.is_platform_admin() then
    raise exception 'not allowed' using errcode = '42501';
  end if;
  if not exists (select 1 from site_content_versions where key = p_key and version = p_version) then
    raise exception 'version not found' using errcode = 'P0002';
  end if;
  update site_content c set section = v.section, title = v.title, body_md = v.body_md, image_path = v.image_path, sort = v.sort,
    updated_by = auth.uid(), updated_at = now()
  from site_content_versions v where v.key = p_key and v.version = p_version and c.key = v.key and c.lang = v.lang;
  insert into audit_log (actor_id, action, details) values (auth.uid(), 'site_content_restore', jsonb_build_object('key', p_key, 'version', p_version));
end $$;

-- Archive (instead of deleting) a page: it leaves the website; its published versions stay in the history.
create or replace function public.site_content_archive(p_key text, p_archived boolean default true)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.is_platform_admin() then
    raise exception 'not allowed' using errcode = '42501';
  end if;
  update site_content set archived = p_archived, published = case when p_archived then false else published end where key = p_key;
  insert into audit_log (actor_id, action, details)
  values (auth.uid(), case when p_archived then 'site_content_archive' else 'site_content_unarchive' end, jsonb_build_object('key', p_key));
end $$;

-- Public read for the website: the latest published version of every live page.
create or replace function public.site_content_public(p_lang text default null)
returns table (key text, lang text, section text, title text, body_md text, image_path text, sort integer, version integer, published_at timestamptz)
language sql stable security definer set search_path = public as $$
  select v.key, v.lang, v.section, v.title, v.body_md, v.image_path, v.sort, v.version, v.published_at
  from site_content c join site_content_versions v on v.key = c.key and v.lang = c.lang and v.version = c.version
  where c.published and (p_lang is null or v.lang = p_lang)
  order by v.section, v.sort, v.key, v.lang
$$;

-- ───────────── app content
create table if not exists public.app_content (
  key text not null check (key ~ '^[a-z0-9][a-z0-9._-]{1,62}$'),
  lang text not null check (lang in ('en', 'sw')),
  kind text not null default 'announcement' check (kind in ('announcement', 'emergency_numbers', 'learn_cover', 'other')),
  value text not null default '' check (char_length(value) <= 4000),
  country_code character(2) references public.countries(code),
  starts_on date,
  ends_on date,
  mentions_symptoms boolean not null default false,
  reviewed_by text,
  reviewed_on date,
  published boolean not null default false,
  version integer not null default 0,
  updated_by uuid references public.profiles(id) on delete set null,
  updated_at timestamptz not null default now(),
  archived boolean not null default false,
  primary key (key, lang),
  check (ends_on is null or starts_on is null or ends_on >= starts_on)
);
create table if not exists public.app_content_versions (
  id bigint generated always as identity primary key,
  key text not null,
  lang text not null,
  version integer not null,
  kind text not null,
  value text not null,
  country_code character(2),
  starts_on date,
  ends_on date,
  mentions_symptoms boolean not null,
  reviewed_by text,
  reviewed_on date,
  published_at timestamptz not null default now(),
  published_by uuid references public.profiles(id) on delete set null,
  unique (key, lang, version)
);
alter table public.app_content enable row level security;
alter table public.app_content_versions enable row level security;
do $$
begin
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'app_content' and policyname = 'app_content_admin') then
    create policy app_content_admin on public.app_content for select to authenticated using (public.is_platform_admin());
  end if;
end $$;
do $$
begin
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'app_content_versions' and policyname = 'app_content_versions_admin') then
    create policy app_content_versions_admin on public.app_content_versions for select to authenticated using (public.is_platform_admin());
  end if;
end $$;

create or replace function public.app_content_save(p_key text, p_kind text, p_country text, p_starts date, p_ends date,
                                                   p_en text, p_sw text, p_mentions_symptoms boolean default false)
returns void language plpgsql security definer set search_path = public as $$
declare v_sym boolean := coalesce(p_mentions_symptoms, false) or public.mentions_symptoms(p_en) or public.mentions_symptoms(p_sw);
begin
  if not public.is_platform_admin() then
    raise exception 'not allowed' using errcode = '42501';
  end if;
  insert into app_content (key, lang, kind, value, country_code, starts_on, ends_on, mentions_symptoms, updated_by, updated_at)
  values (p_key, 'en', p_kind, coalesce(p_en, ''), nullif(p_country, ''), p_starts, p_ends, v_sym, auth.uid(), now()),
         (p_key, 'sw', p_kind, coalesce(p_sw, ''), nullif(p_country, ''), p_starts, p_ends, v_sym, auth.uid(), now())
  on conflict (key, lang) do update set kind = excluded.kind, country_code = excluded.country_code, starts_on = excluded.starts_on,
    ends_on = excluded.ends_on, mentions_symptoms = excluded.mentions_symptoms, updated_by = excluded.updated_by, updated_at = now(),
    -- changed text loses its clinical sign-off
    reviewed_by = case when app_content.value is distinct from excluded.value then null else app_content.reviewed_by end,
    reviewed_on = case when app_content.value is distinct from excluded.value then null else app_content.reviewed_on end,
    value = excluded.value;
  insert into audit_log (actor_id, action, details) values (auth.uid(), 'app_content_save', jsonb_build_object('key', p_key));
end $$;

create or replace function public.app_content_publish(p_key text, p_reviewer text default null, p_reviewed_on date default null)
returns integer language plpgsql security definer set search_path = public as $$
declare v integer;
begin
  if not public.is_platform_admin() then
    raise exception 'not allowed' using errcode = '42501';
  end if;
  if (select count(*) from app_content where key = p_key and char_length(trim(value)) > 0) < 2 then
    raise exception 'English and Kiswahili both need text before publishing' using errcode = '22023';
  end if;
  if p_reviewer is not null then
    if char_length(trim(p_reviewer)) < 3 or p_reviewed_on is null or p_reviewed_on > current_date then
      raise exception 'clinical sign-off needs the reviewer''s role and a review date that is not in the future' using errcode = '22023';
    end if;
    update app_content set reviewed_by = trim(p_reviewer), reviewed_on = p_reviewed_on where key = p_key;
  end if;
  if exists (select 1 from app_content where key = p_key and mentions_symptoms and (reviewed_by is null or reviewed_on is null)) then
    raise exception 'this text mentions symptoms: clinical sign-off needed (reviewer role and date)' using errcode = '22023';
  end if;
  select coalesce(max(version), 0) + 1 into v from app_content_versions where key = p_key;
  insert into app_content_versions (key, lang, version, kind, value, country_code, starts_on, ends_on, mentions_symptoms, reviewed_by, reviewed_on, published_by)
  select key, lang, v, kind, value, country_code, starts_on, ends_on, mentions_symptoms, reviewed_by, reviewed_on, auth.uid()
  from app_content where key = p_key;
  update app_content set published = true, version = v where key = p_key;
  perform public.bump_content_version();
  insert into audit_log (actor_id, action, details) values (auth.uid(), 'app_content_publish', jsonb_build_object('key', p_key, 'version', v));
  return v;
end $$;

create or replace function public.app_content_unpublish(p_key text)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.is_platform_admin() then
    raise exception 'not allowed' using errcode = '42501';
  end if;
  update app_content set published = false where key = p_key;
  perform public.bump_content_version();
  insert into audit_log (actor_id, action, details) values (auth.uid(), 'app_content_unpublish', jsonb_build_object('key', p_key));
end $$;

create or replace function public.app_content_restore(p_key text, p_version integer)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.is_platform_admin() then
    raise exception 'not allowed' using errcode = '42501';
  end if;
  if not exists (select 1 from app_content_versions where key = p_key and version = p_version) then
    raise exception 'version not found' using errcode = 'P0002';
  end if;
  update app_content c set kind = v.kind, value = v.value, country_code = v.country_code, starts_on = v.starts_on, ends_on = v.ends_on,
    mentions_symptoms = v.mentions_symptoms, reviewed_by = v.reviewed_by, reviewed_on = v.reviewed_on, updated_by = auth.uid(), updated_at = now()
  from app_content_versions v where v.key = p_key and v.version = p_version and c.key = v.key and c.lang = v.lang;
  insert into audit_log (actor_id, action, details) values (auth.uid(), 'app_content_restore', jsonb_build_object('key', p_key, 'version', p_version));
end $$;

create or replace function public.app_content_archive(p_key text, p_archived boolean default true)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.is_platform_admin() then
    raise exception 'not allowed' using errcode = '42501';
  end if;
  update app_content set archived = p_archived, published = case when p_archived then false else published end where key = p_key;
  perform public.bump_content_version();
  insert into audit_log (actor_id, action, details)
  values (auth.uid(), case when p_archived then 'app_content_archive' else 'app_content_unarchive' end, jsonb_build_object('key', p_key));
end $$;

-- ───────────── the app's offline manifest (contract documented in supabase/README.md)
create or replace function public.app_content_manifest()
returns jsonb language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'schema', 1,
    'content_version', (select content_version from content_meta where id = 1),
    'generated_at', now(),
    'media', jsonb_build_object('bucket', 'app-media', 'path', '<PICTURE-ID>.webp'),
    'lessons', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', l.id, 'category', l.category, 'format', l.format, 'minutes', l.minutes, 'stage', l.stage, 'sort', l.sort,
        'version', l.version, 'art_keys', l.art_keys, 'step_pictures', l.step_pictures,
        'tr', (select coalesce(jsonb_object_agg(t.lang, jsonb_build_object('title', t.title, 'steps', t.steps,
                                                                            'reviewed_by', t.reviewed_by, 'reviewed_on', t.reviewed_on)), '{}'::jsonb)
               from lesson_translations t where t.lesson_id = l.id and t.lang in ('en', 'sw'))) order by l.sort, l.id)
      from lessons l where l.status = 'published' and 'app' = any(l.channels)), '[]'::jsonb),
    'content', coalesce((
      select jsonb_object_agg(x.key, x.item) from (
        select c.key, jsonb_build_object('kind', min(v.kind), 'version', max(v.version), 'country_code', min(v.country_code),
                                         'starts_on', min(v.starts_on), 'ends_on', max(v.ends_on),
                                         'en', max(v.value) filter (where v.lang = 'en'), 'sw', max(v.value) filter (where v.lang = 'sw')) item
        from app_content c join app_content_versions v on v.key = c.key and v.lang = c.lang and v.version = c.version
        where c.published and (v.ends_on is null or v.ends_on >= current_date)
        group by c.key) x), '{}'::jsonb))
$$;

-- ───────────── Storage buckets (public read; platform admins write)
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('site-media', 'site-media', true, 2097152, array['image/webp', 'image/png', 'image/jpeg']),
       ('app-media', 'app-media', true, 153600, array['image/webp'])
on conflict (id) do update set public = excluded.public, file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

do $$
begin
  if not exists (select 1 from pg_policies where schemaname = 'storage' and tablename = 'objects' and policyname = 'media_admin_read') then
    create policy media_admin_read on storage.objects for select to authenticated
  using (bucket_id in ('site-media', 'app-media') and public.is_platform_admin());
  end if;
end $$;
do $$
begin
  if not exists (select 1 from pg_policies where schemaname = 'storage' and tablename = 'objects' and policyname = 'media_admin_insert') then
    create policy media_admin_insert on storage.objects for insert to authenticated
  with check (bucket_id in ('site-media', 'app-media') and public.is_platform_admin()
              and (bucket_id <> 'app-media' or name ~ '^[A-Z]{2,5}(-[A-Z0-9]+)+-P[0-9]{1,2}\.webp$')
              and (bucket_id <> 'site-media' or name ~ '^[a-z0-9][a-z0-9/_.-]{0,199}\.(webp|png|jpe?g)$'));
  end if;
end $$;
do $$
begin
  if not exists (select 1 from pg_policies where schemaname = 'storage' and tablename = 'objects' and policyname = 'media_admin_update') then
    create policy media_admin_update on storage.objects for update to authenticated
  using (bucket_id in ('site-media', 'app-media') and public.is_platform_admin())
  with check (bucket_id in ('site-media', 'app-media') and public.is_platform_admin()
              and (bucket_id <> 'app-media' or name ~ '^[A-Z]{2,5}(-[A-Z0-9]+)+-P[0-9]{1,2}\.webp$')
              and (bucket_id <> 'site-media' or name ~ '^[a-z0-9][a-z0-9/_.-]{0,199}\.(webp|png|jpe?g)$'));
  end if;
end $$;
do $$
begin
  if not exists (select 1 from pg_policies where schemaname = 'storage' and tablename = 'objects' and policyname = 'media_admin_delete') then
    create policy media_admin_delete on storage.objects for delete to authenticated
  using (bucket_id in ('site-media', 'app-media') and public.is_platform_admin());
  end if;
end $$;

-- ───────────── grants
revoke execute on function public.bump_content_version() from public, anon, authenticated;
revoke execute on function public.lessons_guard() from public, anon, authenticated;
revoke execute on function public.lesson_translations_guard() from public, anon, authenticated;
revoke execute on function public.lesson_snapshot(text) from public, anon, authenticated;
do $$
declare f text;
begin
  foreach f in array array[
    'public.lesson_publish(text, text, date)', 'public.lesson_set_status(text, text)', 'public.lesson_restore(text, integer)',
    'public.site_content_save(text, text, integer, text, text, text, text, text)', 'public.site_content_publish(text)',
    'public.site_content_unpublish(text)', 'public.site_content_restore(text, integer)', 'public.site_content_archive(text, boolean)',
    'public.app_content_save(text, text, text, date, date, text, text, boolean)', 'public.app_content_publish(text, text, date)',
    'public.app_content_unpublish(text)', 'public.app_content_restore(text, integer)', 'public.app_content_archive(text, boolean)'
  ] loop
    execute format('revoke all on function %s from public, anon', f);
    execute format('grant execute on function %s to authenticated', f);
  end loop;
end $$;
revoke all on function public.site_content_public(text) from public;
grant execute on function public.site_content_public(text) to anon, authenticated;
revoke all on function public.app_content_manifest() from public;
grant execute on function public.app_content_manifest() to anon, authenticated;
grant execute on function public.valid_picture_ids(text[]) to anon, authenticated;
grant execute on function public.mentions_symptoms(text) to authenticated;
