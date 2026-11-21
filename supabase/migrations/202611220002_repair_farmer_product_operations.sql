-- Apply manually after reviewing the read-only production preflight queries provided with this change.
-- Safe for existing product and order data: this only adds a nullable archive marker,
-- replaces two RPC bodies with the signatures already used by the clients, and resets
-- the farmer-owned product UPDATE policy. It never deletes a product or order row.

alter table public.products
  add column if not exists archived_at timestamptz;

update public.products p
  set status = case
    when p.stock > 0 then 'Available'
    else 'Out of Stock'
  end
  where p.archived_at is null
    and p.status is distinct from case
      when p.stock > 0 then 'Available'
      else 'Out of Stock'
    end;

drop policy if exists "Farmers update their own products" on public.products;
create policy "Farmers update their own products" on public.products
  for update to authenticated
  using (
    farmer_id = auth.uid()
    and archived_at is null
    and exists (
      select 1
      from public.users u
      where u.id = auth.uid()
        and lower(u.role::text) = 'farmer'
    )
  )
  with check (
    farmer_id = auth.uid()
    and archived_at is null
    and exists (
      select 1
      from public.users u
      where u.id = auth.uid()
        and lower(u.role::text) = 'farmer'
    )
  );

create or replace function public.restock_farmer_product(
  p_product_id bigint,
  p_quantity integer
)
returns integer
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_user_id uuid := auth.uid();
  v_role text;
  v_stock integer;
begin
  if v_user_id is null then
    raise exception 'Authentication is required.' using errcode = '28000';
  end if;
  if p_quantity is null or p_quantity < 1 then
    raise exception 'Restock quantity must be a positive whole number.' using errcode = '22023';
  end if;

  select lower(u.role::text)
    into v_role
    from public.users u
    where u.id = v_user_id;
  if v_role is distinct from 'farmer' then
    raise exception 'Only the owning farmer can restock this listing.' using errcode = '42501';
  end if;

  perform 1
    from public.products p
    where p.id = p_product_id
      and p.farmer_id = v_user_id
      and p.archived_at is null
    for update;
  if not found then
    raise exception 'Listing not found or no longer available to manage.' using errcode = 'P0002';
  end if;

  update public.products p
    set stock = coalesce(p.stock, 0) + p_quantity,
        status = 'Available',
        updated_at = now()
    where p.id = p_product_id
      and p.farmer_id = v_user_id
      and p.archived_at is null
    returning p.stock into v_stock;

  return v_stock;
end;
$function$;

create or replace function public.archive_farmer_product(p_product_id bigint)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_user_id uuid := auth.uid();
  v_role text;
  v_has_order_history boolean;
begin
  if v_user_id is null then
    raise exception 'Authentication is required.' using errcode = '28000';
  end if;

  select lower(u.role::text)
    into v_role
    from public.users u
    where u.id = v_user_id;
  if v_role is distinct from 'farmer' then
    raise exception 'Only the owning farmer can unlist this listing.' using errcode = '42501';
  end if;

  perform 1
    from public.products p
    where p.id = p_product_id
      and p.farmer_id = v_user_id
      and p.archived_at is null
    for update;
  if not found then
    raise exception 'Listing not found or no longer available to manage.' using errcode = 'P0002';
  end if;

  select exists (
    select 1
      from public.order_items oi
      where oi.product_id = p_product_id
  ) into v_has_order_history;

  update public.products p
    set archived_at = now(),
        stock = 0,
        status = 'Out of Stock',
        updated_at = now()
    where p.id = p_product_id
      and p.farmer_id = v_user_id
      and p.archived_at is null;

  return jsonb_build_object('has_order_history', v_has_order_history);
end;
$function$;

revoke all on function public.restock_farmer_product(bigint, integer) from public, anon;
grant execute on function public.restock_farmer_product(bigint, integer) to authenticated;
revoke all on function public.archive_farmer_product(bigint) from public, anon;
grant execute on function public.archive_farmer_product(bigint) to authenticated;

notify pgrst, 'reload schema';
