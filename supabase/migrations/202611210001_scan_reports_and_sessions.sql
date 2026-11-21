-- Additive report snapshots and session summaries used by the web scan flow.
-- Existing Mobile tables and stored records are preserved.

create table if not exists public.scan_sessions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  started_at timestamptz not null default now(),
  completed_at timestamptz,
  total_scanned integer not null default 0,
  healthy_count integer not null default 0,
  not_healthy_count integer not null default 0,
  downy_mildew_count integer not null default 0,
  powdery_mildew_count integer not null default 0,
  septoria_blight_count integer not null default 0,
  healthy_percentage numeric(6,2) not null default 0,
  not_healthy_percentage numeric(6,2) not null default 0,
  healthy_avg_confidence numeric(8,6) not null default 0,
  downy_avg_confidence numeric(8,6) not null default 0,
  powdery_avg_confidence numeric(8,6) not null default 0,
  septoria_avg_confidence numeric(8,6) not null default 0,
  status text not null default 'active'
);

alter table public.scan_sessions
  add column if not exists user_id uuid references auth.users(id) on delete cascade,
  add column if not exists started_at timestamptz not null default now(),
  add column if not exists completed_at timestamptz,
  add column if not exists total_scanned integer not null default 0,
  add column if not exists healthy_count integer not null default 0,
  add column if not exists not_healthy_count integer not null default 0,
  add column if not exists downy_mildew_count integer not null default 0,
  add column if not exists powdery_mildew_count integer not null default 0,
  add column if not exists septoria_blight_count integer not null default 0,
  add column if not exists healthy_percentage numeric(6,2) not null default 0,
  add column if not exists not_healthy_percentage numeric(6,2) not null default 0,
  add column if not exists healthy_avg_confidence numeric(8,6) not null default 0,
  add column if not exists downy_avg_confidence numeric(8,6) not null default 0,
  add column if not exists powdery_avg_confidence numeric(8,6) not null default 0,
  add column if not exists septoria_avg_confidence numeric(8,6) not null default 0,
  add column if not exists status text not null default 'active';

alter table public.diagnostic_logs
  add column if not exists scan_session_id uuid,
  add column if not exists pathogen_name text,
  add column if not exists disease_description text,
  add column if not exists pathogen_description text,
  add column if not exists treatment_recommendations jsonb,
  add column if not exists selling_recommendation text,
  add column if not exists selling_explanation text;

create index if not exists scan_sessions_user_started_idx
  on public.scan_sessions (user_id, started_at desc);

create index if not exists diagnostic_logs_scan_session_idx
  on public.diagnostic_logs (scan_session_id);

alter table public.scan_sessions enable row level security;

drop policy if exists "Farmers read their own scan sessions"
  on public.scan_sessions;
create policy "Farmers read their own scan sessions"
  on public.scan_sessions for select to authenticated
  using (user_id = auth.uid());

drop policy if exists "Farmers create their own scan sessions"
  on public.scan_sessions;
create policy "Farmers create their own scan sessions"
  on public.scan_sessions for insert to authenticated
  with check (user_id = auth.uid());

drop policy if exists "Farmers update their own scan sessions"
  on public.scan_sessions;
create policy "Farmers update their own scan sessions"
  on public.scan_sessions for update to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

grant select, insert, update on public.scan_sessions to authenticated;
