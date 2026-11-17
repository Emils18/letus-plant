-- Names may be reused after an account is permanently deleted.
-- Keep only the case-insensitive unique email index.
DROP INDEX IF EXISTS public.users_full_name_unique;
