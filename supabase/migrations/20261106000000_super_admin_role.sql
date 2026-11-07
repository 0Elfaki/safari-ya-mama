-- New role for the dashboard: super_admin (full control, including facilities and admin accounts).
-- An enum value cannot be used in the transaction that adds it, so this file only adds it;
-- 20261106000100_roles_permissions.sql uses it.
alter type public.user_role add value if not exists 'super_admin';
