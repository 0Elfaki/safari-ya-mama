-- Covering indexes for the website CMS foreign keys (performance advisor: unindexed_foreign_keys).
create index if not exists blog_posts_author_idx on public.blog_posts (author_id);
create index if not exists blog_posts_created_by_idx on public.blog_posts (created_by);
create index if not exists blog_posts_draft_updated_by_idx on public.blog_posts (draft_updated_by);
create index if not exists media_created_by_idx on public.media (created_by);
create index if not exists partners_confirmed_by_idx on public.partners (confirmed_by);
create index if not exists partners_updated_by_idx on public.partners (updated_by);
create index if not exists preview_tokens_created_by_idx on public.preview_tokens (created_by);
create index if not exists revisions_author_idx on public.revisions (author);
create index if not exists seo_pages_updated_by_idx on public.seo_pages (updated_by);
create index if not exists site_sections_updated_by_idx on public.site_sections (updated_by);
create index if not exists site_settings_updated_by_idx on public.site_settings (updated_by);
create index if not exists impact_kpis_updated_by_idx on public.impact_kpis (updated_by);
