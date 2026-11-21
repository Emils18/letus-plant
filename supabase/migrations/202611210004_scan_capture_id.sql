-- A client uses the same capture ID when retrying a save after a network error.
alter table public.diagnostic_logs
  add column if not exists scan_capture_id uuid;

create unique index if not exists diagnostic_logs_scan_capture_unique
  on public.diagnostic_logs (user_id, scan_capture_id);
