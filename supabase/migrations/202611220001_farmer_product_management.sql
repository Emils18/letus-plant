-- Apply only after review/approval. These routines preserve product IDs and all order rows.
alter table public.products add column if not exists archived_at timestamptz;

drop policy if exists "Farmers update their own products" on public.products;
create policy "Farmers update their own products" on public.products
for update to authenticated
using (farmer_id = auth.uid() and archived_at is null
  and exists (select 1 from public.users u where u.id = auth.uid() and lower(u.role::text) = 'farmer'))
with check (farmer_id = auth.uid() and archived_at is null
  and exists (select 1 from public.users u where u.id = auth.uid() and lower(u.role::text) = 'farmer'));

drop policy if exists "Farmers delete their own products" on public.products;

create or replace function public.restock_farmer_product(p_product_id bigint, p_quantity integer)
returns integer language plpgsql security invoker set search_path = '' as $$
declare new_stock integer;
begin
  if p_quantity is null or p_quantity < 1 then
    raise exception 'Enter a positive whole number.' using errcode = '22023';
  end if;
  update public.products p set stock = coalesce(p.stock, 0) + p_quantity,
    status = 'Available', updated_at = now()
  where p.id = p_product_id and p.farmer_id = auth.uid() and p.archived_at is null
    and exists (select 1 from public.users u where u.id = auth.uid() and lower(u.role::text) = 'farmer')
  returning p.stock into new_stock;
  if not found then raise exception 'Listing not available to manage.' using errcode = 'P0002'; end if;
  return new_stock;
end; $$;

create or replace function public.archive_farmer_product(p_product_id bigint)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare has_history boolean;
begin
  if not exists (select 1 from public.products p join public.users u on u.id = auth.uid()
    where p.id = p_product_id and p.farmer_id = auth.uid() and p.archived_at is null
      and lower(u.role::text) = 'farmer' for update of p) then
    raise exception 'Listing not available to manage.' using errcode = 'P0002';
  end if;
  select exists(select 1 from public.order_items oi where oi.product_id = p_product_id) into has_history;
  update public.products set archived_at = now(), stock = 0, status = 'Out of Stock', updated_at = now()
    where id = p_product_id and farmer_id = auth.uid();
  return jsonb_build_object('has_order_history', has_history);
end; $$;

revoke all on function public.restock_farmer_product(bigint, integer) from public, anon;
grant execute on function public.restock_farmer_product(bigint, integer) to authenticated;
revoke all on function public.archive_farmer_product(bigint) from public, anon;
grant execute on function public.archive_farmer_product(bigint) to authenticated;
