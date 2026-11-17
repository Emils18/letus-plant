CREATE UNIQUE INDEX IF NOT EXISTS users_email_unique     ON public.users (LOWER(email));
CREATE UNIQUE INDEX IF NOT EXISTS users_full_name_unique ON public.users (LOWER(full_name));
