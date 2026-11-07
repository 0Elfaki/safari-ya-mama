-- Website team roles for the dashboard's Website section (the Studio spec):
--   editor            writes, edits and publishes blog posts and website pages
--   author            writes their own blog drafts and submits them for review
--   clinical_reviewer approves health content (blog posts that give health advice)
--   viewer            reads the Website section only
-- Admin and super_admin already have every website power. These roles never see mothers' data.
-- Kept in its own file: a new enum value cannot be used in the transaction that adds it.
alter type public.user_role add value if not exists 'editor';
alter type public.user_role add value if not exists 'author';
alter type public.user_role add value if not exists 'clinical_reviewer';
alter type public.user_role add value if not exists 'viewer';
