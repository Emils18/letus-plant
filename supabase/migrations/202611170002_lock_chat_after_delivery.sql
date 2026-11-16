drop policy if exists "Order participants can send chat"
  on public.order_messages;

create policy "Order participants can send chat"
  on public.order_messages
  for insert
  to authenticated
  with check (
    sender_id = auth.uid()
    and exists (
      select 1
      from public.orders o
      where o.id::text = order_messages.order_id
        and (o.user_id = auth.uid() or o.farmer_id = auth.uid())
        and lower(coalesce(o.status, '')) not in ('delivered', 'received', 'completed')
        and lower(coalesce(o.delivery_status, '')) not in ('delivered', 'received', 'completed')
    )
  );
