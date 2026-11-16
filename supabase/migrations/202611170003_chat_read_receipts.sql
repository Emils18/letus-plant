alter table public.order_messages
  add column if not exists read_at timestamptz;

drop policy if exists "Chat recipients can mark messages seen"
  on public.order_messages;

create policy "Chat recipients can mark messages seen"
  on public.order_messages
  for update
  to authenticated
  using (
    sender_id <> auth.uid()
    and read_at is null
    and exists (
      select 1
      from public.orders o
      where o.id::text = order_messages.order_id
        and (o.user_id = auth.uid() or o.farmer_id = auth.uid())
    )
  )
  with check (
    sender_id <> auth.uid()
    and read_at is not null
    and exists (
      select 1
      from public.orders o
      where o.id::text = order_messages.order_id
        and (o.user_id = auth.uid() or o.farmer_id = auth.uid())
    )
  );

grant update (read_at) on public.order_messages to authenticated;
