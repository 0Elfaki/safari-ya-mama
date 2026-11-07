-- Website CMS: everything the public website (safariyamama.com) shows, managed from the dashboard's
-- Website section. Spec: "Safari ya Mama Studio" (website-dashboard-prompt.md), built into the
-- staff dashboard instead of a separate app.
--
-- How it works
--   * Every editable thing has a working copy (draft) and a live copy. Saving changes only the
--     draft; Publish copies it to the live copy. The website reads live copies only, with the anon
--     key, through site_public() and the blog_posts table (published rows, selected columns).
--   * Writes go only through the security definer functions below (no insert/update policies), so
--     the workflow rules (review, clinical sign-off, confirmed partners) cannot be skipped.
--   * Every change writes a revision (snapshot, restorable) and an audit_log row (no personal data).
--   * Nothing is deleted: posts, sections, media, partners and figures are archived.
--   * The website's earlier supabase/migrations/20261106_blog.sql is superseded by this file
--     (same tables and columns the website reads, plus workflow columns; roles come from profiles).
--
-- Roles (profiles.role, set only through the admin-users Edge Function), all with two-step sign-in:
--   super_admin, programme_admin (Admin) .. everything, incl. confirming partners, archiving, inbox export
--   editor ................................ write, edit and publish posts; edit pages, media, partners, figures
--   author ................................ write and edit own blog drafts, submit for review
--   clinical_reviewer ..................... approve health content (blog posts that mention symptoms)
--   viewer ................................ read only

-- ───────────── role helpers
create or replace function public.web_role()
returns text language sql stable security definer set search_path = public as $$
  select case when public.mfa_ok()
               and public.my_role() in ('super_admin', 'programme_admin', 'editor', 'author', 'clinical_reviewer', 'viewer')
              then public.my_role()::text end
$$;

-- p: 'read' | 'write' (blog drafts) | 'edit' (publish, pages, media) | 'review' (clinical) | 'admin'
create or replace function public.web_can(p text)
returns boolean language sql stable security definer set search_path = public as $$
  select coalesce(case p
    when 'read'   then public.web_role() is not null
    when 'write'  then public.web_role() in ('super_admin', 'programme_admin', 'editor', 'author')
    when 'edit'   then public.web_role() in ('super_admin', 'programme_admin', 'editor')
    when 'review' then public.web_role() in ('super_admin', 'programme_admin', 'clinical_reviewer')
    when 'admin'  then public.web_role() in ('super_admin', 'programme_admin')
    else false end, false)
$$;

create or replace function public.web_need(p text)
returns void language plpgsql stable security definer set search_path = public as $$
begin
  if not public.web_can(p) then
    raise exception 'You do not have permission to do this.' using errcode = '42501';
  end if;
end $$;

-- ───────────── revisions (restorable snapshots)
create table if not exists public.revisions (
  id bigint generated always as identity primary key,
  table_name text not null,
  row_id text not null,
  snapshot jsonb not null,
  author uuid references public.profiles(id) on delete set null,
  note text not null default 'save',
  created_at timestamptz not null default now()
);
create index if not exists revisions_row_idx on public.revisions (table_name, row_id, id desc);
alter table public.revisions enable row level security;
do $$ begin
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'revisions' and policyname = 'revisions_read') then
    create policy revisions_read on public.revisions for select to authenticated using (public.web_can('read'));
  end if;
end $$;

-- One revision per save; quick autosaves by the same person within 2 minutes update the last one.
create or replace function public.cms_revision(p_table text, p_row text, p_snapshot jsonb, p_note text default 'save')
returns void language plpgsql security definer set search_path = public as $$
declare v_last revisions;
begin
  select * into v_last from revisions where table_name = p_table and row_id = p_row order by id desc limit 1;
  if p_note = 'save' and v_last.id is not null and v_last.note = 'save' and v_last.author is not distinct from auth.uid()
     and v_last.created_at > now() - interval '2 minutes' then
    update revisions set snapshot = p_snapshot where id = v_last.id;
  else
    insert into revisions (table_name, row_id, snapshot, author, note) values (p_table, p_row, p_snapshot, auth.uid(), p_note);
  end if;
end $$;

create or replace function public.cms_audit(p_action text, p_table text, p_row text, p_extra jsonb default '{}'::jsonb)
returns void language sql security definer set search_path = public as $$
  insert into audit_log (actor_id, action, details)
  values (auth.uid(), p_action, jsonb_build_object('table', p_table, 'row_id', p_row) || coalesce(p_extra, '{}'::jsonb))
$$;

-- ───────────── preview links (short-lived, staff only)
create table if not exists public.preview_tokens (
  token uuid primary key default gen_random_uuid(),
  created_by uuid not null references public.profiles(id) on delete cascade,
  expires_at timestamptz not null default now() + interval '30 minutes'
);
alter table public.preview_tokens enable row level security; -- read only through site_preview() / blog_preview()

create or replace function public.preview_token()
returns uuid language plpgsql security definer set search_path = public as $$
declare v uuid;
begin
  perform public.web_need('read');
  insert into preview_tokens (created_by) values (auth.uid()) returning token into v;
  return v;
end $$;

create or replace function public.preview_ok(p_token uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from preview_tokens where token = p_token and expires_at > now())
$$;

-- ───────────── blog
create table if not exists public.blog_authors (
  id          text primary key,
  name        text not null,
  role        text,
  bio         text,
  created_at  timestamptz not null default now()
);
alter table public.blog_authors add column if not exists archived boolean not null default false;
alter table public.blog_authors add column if not exists updated_at timestamptz not null default now();

create table if not exists public.blog_posts (
  id               uuid primary key default gen_random_uuid(),
  slug             text not null unique check (slug ~ '^[a-z0-9]+(-[a-z0-9]+)*$'),
  title            text not null,
  excerpt          text not null default '',
  category         text not null default 'Product Updates' check (category in (
                     'Maternal Health', 'FemTech and AI', 'Research and Innovation',
                     'Community Stories', 'Product Updates')),
  author_id        text not null references public.blog_authors (id),
  published_at     timestamptz not null default now(),
  reading_minutes  int check (reading_minutes between 1 and 60),
  cover_url        text,
  cover_small_url  text,
  cover_alt        text,
  featured         boolean not null default false,
  published        boolean not null default false,
  body             jsonb not null default '[]'::jsonb check (jsonb_typeof(body) = 'array'),
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now(),
  constraint cover_needs_alt check (cover_url is null or coalesce(cover_alt, '') <> '')
);
create index if not exists blog_posts_live_idx on public.blog_posts (published, published_at desc);

alter table public.blog_posts add column if not exists status text not null default 'draft';
alter table public.blog_posts add column if not exists draft jsonb not null default '{}'::jsonb;
alter table public.blog_posts add column if not exists has_draft_changes boolean not null default false;
alter table public.blog_posts add column if not exists draft_updated_at timestamptz not null default now();
alter table public.blog_posts add column if not exists draft_updated_by uuid references public.profiles(id) on delete set null;
alter table public.blog_posts add column if not exists created_by uuid references public.profiles(id) on delete set null;
alter table public.blog_posts add column if not exists seo_title text;
alter table public.blog_posts add column if not exists seo_description text;
alter table public.blog_posts add column if not exists health_review text not null default 'not_needed';
alter table public.blog_posts add column if not exists reviewed_by text;
alter table public.blog_posts add column if not exists reviewed_on date;
alter table public.blog_posts add column if not exists review_note text;
alter table public.blog_posts add column if not exists review_hash text;
alter table public.blog_posts add column if not exists archived boolean not null default false;
do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'blog_posts_status_check') then
    alter table public.blog_posts add constraint blog_posts_status_check check (status in ('draft', 'in_review', 'published', 'unpublished'));
  end if;
  if not exists (select 1 from pg_constraint where conname = 'blog_posts_health_review_check') then
    alter table public.blog_posts add constraint blog_posts_health_review_check
      check (health_review in ('not_needed', 'requested', 'approved', 'changes_requested'));
  end if;
end $$;

create or replace function public.blog_touch_updated_at() returns trigger
language plpgsql set search_path = public as $$ begin new.updated_at := now(); return new; end $$;
create or replace trigger blog_posts_updated_at before update on public.blog_posts
  for each row execute function public.blog_touch_updated_at();

alter table public.blog_authors enable row level security;
alter table public.blog_posts enable row level security;
do $$ begin
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'blog_authors' and policyname = 'blog_authors_public') then
    create policy blog_authors_public on public.blog_authors for select to anon, authenticated using (true);
  end if;
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'blog_posts' and policyname = 'blog_posts_public') then
    create policy blog_posts_public on public.blog_posts for select to anon
      using (published and not archived and published_at <= now());
  end if;
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'blog_posts' and policyname = 'blog_posts_staff') then
    create policy blog_posts_staff on public.blog_posts for select to authenticated using (public.web_can('read'));
  end if;
end $$;
-- The website (anon) may read only the live columns, never the draft or review notes.
revoke all on public.blog_posts from anon, authenticated;
grant select (id, slug, title, excerpt, category, author_id, published_at, reading_minutes, cover_url, cover_small_url, cover_alt,
              featured, published, body, created_at, updated_at, seo_title, seo_description) on public.blog_posts to anon;
grant select on public.blog_posts to authenticated;
revoke all on public.blog_authors from anon, authenticated;
grant select on public.blog_authors to anon, authenticated;

insert into public.blog_authors (id, name, role, bio) values
  ('product', 'Safari ya Mama product team', 'Product and design', 'The team designing the Safari ya Mama app, staff dashboard and website.'),
  ('content', 'Safari ya Mama content team', 'Health education content', 'Prepares lessons and danger-sign guidance from WHO guidance, for review by qualified clinicians before use.'),
  ('engineering', 'Zatii Technologies engineering', 'Engineering', 'Builds and tests the app, the server and the shared safety rules engine.')
on conflict (id) do nothing;

-- Body blocks: p / h2 / h3 / quote {text, source?} and ul {items}. Inline **bold**, *italic*, [text](https://…).
create or replace function public.blog_body_ok(p jsonb)
returns boolean language sql immutable set search_path = public as $$
  select jsonb_typeof(p) = 'array' and not exists (
    select 1 from jsonb_array_elements(p) b
    where not ((b ->> 'type' in ('p', 'h2', 'h3', 'quote') and jsonb_typeof(b -> 'text') = 'string')
            or (b ->> 'type' = 'ul' and jsonb_typeof(b -> 'items') = 'array'
                and not exists (select 1 from jsonb_array_elements(b -> 'items') i where jsonb_typeof(i) <> 'string'))))
$$;

create or replace function public.blog_text(d jsonb)
returns text language sql immutable set search_path = public as $$
  select coalesce(d ->> 'title', '') || ' ' || coalesce(d ->> 'excerpt', '') || ' ' ||
         coalesce((select string_agg(coalesce(b ->> 'text', (select string_agg(i, ' ') from jsonb_array_elements_text(b -> 'items') i)), ' ')
                   from jsonb_array_elements(coalesce(d -> 'body', '[]'::jsonb)) b), '')
$$;

-- Needs clinical sign-off before publishing: the text mentions symptoms or danger signs.
create or replace function public.blog_needs_review(d jsonb)
returns boolean language sql stable set search_path = public as $$
  select public.mentions_symptoms(public.blog_text(d))
      or public.blog_text(d) ~* '(danger sign|bleeding|dose|dosage|pre-?eclampsia|miscarriage|convulsion)'
$$;

create or replace function public.blog_check_draft(d jsonb)
returns void language plpgsql immutable set search_path = public as $$
begin
  if jsonb_typeof(d) <> 'object' then raise exception 'The post could not be read.' using errcode = '22023'; end if;
  if coalesce(d ->> 'slug', '') !~ '^[a-z0-9]+(-[a-z0-9]+)*$' then
    raise exception 'The web address (slug) may use lower-case letters, digits and single hyphens only.' using errcode = '22023';
  end if;
  if char_length(coalesce(d ->> 'title', '')) > 200 or char_length(coalesce(d ->> 'excerpt', '')) > 400 then
    raise exception 'The title or excerpt is too long.' using errcode = '22023';
  end if;
  if d ? 'body' and not public.blog_body_ok(d -> 'body') then
    raise exception 'The post body has a block type the website cannot show.' using errcode = '22023';
  end if;
  if pg_column_size(d) > 400000 then raise exception 'The post is too long to save.' using errcode = '22023'; end if;
end $$;

-- Create (p_id null) or save the working copy. p_expected = the draft_updated_at the editor loaded;
-- if someone else saved since, the save is refused instead of overwriting their work.
create or replace function public.blog_save(p_id uuid, p_draft jsonb, p_expected timestamptz default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  r blog_posts;
  v_role text := public.web_role();
  v_hash text := md5(public.blog_text(p_draft));
  v_review text;
begin
  perform public.web_need('write');
  perform public.blog_check_draft(p_draft);
  if exists (select 1 from blog_posts where slug = p_draft ->> 'slug' and id is distinct from p_id) then
    raise exception 'Another post already uses this web address. Choose a different slug.' using errcode = '23505';
  end if;
  if p_id is null then
    insert into blog_posts (slug, title, excerpt, category, author_id, published, status, draft, created_by, draft_updated_by,
                            health_review)
    values (p_draft ->> 'slug', coalesce(nullif(p_draft ->> 'title', ''), 'Untitled'), '',
            coalesce(nullif(p_draft ->> 'category', ''), 'Product Updates'),
            coalesce(nullif(p_draft ->> 'author_id', ''), 'content'), false, 'draft', p_draft, auth.uid(), auth.uid(),
            case when public.blog_needs_review(p_draft) then 'requested' else 'not_needed' end)
    returning * into r;
    perform public.cms_revision('blog_posts', r.id::text, jsonb_build_object('draft', p_draft), 'created');
    perform public.cms_audit('content_create', 'blog_posts', r.id::text);
    return jsonb_build_object('id', r.id, 'draft_updated_at', r.draft_updated_at, 'health_review', r.health_review);
  end if;

  select * into r from blog_posts where id = p_id for update;
  if r.id is null or r.archived then raise exception 'This post no longer exists.' using errcode = 'P0002'; end if;
  if v_role = 'author' and r.created_by is distinct from auth.uid() then
    raise exception 'Authors can edit only their own posts.' using errcode = '42501';
  end if;
  if p_expected is not null and r.draft_updated_at > p_expected + interval '1 millisecond' then
    raise exception 'Someone else saved this post at %. Reload to see their changes before saving.',
      to_char(r.draft_updated_at at time zone 'Africa/Dar_es_Salaam', 'HH24:MI') using errcode = '40001';
  end if;
  v_review := case
    when not public.blog_needs_review(p_draft) then case when r.health_review = 'approved' then 'approved' else 'not_needed' end
    when r.health_review = 'approved' and r.review_hash = v_hash then 'approved'
    when r.health_review = 'changes_requested' then 'changes_requested'
    else 'requested' end;
  update blog_posts set
    draft = p_draft, draft_updated_at = clock_timestamp(), draft_updated_by = auth.uid(),
    has_draft_changes = published,
    health_review = v_review,
    -- an unpublished post keeps its title and address in step with the draft (lists, unique slug)
    slug = case when published then slug else p_draft ->> 'slug' end,
    title = case when published then title else coalesce(nullif(p_draft ->> 'title', ''), 'Untitled') end
  where id = p_id returning * into r;
  perform public.cms_revision('blog_posts', r.id::text, jsonb_build_object('draft', p_draft));
  perform public.cms_audit('content_save', 'blog_posts', r.id::text);
  return jsonb_build_object('id', r.id, 'draft_updated_at', r.draft_updated_at, 'health_review', r.health_review);
end $$;

create or replace function public.blog_submit(p_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare r blog_posts;
begin
  perform public.web_need('write');
  select * into r from blog_posts where id = p_id and not archived;
  if r.id is null then raise exception 'This post no longer exists.' using errcode = 'P0002'; end if;
  if public.web_role() = 'author' and r.created_by is distinct from auth.uid() then
    raise exception 'Authors can submit only their own posts.' using errcode = '42501';
  end if;
  update blog_posts set status = case when published then status else 'in_review' end,
    health_review = case when health_review = 'changes_requested' then 'requested' else health_review end
  where id = p_id;
  perform public.cms_audit('content_submit', 'blog_posts', p_id::text);
end $$;

-- Clinical review: approve or ask for changes. A clinical reviewer signs with their own name; an
-- Admin signing off records the reviewer's role and cadre (as for lessons).
create or replace function public.blog_review(p_id uuid, p_decision text, p_note text default null, p_reviewer text default null)
returns void language plpgsql security definer set search_path = public as $$
declare
  r blog_posts;
  v_by text;
begin
  select * into r from blog_posts where id = p_id and not archived;
  if r.id is null then raise exception 'This post no longer exists.' using errcode = 'P0002'; end if;
  if p_decision = 'requested' then
    perform public.web_need('write');
    update blog_posts set health_review = 'requested', review_note = left(p_note, 600) where id = p_id;
  elsif p_decision in ('approved', 'changes_requested') then
    perform public.web_need('review');
    v_by := case when public.web_role() = 'clinical_reviewer'
                 then (select display_name from profiles where id = auth.uid()) || ', clinical reviewer'
                 else nullif(trim(coalesce(p_reviewer, '')), '') end;
    if p_decision = 'approved' and coalesce(char_length(v_by), 0) < 3 then
      raise exception 'Write who reviewed it (role and cadre).' using errcode = '22023';
    end if;
    update blog_posts set health_review = p_decision, review_note = left(p_note, 600),
      reviewed_by = case when p_decision = 'approved' then left(v_by, 120) else reviewed_by end,
      reviewed_on = case when p_decision = 'approved' then current_date else reviewed_on end,
      review_hash = case when p_decision = 'approved' then md5(public.blog_text(draft)) else review_hash end
    where id = p_id;
  else
    raise exception 'Unknown review decision.' using errcode = '22023';
  end if;
  perform public.cms_audit('content_review', 'blog_posts', p_id::text, jsonb_build_object('decision', p_decision));
end $$;

create or replace function public.blog_publish(p_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare
  r blog_posts;
  d jsonb;
begin
  perform public.web_need('edit');
  select * into r from blog_posts where id = p_id and not archived for update;
  if r.id is null then raise exception 'This post no longer exists.' using errcode = 'P0002'; end if;
  d := r.draft;
  perform public.blog_check_draft(d);
  if coalesce(trim(d ->> 'title'), '') = '' or coalesce(trim(d ->> 'excerpt'), '') = ''
     or coalesce(d ->> 'category', '') = '' or coalesce(d ->> 'author_id', '') = '' then
    raise exception 'Add a title, excerpt, category and author before publishing.' using errcode = '22023';
  end if;
  if not exists (select 1 from blog_authors where id = d ->> 'author_id' and not archived) then
    raise exception 'Choose an author from the list.' using errcode = '22023';
  end if;
  if coalesce(d ->> 'cover_url', '') <> '' and coalesce(trim(d ->> 'cover_alt'), '') = '' then
    raise exception 'The cover picture needs alt text.' using errcode = '22023';
  end if;
  if jsonb_array_length(coalesce(d -> 'body', '[]'::jsonb)) = 0 then
    raise exception 'The post has no text yet.' using errcode = '22023';
  end if;
  if exists (select 1 from jsonb_array_elements(d -> 'body') b where b ->> 'type' in ('h2', 'h3') and trim(b ->> 'text') = '') then
    raise exception 'Remove or fill the empty headings.' using errcode = '22023';
  end if;
  if exists (select 1 from jsonb_array_elements(d -> 'body') b where b ->> 'type' = 'quote' and coalesce(trim(b ->> 'source'), '') = '') then
    raise exception 'Every quote needs its source (who said it, or where it was published).' using errcode = '22023';
  end if;
  if public.blog_needs_review(d) and not (r.health_review = 'approved' and r.review_hash = md5(public.blog_text(d))) then
    raise exception 'This post mentions symptoms or danger signs. A clinical reviewer must approve this version before it is published.'
      using errcode = '42501';
  end if;
  if coalesce((d ->> 'featured')::boolean, false) then
    update blog_posts set featured = false where featured and id <> p_id;
  end if;
  update blog_posts set
    slug = d ->> 'slug', title = d ->> 'title', excerpt = coalesce(d ->> 'excerpt', ''), category = d ->> 'category',
    author_id = d ->> 'author_id',
    published_at = coalesce(nullif(d ->> 'published_at', '')::timestamptz, now()),
    reading_minutes = least(60, greatest(1, nullif(d ->> 'reading_minutes', '')::int)),
    cover_url = nullif(d ->> 'cover_url', ''), cover_small_url = nullif(d ->> 'cover_small_url', ''),
    cover_alt = nullif(d ->> 'cover_alt', ''),
    featured = coalesce((d ->> 'featured')::boolean, false),
    body = coalesce(d -> 'body', '[]'::jsonb),
    seo_title = nullif(d ->> 'seo_title', ''), seo_description = nullif(d ->> 'seo_description', ''),
    published = true, status = 'published', has_draft_changes = false
  where id = p_id;
  perform public.cms_revision('blog_posts', p_id::text, jsonb_build_object('draft', d), 'publish');
  perform public.cms_audit('content_publish', 'blog_posts', p_id::text);
end $$;

create or replace function public.blog_unpublish(p_id uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  perform public.web_need('edit');
  update blog_posts set published = false, status = 'unpublished', featured = false where id = p_id;
  perform public.cms_audit('content_unpublish', 'blog_posts', p_id::text);
end $$;

-- Admins only. Archived posts leave the website and the lists; nothing is deleted.
create or replace function public.blog_archive(p_id uuid, p_archived boolean default true)
returns void language plpgsql security definer set search_path = public as $$
begin
  perform public.web_need('admin');
  update blog_posts set archived = p_archived, published = case when p_archived then false else published end,
    status = case when p_archived and published then 'unpublished' else status end, featured = false
  where id = p_id;
  perform public.cms_audit(case when p_archived then 'content_archive' else 'content_unarchive' end, 'blog_posts', p_id::text);
end $$;

create or replace function public.blog_restore(p_id uuid, p_revision bigint)
returns void language plpgsql security definer set search_path = public as $$
declare v jsonb;
begin
  perform public.web_need('write');
  select snapshot -> 'draft' into v from revisions where id = p_revision and table_name = 'blog_posts' and row_id = p_id::text;
  if v is null then raise exception 'That version was not found.' using errcode = 'P0002'; end if;
  perform public.blog_save(p_id, v, null);
  perform public.cms_audit('content_restore', 'blog_posts', p_id::text, jsonb_build_object('revision', p_revision));
end $$;

create or replace function public.blog_author_save(p_id text, p_name text, p_role text, p_bio text)
returns void language plpgsql security definer set search_path = public as $$
begin
  perform public.web_need('edit');
  if coalesce(p_id, '') !~ '^[a-z0-9]+(-[a-z0-9]+)*$' or char_length(trim(coalesce(p_name, ''))) < 2 then
    raise exception 'Give the author a short id (lower-case, hyphens) and a name.' using errcode = '22023';
  end if;
  insert into blog_authors (id, name, role, bio) values (p_id, trim(p_name), nullif(trim(p_role), ''), nullif(trim(p_bio), ''))
  on conflict (id) do update set name = excluded.name, role = excluded.role, bio = excluded.bio, updated_at = now(), archived = false;
  perform public.cms_audit('content_save', 'blog_authors', p_id);
end $$;

create or replace function public.blog_author_archive(p_id text)
returns void language plpgsql security definer set search_path = public as $$
begin
  perform public.web_need('edit');
  if exists (select 1 from blog_posts where not archived and (author_id = p_id or draft ->> 'author_id' = p_id)) then
    raise exception 'Posts still use this author. Change their author first.' using errcode = '23503';
  end if;
  update blog_authors set archived = true, updated_at = now() where id = p_id;
  perform public.cms_audit('content_archive', 'blog_authors', p_id);
end $$;

-- Draft preview for the website (staff open it with a short-lived token).
create or replace function public.blog_preview(p_token uuid, p_id uuid)
returns jsonb language sql stable security definer set search_path = public as $$
  select case when public.preview_ok(p_token) then
    (select draft || jsonb_build_object('id', id) from blog_posts where id = p_id) end
$$;

-- ───────────── pages: sections
create table if not exists public.site_sections (
  id uuid primary key default gen_random_uuid(),
  page text not null check (page ~ '^[a-z0-9-]{1,40}$'),
  section_key text not null check (section_key ~ '^[a-z0-9-]{1,60}$'),
  label text not null default '',
  sort integer not null default 0,
  visible boolean not null default true,
  data jsonb,                                   -- live copy; null = not published (website uses its built-in text)
  draft jsonb not null default '{}'::jsonb,
  draft_sort integer not null default 0,
  draft_visible boolean not null default true,
  defaults jsonb not null default '{}'::jsonb,  -- the website's built-in version ("Reset")
  published boolean not null default false,
  has_changes boolean not null default false,
  version integer not null default 0,
  archived boolean not null default false,
  updated_by uuid references public.profiles(id) on delete set null,
  updated_at timestamptz not null default now(),
  published_at timestamptz,
  unique (page, section_key)
);
alter table public.site_sections enable row level security;
do $$ begin
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'site_sections' and policyname = 'site_sections_staff') then
    create policy site_sections_staff on public.site_sections for select to authenticated using (public.web_can('read'));
  end if;
end $$;

-- Adds sections the website has built in (from the dashboard's "Import from the website"), and keeps
-- each section's built-in version current. Existing drafts and live copies are not touched.
create or replace function public.site_sections_import(p_sections jsonb)
returns integer language plpgsql security definer set search_path = public as $$
declare
  s jsonb;
  n integer := 0;
begin
  perform public.web_need('edit');
  for s in select * from jsonb_array_elements(p_sections) loop
    insert into site_sections (page, section_key, label, sort, draft_sort, defaults, draft)
    values (s ->> 'page', s ->> 'key', coalesce(s ->> 'label', ''), coalesce((s ->> 'sort')::int, 0), coalesce((s ->> 'sort')::int, 0),
            coalesce(s -> 'data', '{}'::jsonb), coalesce(s -> 'data', '{}'::jsonb))
    on conflict (page, section_key) do update set defaults = excluded.defaults, label = excluded.label;
    n := n + 1;
  end loop;
  perform public.cms_audit('content_import', 'site_sections', 'all', jsonb_build_object('sections', n));
  return n;
end $$;

create or replace function public.site_section_save(p_id uuid, p_draft jsonb, p_visible boolean, p_expected timestamptz default null)
returns timestamptz language plpgsql security definer set search_path = public as $$
declare r site_sections;
begin
  perform public.web_need('edit');
  if jsonb_typeof(p_draft) <> 'object' or pg_column_size(p_draft) > 300000 then
    raise exception 'This section could not be saved (too large or unreadable).' using errcode = '22023';
  end if;
  select * into r from site_sections where id = p_id for update;
  if r.id is null then raise exception 'This section no longer exists.' using errcode = 'P0002'; end if;
  if p_expected is not null and r.updated_at > p_expected + interval '1 millisecond' then
    raise exception 'Someone else saved this section at %. Reload to see their changes before saving.',
      to_char(r.updated_at at time zone 'Africa/Dar_es_Salaam', 'HH24:MI') using errcode = '40001';
  end if;
  update site_sections set draft = p_draft, draft_visible = coalesce(p_visible, draft_visible), has_changes = true,
    updated_by = auth.uid(), updated_at = clock_timestamp()
  where id = p_id returning * into r;
  perform public.cms_revision('site_sections', p_id::text, jsonb_build_object('draft', p_draft, 'visible', r.draft_visible));
  perform public.cms_audit('content_save', 'site_sections', p_id::text, jsonb_build_object('page', r.page, 'section', r.section_key));
  return r.updated_at;
end $$;

create or replace function public.site_sections_reorder(p_page text, p_ids uuid[])
returns void language plpgsql security definer set search_path = public as $$
begin
  perform public.web_need('edit');
  update site_sections s set draft_sort = o.i * 10, has_changes = has_changes or s.draft_sort <> o.i * 10, updated_at = clock_timestamp(),
    updated_by = auth.uid()
  from unnest(p_ids) with ordinality o(id, i) where s.id = o.id and s.page = p_page;
  perform public.cms_audit('content_reorder', 'site_sections', p_page);
end $$;

create or replace function public.site_section_publish(p_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare r site_sections;
begin
  perform public.web_need('edit');
  update site_sections set data = draft, visible = draft_visible, sort = draft_sort, published = true, has_changes = false,
    version = version + 1, published_at = now(), updated_by = auth.uid()
  where id = p_id and not archived returning * into r;
  if r.id is null then raise exception 'This section no longer exists.' using errcode = 'P0002'; end if;
  perform public.cms_revision('site_sections', p_id::text, jsonb_build_object('draft', r.draft, 'visible', r.visible), 'publish');
  perform public.cms_audit('content_publish', 'site_sections', p_id::text, jsonb_build_object('page', r.page, 'section', r.section_key));
end $$;

create or replace function public.site_page_publish(p_page text)
returns integer language plpgsql security definer set search_path = public as $$
declare v uuid; n integer := 0;
begin
  perform public.web_need('edit');
  for v in select id from site_sections where page = p_page and has_changes and not archived loop
    perform public.site_section_publish(v);
    n := n + 1;
  end loop;
  return n;
end $$;

-- Back to the website's built-in version (into the draft; publish to make it live).
create or replace function public.site_section_reset(p_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare r site_sections;
begin
  perform public.web_need('edit');
  select * into r from site_sections where id = p_id;
  if r.id is null then raise exception 'This section no longer exists.' using errcode = 'P0002'; end if;
  perform public.site_section_save(p_id, r.defaults, true, null);
end $$;

create or replace function public.site_section_restore(p_id uuid, p_revision bigint)
returns void language plpgsql security definer set search_path = public as $$
declare v jsonb;
begin
  perform public.web_need('edit');
  select snapshot into v from revisions where id = p_revision and table_name = 'site_sections' and row_id = p_id::text;
  if v is null then raise exception 'That version was not found.' using errcode = 'P0002'; end if;
  perform public.site_section_save(p_id, v -> 'draft', coalesce((v ->> 'visible')::boolean, true), null);
end $$;

-- ───────────── settings (site name, contact, socials, footer, banner) and SEO
create table if not exists public.site_settings (
  key text primary key check (key ~ '^[a-z0-9_]{1,40}$'),
  value jsonb,                                  -- live
  draft jsonb not null default '{}'::jsonb,
  has_changes boolean not null default false,
  updated_by uuid references public.profiles(id) on delete set null,
  updated_at timestamptz not null default now()
);
alter table public.site_settings enable row level security;
do $$ begin
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'site_settings' and policyname = 'site_settings_staff') then
    create policy site_settings_staff on public.site_settings for select to authenticated using (public.web_can('read'));
  end if;
end $$;

create or replace function public.site_setting_save(p_key text, p_draft jsonb, p_publish boolean default false)
returns void language plpgsql security definer set search_path = public as $$
begin
  perform public.web_need(case when p_key in ('banner', 'site') then 'admin' else 'edit' end);
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

create table if not exists public.seo_pages (
  path text primary key check (path ~ '^/[a-z0-9/_-]{0,120}$'),
  title text check (char_length(title) <= 70),
  description text check (char_length(description) <= 200),
  share_image_url text,
  noindex boolean not null default false,
  updated_by uuid references public.profiles(id) on delete set null,
  updated_at timestamptz not null default now()
);
alter table public.seo_pages enable row level security;
do $$ begin
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'seo_pages' and policyname = 'seo_pages_staff') then
    create policy seo_pages_staff on public.seo_pages for select to authenticated using (public.web_can('read'));
  end if;
end $$;

create or replace function public.seo_save(p_path text, p_title text, p_description text, p_image text, p_noindex boolean)
returns void language plpgsql security definer set search_path = public as $$
begin
  perform public.web_need('edit');
  insert into seo_pages (path, title, description, share_image_url, noindex, updated_by)
  values (p_path, nullif(trim(p_title), ''), nullif(trim(p_description), ''), nullif(trim(p_image), ''), coalesce(p_noindex, false), auth.uid())
  on conflict (path) do update set title = excluded.title, description = excluded.description,
    share_image_url = excluded.share_image_url, noindex = excluded.noindex, updated_by = auth.uid(), updated_at = now();
  perform public.cms_revision('seo_pages', p_path, jsonb_build_object('title', p_title, 'description', p_description,
    'share_image_url', p_image, 'noindex', p_noindex), 'publish');
  perform public.cms_audit('content_publish', 'seo_pages', p_path);
end $$;

-- ───────────── media library (website images in the site-media bucket)
create table if not exists public.media (
  id uuid primary key default gen_random_uuid(),
  path text not null unique,
  url text not null,
  url_small text,
  width integer,
  height integer,
  bytes integer,
  alt text not null check (char_length(trim(alt)) >= 3),
  kind text not null default 'photo' check (kind in ('illustration', 'photo', 'screenshot', 'logo')),
  archived boolean not null default false,
  created_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table public.media enable row level security;
do $$ begin
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'media' and policyname = 'media_staff') then
    create policy media_staff on public.media for select to authenticated using (public.web_can('read'));
  end if;
end $$;

create or replace function public.media_register(p_path text, p_url text, p_url_small text, p_width integer, p_height integer,
                                                 p_bytes integer, p_alt text, p_kind text)
returns uuid language plpgsql security definer set search_path = public as $$
declare v uuid;
begin
  perform public.web_need('edit');
  if p_kind = 'illustration' and p_alt !~* '^illustration' then p_alt := 'Illustration: ' || p_alt; end if;
  insert into media (path, url, url_small, width, height, bytes, alt, kind, created_by)
  values (p_path, p_url, p_url_small, p_width, p_height, p_bytes, trim(p_alt), p_kind, auth.uid())
  on conflict (path) do update set url = excluded.url, url_small = excluded.url_small, width = excluded.width, height = excluded.height,
    bytes = excluded.bytes, alt = excluded.alt, kind = excluded.kind, archived = false, updated_at = now()
  returning id into v;
  perform public.cms_audit('content_save', 'media', v::text);
  return v;
end $$;

create or replace function public.media_update(p_id uuid, p_alt text, p_kind text)
returns void language plpgsql security definer set search_path = public as $$
begin
  perform public.web_need('edit');
  update media set alt = trim(p_alt), kind = p_kind, updated_at = now() where id = p_id;
  perform public.cms_audit('content_save', 'media', p_id::text);
end $$;

create or replace function public.media_archive(p_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare v_url text;
begin
  perform public.web_need('edit');
  select url into v_url from media where id = p_id;
  if exists (select 1 from public.media_usage(v_url)) then
    raise exception 'This picture is still used. Replace it where it is used first.' using errcode = '23503';
  end if;
  update media set archived = true, updated_at = now() where id = p_id;
  perform public.cms_audit('content_archive', 'media', p_id::text);
end $$;

-- ───────────── partners and impact figures
create table if not exists public.partners (
  id uuid primary key default gen_random_uuid(),
  name text not null check (char_length(trim(name)) >= 2),
  logo_url text,
  logo_alt text,
  url text check (url is null or url ~ '^https://'),
  relationship text,
  status text not null default 'proposed' check (status in ('proposed', 'confirmed')),
  confirmed_by uuid references public.profiles(id) on delete set null,
  sort integer not null default 0,
  published boolean not null default false,
  archived boolean not null default false,
  updated_by uuid references public.profiles(id) on delete set null,
  updated_at timestamptz not null default now(),
  constraint partners_publish_confirmed check (not published or status = 'confirmed')
);
alter table public.partners enable row level security;
do $$ begin
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'partners' and policyname = 'partners_staff') then
    create policy partners_staff on public.partners for select to authenticated using (public.web_can('read'));
  end if;
end $$;

create or replace function public.partner_save(p_id uuid, p_name text, p_logo_url text, p_logo_alt text, p_url text,
                                               p_relationship text, p_sort integer)
returns uuid language plpgsql security definer set search_path = public as $$
declare v uuid := p_id;
begin
  perform public.web_need('edit');
  if v is null then
    insert into partners (name, logo_url, logo_alt, url, relationship, sort, updated_by)
    values (trim(p_name), nullif(p_logo_url, ''), nullif(trim(p_logo_alt), ''), nullif(trim(p_url), ''), nullif(trim(p_relationship), ''),
            coalesce(p_sort, 0), auth.uid()) returning id into v;
  else
    update partners set name = trim(p_name), logo_url = nullif(p_logo_url, ''), logo_alt = nullif(trim(p_logo_alt), ''),
      url = nullif(trim(p_url), ''), relationship = nullif(trim(p_relationship), ''), sort = coalesce(p_sort, sort),
      updated_by = auth.uid(), updated_at = now()
    where id = v;
  end if;
  perform public.cms_audit('content_save', 'partners', v::text);
  return v;
end $$;

-- Only an Admin may record that a partnership is confirmed (honesty rule: no claimed endorsements).
create or replace function public.partner_confirm(p_id uuid, p_confirmed boolean)
returns void language plpgsql security definer set search_path = public as $$
begin
  perform public.web_need('admin');
  update partners set status = case when p_confirmed then 'confirmed' else 'proposed' end,
    confirmed_by = case when p_confirmed then auth.uid() end,
    published = case when p_confirmed then published else false end, updated_at = now()
  where id = p_id;
  perform public.cms_audit('partner_confirm', 'partners', p_id::text, jsonb_build_object('confirmed', p_confirmed));
end $$;

create or replace function public.partner_publish(p_id uuid, p_published boolean)
returns void language plpgsql security definer set search_path = public as $$
begin
  perform public.web_need('edit');
  if p_published and not exists (select 1 from partners where id = p_id and status = 'confirmed') then
    raise exception 'Only a partnership an Admin has marked confirmed can be shown on the website.' using errcode = '42501';
  end if;
  update partners set published = p_published, updated_at = now() where id = p_id;
  perform public.cms_audit(case when p_published then 'content_publish' else 'content_unpublish' end, 'partners', p_id::text);
end $$;

create or replace function public.partner_archive(p_id uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  perform public.web_need('edit');
  update partners set archived = true, published = false, updated_at = now() where id = p_id;
  perform public.cms_audit('content_archive', 'partners', p_id::text);
end $$;

create table if not exists public.impact_kpis (
  id uuid primary key default gen_random_uuid(),
  label text not null check (char_length(trim(label)) >= 2),
  value numeric not null,
  unit text,
  source text not null check (char_length(trim(source)) >= 3),
  is_demo boolean not null default true,
  sort integer not null default 0,
  published boolean not null default false,
  archived boolean not null default false,
  updated_by uuid references public.profiles(id) on delete set null,
  updated_at timestamptz not null default now()
);
alter table public.impact_kpis enable row level security;
do $$ begin
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'impact_kpis' and policyname = 'impact_kpis_staff') then
    create policy impact_kpis_staff on public.impact_kpis for select to authenticated using (public.web_can('read'));
  end if;
end $$;

create or replace function public.impact_save(p_id uuid, p_label text, p_value numeric, p_unit text, p_source text,
                                              p_is_demo boolean, p_sort integer)
returns uuid language plpgsql security definer set search_path = public as $$
declare v uuid := p_id;
begin
  perform public.web_need('edit');
  if v is null then
    insert into impact_kpis (label, value, unit, source, is_demo, sort, updated_by)
    values (trim(p_label), p_value, nullif(trim(p_unit), ''), trim(p_source), coalesce(p_is_demo, true), coalesce(p_sort, 0), auth.uid())
    returning id into v;
  else
    update impact_kpis set label = trim(p_label), value = p_value, unit = nullif(trim(p_unit), ''), source = trim(p_source),
      is_demo = coalesce(p_is_demo, true), sort = coalesce(p_sort, sort), updated_by = auth.uid(), updated_at = now()
    where id = v;
  end if;
  perform public.cms_revision('impact_kpis', v::text, (select to_jsonb(k) - 'updated_by' from impact_kpis k where k.id = v));
  perform public.cms_audit('content_save', 'impact_kpis', v::text);
  return v;
end $$;

create or replace function public.impact_publish(p_id uuid, p_published boolean)
returns void language plpgsql security definer set search_path = public as $$
begin
  perform public.web_need('edit');
  update impact_kpis set published = p_published, updated_at = now() where id = p_id and not archived;
  perform public.cms_audit(case when p_published then 'content_publish' else 'content_unpublish' end, 'impact_kpis', p_id::text);
end $$;

create or replace function public.impact_archive(p_id uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  perform public.web_need('edit');
  update impact_kpis set archived = true, published = false, updated_at = now() where id = p_id;
  perform public.cms_audit('content_archive', 'impact_kpis', p_id::text);
end $$;

-- Where a picture is used (pages, posts, partners, settings).
create or replace function public.media_usage(p_url text)
returns table (kind text, label text) language sql stable security definer set search_path = public as $$
  select 'Page section', s.page || ' · ' || coalesce(nullif(s.label, ''), s.section_key) from site_sections s
   where not s.archived and (s.draft::text like '%' || p_url || '%' or coalesce(s.data::text, '') like '%' || p_url || '%')
  union all
  select 'Blog post', coalesce(nullif(p.draft ->> 'title', ''), p.title) from blog_posts p
   where not p.archived and (p.draft::text like '%' || p_url || '%' or coalesce(p.cover_url, '') = p_url or coalesce(p.cover_small_url, '') = p_url)
  union all
  select 'Partner', x.name from partners x where not x.archived and x.logo_url = p_url
  union all
  select 'Settings', st.key from site_settings st where st.draft::text like '%' || p_url || '%' or coalesce(st.value::text, '') like '%' || p_url || '%'
  union all
  select 'SEO', sp.path from seo_pages sp where sp.share_image_url = p_url
$$;

-- ───────────── contact form inbox (personal data: staff read it, it never goes to logs or revisions)
create table if not exists public.contact_messages (
  id uuid primary key default gen_random_uuid(),
  name text not null check (char_length(name) between 2 and 120),
  organisation text check (char_length(organisation) <= 160),
  email text not null check (email ~* '^[^@\s]+@[^@\s]+\.[^@\s]+$' and char_length(email) <= 200),
  topic text check (char_length(topic) <= 80),
  message text not null check (char_length(message) between 20 and 2000),
  status text not null default 'new' check (status in ('new', 'replied', 'archived')),
  note text check (char_length(note) <= 1000),
  sender_hash text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists contact_messages_status_idx on public.contact_messages (status, created_at desc);
alter table public.contact_messages enable row level security;
do $$ begin
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'contact_messages' and policyname = 'contact_messages_staff') then
    create policy contact_messages_staff on public.contact_messages for select to authenticated using (public.web_can('edit'));
  end if;
end $$;

-- The website's contact form (anon). At most 5 messages an hour from one sender, 300 a day in total.
create or replace function public.submit_contact(p_name text, p_organisation text, p_email text, p_topic text, p_message text)
returns boolean language plpgsql security definer set search_path = public as $$
declare
  v_hash text := md5(coalesce(split_part(current_setting('request.headers', true)::jsonb ->> 'x-forwarded-for', ',', 1), '') || 'sym-contact');
begin
  if (select count(*) from contact_messages where sender_hash = v_hash and created_at > now() - interval '1 hour') >= 5
     or (select count(*) from contact_messages where created_at > now() - interval '1 day') >= 300 then
    raise exception 'Too many messages. Please try again later or email us.' using errcode = '53400';
  end if;
  insert into contact_messages (name, organisation, email, topic, message, sender_hash)
  values (trim(p_name), nullif(trim(p_organisation), ''), lower(trim(p_email)), nullif(trim(p_topic), ''), trim(p_message), v_hash);
  return true;
end $$;

create or replace function public.contact_set_status(p_id uuid, p_status text, p_note text default null)
returns void language plpgsql security definer set search_path = public as $$
begin
  perform public.web_need('edit');
  update contact_messages set status = p_status, note = coalesce(left(p_note, 1000), note), updated_at = now() where id = p_id;
  perform public.cms_audit('contact_status', 'contact_messages', p_id::text, jsonb_build_object('status', p_status));
end $$;

-- ───────────── what the website reads (anon), and the staff preview of drafts
create or replace function public.site_bundle(p_drafts boolean)
returns jsonb language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'generated_at', now(),
    'sections', coalesce((select jsonb_object_agg(s.page || '/' || s.section_key, jsonb_build_object(
        'visible', case when p_drafts then s.draft_visible else s.visible end,
        'sort', case when p_drafts then s.draft_sort else s.sort end,
        'data', case when p_drafts then s.draft else s.data end))
      from site_sections s where not s.archived and (p_drafts or s.published)), '{}'::jsonb),
    'settings', coalesce((select jsonb_object_agg(st.key, case when p_drafts then st.draft else st.value end)
      from site_settings st where p_drafts or st.value is not null), '{}'::jsonb),
    'seo', coalesce((select jsonb_object_agg(sp.path, jsonb_build_object('title', sp.title, 'description', sp.description,
        'image', sp.share_image_url, 'noindex', sp.noindex)) from seo_pages sp), '{}'::jsonb),
    'partners', coalesce((select jsonb_agg(jsonb_build_object('name', p.name, 'logo', p.logo_url, 'logo_alt', p.logo_alt, 'url', p.url,
        'relationship', p.relationship) order by p.sort, p.name)
      from partners p where p.published and p.status = 'confirmed' and not p.archived), '[]'::jsonb),
    'impact', coalesce((select jsonb_agg(jsonb_build_object('label', k.label, 'value', k.value, 'unit', k.unit, 'source', k.source,
        'demo', k.is_demo) order by k.sort, k.label)
      from impact_kpis k where k.published and not k.archived), '[]'::jsonb))
$$;

create or replace function public.site_public()
returns jsonb language sql stable security definer set search_path = public as $$
  select public.site_bundle(false)
$$;

create or replace function public.site_preview(p_token uuid)
returns jsonb language sql stable security definer set search_path = public as $$
  select case when public.preview_ok(p_token) then public.site_bundle(true) end
$$;

-- ───────────── storage: website editors may upload to site-media; app pictures stay with Admins
alter policy media_admin_read on storage.objects
  using ((bucket_id = 'site-media' and public.web_can('read')) or (bucket_id in ('site-media', 'app-media') and public.is_platform_admin()));
alter policy media_admin_insert on storage.objects
  with check ((bucket_id = 'site-media' and public.web_can('edit') and name ~ '^[a-z0-9][a-z0-9/_.-]{0,199}\.(webp|png|jpe?g)$')
           or (bucket_id = 'app-media' and public.is_platform_admin() and name ~ '^[A-Z]{2,5}(-[A-Z0-9]+)+-P[0-9]{1,2}\.webp$'));
alter policy media_admin_update on storage.objects
  using ((bucket_id = 'site-media' and public.web_can('edit')) or (bucket_id = 'app-media' and public.is_platform_admin()))
  with check ((bucket_id = 'site-media' and public.web_can('edit') and name ~ '^[a-z0-9][a-z0-9/_.-]{0,199}\.(webp|png|jpe?g)$')
           or (bucket_id = 'app-media' and public.is_platform_admin() and name ~ '^[A-Z]{2,5}(-[A-Z0-9]+)+-P[0-9]{1,2}\.webp$'));

-- ───────────── accounts: website roles sign in under Administration (with MFA)
create or replace function public.admin_session()
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_role public.user_role := public.my_role();
begin
  if auth.uid() is null or v_role is null
     or v_role not in ('super_admin', 'programme_admin', 'editor', 'author', 'clinical_reviewer', 'viewer') then
    raise exception 'This entrance is for administrators and the website team' using errcode = '42501';
  end if;
  if public.mfa_ok() then
    insert into audit_log (actor_id, action) values (auth.uid(), 'admin_sign_in');
  end if;
  return jsonb_build_object('role', v_role, 'mfa', public.mfa_ok(),
    'name', (select display_name from profiles where id = auth.uid()));
end $$;

create or replace function public.can_manage_account(p_role public.user_role, p_facility uuid default null)
returns boolean language sql stable security definer set search_path = public as $$
  select case
    when p_role in ('super_admin', 'programme_admin', 'facility_admin') then public.is_super_admin()
    when p_role in ('editor', 'author', 'clinical_reviewer', 'viewer') then public.is_platform_admin()
    when p_role = 'health_worker' then public.is_platform_admin()
      or (p_facility is not null and public.facility_admin_of(p_facility))
    else false end
$$;

create or replace function public.can_manage_user(p_target uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select p_target is distinct from auth.uid() and exists (
    select 1 from profiles t where t.id = p_target and t.deleted_at is null and case
      when t.role in ('super_admin', 'programme_admin', 'facility_admin') then public.is_super_admin()
      when t.role in ('editor', 'author', 'clinical_reviewer', 'viewer') then public.is_platform_admin()
      when t.role = 'health_worker' then public.is_platform_admin()
        or exists (select 1 from staff_assignments s where s.staff_id = t.id and public.facility_admin_of(s.facility_id))
      else false end)
$$;

create or replace function public.admin_set_role(p_user uuid, p_role public.user_role)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_old public.user_role;
  v_web constant public.user_role[] := array['editor', 'author', 'clinical_reviewer', 'viewer']::public.user_role[];
  v_all constant public.user_role[] := array['health_worker', 'facility_admin', 'programme_admin', 'super_admin',
                                             'editor', 'author', 'clinical_reviewer', 'viewer']::public.user_role[];
begin
  if p_user = auth.uid() then
    raise exception 'you cannot change your own role' using errcode = '42501';
  end if;
  select role into v_old from profiles where id = p_user and deleted_at is null;
  if v_old is null or not (v_old = any (v_all)) or not (p_role = any (v_all)) then
    raise exception 'only staff, admin and website roles can be changed here' using errcode = '22023';
  end if;
  -- Admins may move people between website roles; everything else is the super admin's.
  if not (public.is_super_admin() or (public.is_platform_admin() and v_old = any (v_web) and p_role = any (v_web))) then
    raise exception 'only the super admin can change this role' using errcode = '42501';
  end if;
  update profiles set role = p_role where id = p_user;
  if not (p_role in ('health_worker', 'facility_admin')) then
    update staff_assignments set active = false where staff_id = p_user;
  end if;
  insert into audit_log (actor_id, action, details)
  values (auth.uid(), 'role_change', jsonb_build_object('target', p_user, 'from', v_old, 'to', p_role));
end $$;

create or replace function public.admin_people(p_facility uuid default null)
returns table (id uuid, display_name text, email text, role public.user_role, facilities jsonb, created_at timestamptz,
               last_sign_in_at timestamptz, confirmed boolean, banned boolean, mfa boolean)
language sql stable security definer set search_path = public, auth as $$
  select p.id, p.display_name, u.email::text, p.role,
    coalesce((select jsonb_agg(jsonb_build_object('id', f.id, 'name', f.name, 'active', s.active) order by f.name)
              from staff_assignments s join facilities f on f.id = s.facility_id where s.staff_id = p.id), '[]'::jsonb),
    u.created_at, u.last_sign_in_at, u.email_confirmed_at is not null, coalesce(u.banned_until > now(), false),
    exists (select 1 from auth.mfa_factors m where m.user_id = u.id and m.status = 'verified')
  from profiles p join auth.users u on u.id = p.id
  where p.deleted_at is null
    and p.role in ('health_worker', 'facility_admin', 'programme_admin', 'super_admin', 'editor', 'author', 'clinical_reviewer', 'viewer')
    and (p_facility is null or exists (select 1 from staff_assignments s where s.staff_id = p.id and s.facility_id = p_facility))
    and (public.is_platform_admin()
         or (p.role in ('health_worker', 'facility_admin')
             and exists (select 1 from staff_assignments s where s.staff_id = p.id and public.facility_admin_of(s.facility_id))))
  order by p.role, p.display_name
$$;

-- ───────────── grants
revoke all on public.revisions, public.preview_tokens, public.site_sections, public.site_settings, public.seo_pages, public.media,
              public.partners, public.impact_kpis, public.contact_messages from anon, authenticated;
grant select on public.revisions, public.site_sections, public.site_settings, public.seo_pages, public.media, public.partners,
                public.impact_kpis, public.contact_messages to authenticated;

do $$
declare f text;
begin
  -- internal helpers: never callable from outside
  foreach f in array array[
    'public.cms_revision(text, text, jsonb, text)', 'public.cms_audit(text, text, text, jsonb)', 'public.preview_ok(uuid)',
    'public.site_bundle(boolean)', 'public.blog_check_draft(jsonb)', 'public.web_need(text)'
  ] loop
    execute format('revoke all on function %s from public, anon, authenticated', f);
  end loop;
  -- signed-in staff (each checks the role itself)
  foreach f in array array[
    'public.web_role()', 'public.web_can(text)', 'public.preview_token()',
    'public.blog_save(uuid, jsonb, timestamptz)', 'public.blog_submit(uuid)', 'public.blog_review(uuid, text, text, text)',
    'public.blog_publish(uuid)', 'public.blog_unpublish(uuid)', 'public.blog_archive(uuid, boolean)', 'public.blog_restore(uuid, bigint)',
    'public.blog_author_save(text, text, text, text)', 'public.blog_author_archive(text)',
    'public.site_sections_import(jsonb)', 'public.site_section_save(uuid, jsonb, boolean, timestamptz)',
    'public.site_sections_reorder(text, uuid[])', 'public.site_section_publish(uuid)', 'public.site_page_publish(text)',
    'public.site_section_reset(uuid)', 'public.site_section_restore(uuid, bigint)',
    'public.site_setting_save(text, jsonb, boolean)', 'public.seo_save(text, text, text, text, boolean)',
    'public.media_register(text, text, text, integer, integer, integer, text, text)', 'public.media_update(uuid, text, text)',
    'public.media_usage(text)', 'public.media_archive(uuid)',
    'public.partner_save(uuid, text, text, text, text, text, integer)', 'public.partner_confirm(uuid, boolean)',
    'public.partner_publish(uuid, boolean)', 'public.partner_archive(uuid)',
    'public.impact_save(uuid, text, numeric, text, text, boolean, integer)', 'public.impact_publish(uuid, boolean)',
    'public.impact_archive(uuid)', 'public.contact_set_status(uuid, text, text)'
  ] loop
    execute format('revoke all on function %s from public, anon', f);
    execute format('grant execute on function %s to authenticated', f);
  end loop;
  -- the public website
  foreach f in array array['public.site_public()', 'public.site_preview(uuid)', 'public.blog_preview(uuid, uuid)',
                           'public.submit_contact(text, text, text, text, text)'] loop
    execute format('revoke all on function %s from public', f);
    execute format('grant execute on function %s to anon, authenticated', f);
  end loop;
end $$;
grant execute on function public.blog_body_ok(jsonb), public.blog_text(jsonb), public.blog_needs_review(jsonb) to authenticated;
