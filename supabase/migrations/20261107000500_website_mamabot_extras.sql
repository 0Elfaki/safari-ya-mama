-- Website extras (Studio spec §9–§10):
-- 1. The WEBSITE's MamaBot answer library (mamabot_entries) and safety phrases (safety_phrases).
--    This is the public website's demo assistant, not the mother app's MamaBot: the app's urgent
--    words and safety answers stay in code (ai-gateway, rules), read-only in the dashboard.
--    Health content rules: an answer is published only after a clinical reviewer (or an Admin
--    recording the reviewer) approves that exact text; any change sends it back for review.
--    Safety phrases (skip the AI, go straight to emergency guidance) are edited and published only
--    by Admins and clinical reviewers.
-- 2. robots.txt text and MamaBot settings live in site_settings ('robots', 'mamabot'; Admin only).
-- 3. Contact form through the Edge Function "contact-submit" (rate limit by sender, email alert to
--    the team). submit_contact_from() is callable only with the service role.

create table if not exists public.mamabot_entries (
  id uuid primary key default gen_random_uuid(),
  patterns text[] not null default '{}',
  answer_en text not null default '' check (char_length(answer_en) <= 2000),
  answer_sw text not null default '' check (char_length(answer_sw) <= 2000),
  urgency text not null default 'none' check (urgency in ('red', 'yellow', 'none')),
  source_lesson_id text,
  reference text check (char_length(reference) <= 300),
  reviewed_by text,
  reviewed_on date,
  review_hash text,
  published boolean not null default false,
  archived boolean not null default false,
  updated_by uuid references public.profiles(id) on delete set null,
  updated_at timestamptz not null default now()
);
create index if not exists mamabot_entries_updated_by_idx on public.mamabot_entries (updated_by);
alter table public.mamabot_entries enable row level security;
do $$ begin
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'mamabot_entries' and policyname = 'mamabot_entries_staff') then
    create policy mamabot_entries_staff on public.mamabot_entries for select to authenticated using (public.web_can('read'));
  end if;
end $$;

create table if not exists public.safety_phrases (
  id uuid primary key default gen_random_uuid(),
  phrase text not null check (char_length(trim(phrase)) between 2 and 80),
  lang text not null check (lang in ('en', 'sw')),
  urgency text not null default 'red' check (urgency in ('red', 'yellow')),
  published boolean not null default false,
  archived boolean not null default false,
  updated_by uuid references public.profiles(id) on delete set null,
  updated_at timestamptz not null default now(),
  unique (phrase, lang)
);
create index if not exists safety_phrases_updated_by_idx on public.safety_phrases (updated_by);
alter table public.safety_phrases enable row level security;
do $$ begin
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'safety_phrases' and policyname = 'safety_phrases_staff') then
    create policy safety_phrases_staff on public.safety_phrases for select to authenticated using (public.web_can('read'));
  end if;
end $$;
revoke all on public.mamabot_entries, public.safety_phrases from anon, authenticated;
grant select on public.mamabot_entries, public.safety_phrases to authenticated;

create or replace function public.mamabot_text(e public.mamabot_entries)
returns text language sql immutable set search_path = public as $$
  select array_to_string(e.patterns, '|') || '#' || e.answer_en || '#' || e.answer_sw || '#' || e.urgency
$$;

create or replace function public.mamabot_entry_save(p_id uuid, p_patterns text[], p_answer_en text, p_answer_sw text,
                                                     p_urgency text, p_lesson text, p_reference text)
returns uuid language plpgsql security definer set search_path = public as $$
declare v uuid := p_id; r mamabot_entries;
begin
  perform public.web_need('edit');
  if cardinality(p_patterns) = 0 or exists (select 1 from unnest(p_patterns) x where char_length(trim(x)) < 2) then
    raise exception 'Add at least one question pattern (2 letters or more each).' using errcode = '22023';
  end if;
  if v is null then
    insert into mamabot_entries (patterns, answer_en, answer_sw, urgency, source_lesson_id, reference, updated_by)
    values (p_patterns, trim(p_answer_en), trim(p_answer_sw), p_urgency, nullif(trim(p_lesson), ''), nullif(trim(p_reference), ''), auth.uid())
    returning id into v;
  else
    update mamabot_entries set patterns = p_patterns, answer_en = trim(p_answer_en), answer_sw = trim(p_answer_sw), urgency = p_urgency,
      source_lesson_id = nullif(trim(p_lesson), ''), reference = nullif(trim(p_reference), ''), updated_by = auth.uid(), updated_at = now()
    where id = v returning * into r;
    -- a changed answer leaves the website until it is reviewed again
    if r.review_hash is distinct from md5(public.mamabot_text(r)) then
      update mamabot_entries set published = false, reviewed_by = null, reviewed_on = null, review_hash = null where id = v;
    end if;
  end if;
  perform public.cms_revision('mamabot_entries', v::text, (select to_jsonb(e) - 'updated_by' from mamabot_entries e where e.id = v));
  perform public.cms_audit('content_save', 'mamabot_entries', v::text);
  return v;
end $$;

-- Clinical approval of the exact current text. A clinical reviewer signs with their own name; an
-- Admin records the reviewer's role and cadre.
create or replace function public.mamabot_entry_review(p_id uuid, p_reviewer text default null)
returns void language plpgsql security definer set search_path = public as $$
declare v_by text;
begin
  perform public.web_need('review');
  v_by := case when public.web_role() = 'clinical_reviewer'
               then (select display_name from profiles where id = auth.uid()) || ', clinical reviewer'
               else nullif(trim(coalesce(p_reviewer, '')), '') end;
  if coalesce(char_length(v_by), 0) < 3 then
    raise exception 'Write who reviewed it (role and cadre).' using errcode = '22023';
  end if;
  update mamabot_entries e set reviewed_by = left(v_by, 120), reviewed_on = current_date, review_hash = md5(public.mamabot_text(e))
  where id = p_id;
  perform public.cms_audit('content_review', 'mamabot_entries', p_id::text, jsonb_build_object('decision', 'approved'));
end $$;

create or replace function public.mamabot_entry_publish(p_id uuid, p_published boolean)
returns void language plpgsql security definer set search_path = public as $$
declare r mamabot_entries;
begin
  perform public.web_need('edit');
  select * into r from mamabot_entries where id = p_id and not archived;
  if r.id is null then raise exception 'This answer no longer exists.' using errcode = 'P0002'; end if;
  if p_published then
    if trim(r.answer_en) = '' or trim(r.answer_sw) = '' then
      raise exception 'Write the answer in English and Kiswahili first.' using errcode = '22023';
    end if;
    if r.review_hash is distinct from md5(public.mamabot_text(r)) then
      raise exception 'A clinical reviewer must approve this exact answer before it goes on the website.' using errcode = '42501';
    end if;
  end if;
  update mamabot_entries set published = p_published, updated_at = now() where id = p_id;
  perform public.cms_audit(case when p_published then 'content_publish' else 'content_unpublish' end, 'mamabot_entries', p_id::text);
end $$;

create or replace function public.mamabot_entry_archive(p_id uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  perform public.web_need('edit');
  update mamabot_entries set archived = true, published = false, updated_at = now() where id = p_id;
  perform public.cms_audit('content_archive', 'mamabot_entries', p_id::text);
end $$;

create or replace function public.safety_phrase_save(p_id uuid, p_phrase text, p_lang text, p_urgency text)
returns uuid language plpgsql security definer set search_path = public as $$
declare v uuid := p_id;
begin
  perform public.web_need('review');
  if v is null then
    insert into safety_phrases (phrase, lang, urgency, updated_by) values (lower(trim(p_phrase)), p_lang, p_urgency, auth.uid())
    on conflict (phrase, lang) do update set urgency = excluded.urgency, archived = false, updated_by = auth.uid(), updated_at = now()
    returning id into v;
  else
    update safety_phrases set phrase = lower(trim(p_phrase)), lang = p_lang, urgency = p_urgency, updated_by = auth.uid(), updated_at = now()
    where id = v;
  end if;
  perform public.cms_audit('content_save', 'safety_phrases', v::text);
  return v;
end $$;

create or replace function public.safety_phrase_publish(p_id uuid, p_published boolean)
returns void language plpgsql security definer set search_path = public as $$
begin
  perform public.web_need('review');
  update safety_phrases set published = p_published, updated_at = now() where id = p_id and not archived;
  perform public.cms_audit(case when p_published then 'content_publish' else 'content_unpublish' end, 'safety_phrases', p_id::text);
end $$;

create or replace function public.safety_phrase_archive(p_id uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  perform public.web_need('review');
  update safety_phrases set archived = true, published = false, updated_at = now() where id = p_id;
  perform public.cms_audit('content_archive', 'safety_phrases', p_id::text);
end $$;

-- What the website's MamaBot reads (anon): published answers and safety phrases, and its settings.
create or replace function public.mamabot_public()
returns jsonb language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'entries', coalesce((select jsonb_agg(jsonb_build_object('id', e.id, 'patterns', e.patterns, 'answer', jsonb_build_object('en', e.answer_en, 'sw', e.answer_sw),
        'urgency', e.urgency, 'lesson', e.source_lesson_id, 'reference', e.reference, 'reviewed_by', e.reviewed_by, 'reviewed_on', e.reviewed_on))
      from mamabot_entries e where e.published and not e.archived and e.review_hash = md5(public.mamabot_text(e))), '[]'::jsonb),
    'safety', coalesce((select jsonb_agg(jsonb_build_object('phrase', s.phrase, 'lang', s.lang, 'urgency', s.urgency))
      from safety_phrases s where s.published and not s.archived), '[]'::jsonb),
    'settings', coalesce((select value from site_settings where key = 'mamabot'), '{}'::jsonb))
$$;

-- Admin-only settings keys now include robots and mamabot.
create or replace function public.site_setting_save(p_key text, p_draft jsonb, p_publish boolean default false)
returns void language plpgsql security definer set search_path = public as $$
begin
  perform public.web_need(case when p_key in ('banner', 'site', 'robots', 'mamabot') then 'admin' else 'edit' end);
  if jsonb_typeof(p_draft) <> 'object' or pg_column_size(p_draft) > 50000 then
    raise exception 'These settings could not be saved.' using errcode = '22023';
  end if;
  insert into site_settings (key, draft, has_changes, updated_by) values (p_key, p_draft, true, auth.uid())
  on conflict (key) do update set draft = excluded.draft, has_changes = true, updated_by = auth.uid(), updated_at = now();
  if p_publish then
    update site_settings set value = draft, has_changes = false where key = p_key;
  end if;
  perform public.cms_revision('site_settings', p_key, jsonb_build_object('draft', p_draft), case when p_publish then 'publish' else 'save' end);
  perform public.cms_audit(case when p_publish then 'content_publish' else 'content_save' end, 'site_settings', p_key);
end $$;

-- Contact form via the Edge Function: same checks as submit_contact, with the sender hash the
-- function computed from the visitor's address. Service role only.
create or replace function public.submit_contact_from(p_name text, p_organisation text, p_email text, p_topic text, p_message text, p_sender text)
returns uuid language plpgsql security definer set search_path = public as $$
declare v uuid;
begin
  if (select count(*) from contact_messages where sender_hash = p_sender and created_at > now() - interval '1 hour') >= 5
     or (select count(*) from contact_messages where created_at > now() - interval '1 day') >= 300 then
    raise exception 'Too many messages. Please try again later or email us.' using errcode = '53400';
  end if;
  insert into contact_messages (name, organisation, email, topic, message, sender_hash)
  values (trim(p_name), nullif(trim(p_organisation), ''), lower(trim(p_email)), nullif(trim(p_topic), ''), trim(p_message), p_sender)
  returning id into v;
  return v;
end $$;

-- What the sitemap needs (anon): published post addresses and dates.
create or replace function public.site_sitemap()
returns jsonb language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'posts', coalesce((select jsonb_agg(jsonb_build_object('slug', slug, 'updated', updated_at) order by published_at desc)
      from blog_posts where published and not archived and published_at <= now()), '[]'::jsonb),
    'noindex', coalesce((select jsonb_agg(path) from seo_pages where noindex), '[]'::jsonb),
    'robots', (select value ->> 'text' from site_settings where key = 'robots'))
$$;

do $$
declare f text;
begin
  revoke all on function public.mamabot_text(public.mamabot_entries) from public, anon, authenticated;
  foreach f in array array[
    'public.mamabot_entry_save(uuid, text[], text, text, text, text, text)', 'public.mamabot_entry_review(uuid, text)',
    'public.mamabot_entry_publish(uuid, boolean)', 'public.mamabot_entry_archive(uuid)',
    'public.safety_phrase_save(uuid, text, text, text)', 'public.safety_phrase_publish(uuid, boolean)', 'public.safety_phrase_archive(uuid)'
  ] loop
    execute format('revoke all on function %s from public, anon', f);
    execute format('grant execute on function %s to authenticated', f);
  end loop;
  foreach f in array array['public.mamabot_public()', 'public.site_sitemap()'] loop
    execute format('revoke all on function %s from public', f);
    execute format('grant execute on function %s to anon, authenticated', f);
  end loop;
  revoke all on function public.submit_contact_from(text, text, text, text, text, text) from public, anon, authenticated;
end $$;
