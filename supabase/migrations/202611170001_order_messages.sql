create table if not exists public.order_messages (
  id uuid primary key default gen_random_uuid(),
  order_id text not null,
  sender_id uuid not null references auth.users(id) on delete cascade,
  message text not null check (length(btrim(message)) > 0),
  created_at timestamptz not null default now()
);

create index if not exists order_messages_order_created_idx
  on public.order_messages (order_id, created_at);

alter table public.order_messages enable row level security;

drop policy if exists "Order participants can read chat" on public.order_messages;
create policy "Order participants can read chat"
  on public.order_messages for select to authenticated
  using (
    exists (
      select 1 from public.orders o
      where o.id::text = order_messages.order_id
        and (o.user_id = auth.uid() or o.farmer_id = auth.uid())
    )
  );

drop policy if exists "Order participants can send chat" on public.order_messages;
create policy "Order participants can send chat"
  on public.order_messages for insert to authenticated
  with check (
    sender_id = auth.uid()
    and exists (
      select 1 from public.orders o
      where o.id::text = order_messages.order_id
        and (o.user_id = auth.uid() or o.farmer_id = auth.uid())
        and lower(coalesce(o.status, '')) not in ('delivered', 'received', 'completed')
        and lower(coalesce(o.delivery_status, '')) not in ('delivered', 'received', 'completed')
    )
  );

grant select, insert on public.order_messages to authenticated;

do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'order_messages'
  ) then
    alter publication supabase_realtime add table public.order_messages;
  end if;
end
$$;
