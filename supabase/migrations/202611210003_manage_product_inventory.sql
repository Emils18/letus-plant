alter table public.products add column if not exists archived_at timestamptz;
alter table public.products enable row level security;

drop policy if exists "Marketplace can read listings" on public.products;
create policy "Marketplace can read listings"
  on public.products for select to anon, authenticated
  using (true);

drop policy if exists "Farmers create their own products" on public.products;
create policy "Farmers create their own products"
  on public.products for insert to authenticated
  with check (
    farmer_id = (select auth.uid())
    and archived_at is null
    and exists (select from public.users u where u.id = (select auth.uid()) and lower(u.role::text) = 'farmer')
  );

-- Management removes listings from sale while retaining product IDs used by orders.
drop policy if exists "Farmers delete their own products" on public.products;

drop policy if exists "Farmers update their own products" on public.products;
create policy "Farmers update their own products"
  on public.products for update to authenticated
  using (
    farmer_id = (select auth.uid())
    and archived_at is null
    and exists (select from public.users u where u.id = (select auth.uid()) and lower(u.role::text) = 'farmer')
  )
  with check (
    farmer_id = (select auth.uid())
    and archived_at is null
    and exists (select from public.users u where u.id = (select auth.uid()) and lower(u.role::text) = 'farmer')
  );

create or replace function public.restock_farmer_product(p_product_id bigint, p_quantity integer)
returns integer
language plpgsql
security invoker
set search_path = ''
as $$
declare
  new_stock integer;
begin
  if p_quantity is null or p_quantity < 1 then
    raise exception 'Enter a positive whole number.' using errcode = '22023';
  end if;

  -- Relative stock updates are serialized by PostgreSQL's row lock.
  update public.products p
  set stock = coalesce(p.stock, 0) + p_quantity,
      status = 'Available',
      updated_at = now()
  where p.id = p_product_id
    and p.farmer_id = auth.uid()
    and p.archived_at is null
    and exists (select from public.users u where u.id = auth.uid() and lower(u.role::text) = 'farmer')
  returning p.stock into new_stock;

  if not found then
    raise exception 'This listing is no longer available to manage.' using errcode = 'P0002';
  end if;

  return new_stock;
exception when numeric_value_out_of_range then
  raise exception 'The resulting stock quantity is too large.' using errcode = '22023';
end;
$$;

create or replace function public.archive_farmer_product(p_product_id bigint)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  owner_id uuid := auth.uid();
  has_order_history boolean;
begin
  -- Access the product only after checking ownership and role inside this function.
  perform 1 from public.products p
  where p.id = p_product_id and p.farmer_id = owner_id and p.archived_at is null
    and exists (select from public.users u where u.id = owner_id and lower(u.role::text) = 'farmer')
  for update;
  if not found then
    raise exception 'This listing is no longer available to manage.' using errcode = 'P0002';
  end if;

  -- This includes both current and historical orders. Keep every reference, even for listings with no orders yet.
  select exists (select from public.order_items oi where oi.product_id = p_product_id) into has_order_history;
  update public.products p
  set archived_at = now(), stock = 0, status = 'Out of Stock', updated_at = now()
  where p.id = p_product_id and p.farmer_id = owner_id;

  return jsonb_build_object('has_order_history', has_order_history);
end;
$$;

revoke all on function public.restock_farmer_product(bigint, integer) from public, anon;
revoke all on function public.archive_farmer_product(bigint) from public, anon;
grant execute on function public.restock_farmer_product(bigint, integer) to authenticated;
grant execute on function public.archive_farmer_product(bigint) to authenticated;

-- Canonical delivery charges are shared by RPC checkout and older signed-in clients.
create or replace function public.marketplace_delivery_fee(delivery_method text)
returns integer
language sql
immutable
set search_path = ''
as $$
  select case when lower(btrim(delivery_method)) = 'delivery' then 50 else 0 end;
$$;

create or replace function public.protect_marketplace_order_charge()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if tg_op = 'INSERT' then
    new.delivery_method := case lower(btrim(new.delivery_method))
      when 'delivery' then 'Delivery'
      when 'pickup' then 'Pickup'
      else null
    end;
    if new.delivery_method is null then
      raise exception 'Choose Delivery or Pickup.' using errcode = '22023';
    end if;
    new.total_amount := public.marketplace_delivery_fee(new.delivery_method);
    new.payment_status := 'Unpaid';
  elsif pg_trigger_depth() = 1 then
    -- The line trigger updates the total. Ordinary lifecycle updates keep the charge.
    new.total_amount := old.total_amount;
    new.delivery_method := old.delivery_method;
  end if;
  return new;
end;
$$;

drop trigger if exists greenguard_protect_order_charge on public.orders;
create trigger greenguard_protect_order_charge
before insert or update on public.orders
for each row execute function public.protect_marketplace_order_charge();

create or replace function public.take_stock_for_order_item()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  order_farmer_id uuid;
  item_price numeric;
  item_name text;
begin
  select o.farmer_id into order_farmer_id from public.orders o
  where o.id = new.order_id and o.user_id = auth.uid() and lower(o.status::text) = 'pending'
  for update;

  if order_farmer_id is null or new.quantity is null or new.quantity < 1 then
    raise exception 'This order cannot reserve stock.' using errcode = '22023';
  end if;

  update public.products p
  set stock = p.stock - new.quantity,
      status = case when p.stock = new.quantity then 'Out of Stock' else 'Available' end,
      updated_at = now()
  where p.id = new.product_id
    and p.farmer_id = order_farmer_id
    and p.archived_at is null
    and p.stock >= new.quantity
    and p.price > 0
  returning p.price, p.name into item_price, item_name;

  if not found then
    raise exception 'Some products are no longer available in the requested quantity.' using errcode = '22023';
  end if;
  new.price := item_price;
  new.price_at_time := item_price;
  new.product_name := item_name;
  new.subtotal := item_price * new.quantity;
  return new;
end;
$$;

create or replace function public.refresh_marketplace_order_charge()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  -- The stock trigger locked the parent order before the item insert.
  update public.orders o
  set total_amount = (
    select coalesce(sum(oi.subtotal), 0) from public.order_items oi where oi.order_id = o.id
  ) + public.marketplace_delivery_fee(o.delivery_method)
  where o.id = new.order_id;
  return new;
end;
$$;

revoke all on function public.take_stock_for_order_item() from public, anon, authenticated;
revoke all on function public.refresh_marketplace_order_charge() from public, anon, authenticated;

drop trigger if exists greenguard_reserve_order_item_stock on public.order_items;
create trigger greenguard_reserve_order_item_stock
before insert on public.order_items
for each row execute function public.take_stock_for_order_item();

drop trigger if exists greenguard_refresh_order_charge on public.order_items;
create trigger greenguard_refresh_order_charge
after insert on public.order_items
for each row execute function public.refresh_marketplace_order_charge();

-- A checkout creates both the headers and their lines in one transaction. It also
-- keeps the established mobile grouping by farmer and the web one-farmer checkout.
create or replace function public.place_marketplace_order(
  p_contact jsonb,
  p_items jsonb,
  p_single_farmer boolean
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  buyer_id uuid := auth.uid();
  delivery_method_value text := p_contact->>'delivery_method';
  payment_method_value text := coalesce(nullif(btrim(p_contact->>'payment_method'), ''), 'To be agreed in person');
  requested_count integer;
  order_lines jsonb;
  farmers uuid[];
  farmer uuid;
  placed_order public.orders%rowtype;
  placed_orders jsonb := '[]'::jsonb;
begin
  if buyer_id is null or not exists (
    select from public.users u where u.id = buyer_id and lower(u.role::text) = 'buyer'
  ) then
    raise exception 'Sign in with a buyer account to place an order.' using errcode = '42501';
  end if;

  if delivery_method_value is null or delivery_method_value not in ('Delivery', 'Pickup')
    or coalesce(btrim(p_contact->>'shipping_name'), '') = ''
    or coalesce(btrim(p_contact->>'shipping_phone'), '') = ''
    or (delivery_method_value = 'Delivery' and (
      coalesce(btrim(p_contact->>'shipping_address'), '') = ''
      or coalesce(btrim(p_contact->>'city'), '') = ''
      or coalesce(btrim(p_contact->>'postal_code'), '') = ''
    )) then
    raise exception 'Fill in your contact and delivery details.' using errcode = '22023';
  end if;

  if jsonb_typeof(p_items) is distinct from 'array' then
    raise exception 'Your cart is empty.' using errcode = '22023';
  end if;
  if jsonb_array_length(p_items) = 0 or exists (
    select from jsonb_to_recordset(p_items) as item(product_id bigint, quantity integer)
    where item.product_id is null or item.product_id < 1 or item.quantity is null or item.quantity < 1
  ) then
    raise exception 'Check the products and quantities in your cart.' using errcode = '22023';
  end if;

  select count(distinct item.product_id) into requested_count
  from jsonb_to_recordset(p_items) as item(product_id bigint, quantity integer);

  -- Lock all requested products in ID order and use current database prices and stock.
  select jsonb_agg(to_jsonb(line)) into order_lines
  from (
    select p.id as product_id, p.farmer_id, p.name, p.price, requested.quantity
    from (
      select item.product_id, sum(item.quantity) as quantity
      from jsonb_to_recordset(p_items) as item(product_id bigint, quantity integer)
      group by item.product_id
    ) requested
    join public.products p on p.id = requested.product_id
    where p.archived_at is null and p.farmer_id is not null and p.price > 0 and p.stock >= requested.quantity
    order by p.id
    for update of p
  ) line;

  if coalesce(jsonb_array_length(order_lines), 0) <> requested_count then
    raise exception 'Some products are no longer available in the requested quantity.' using errcode = '22023';
  end if;

  select array_agg(distinct line.farmer_id) into farmers
  from jsonb_to_recordset(order_lines) as line(farmer_id uuid);
  if p_single_farmer and cardinality(farmers) > 1 then
    raise exception 'Please checkout products from one farmer at a time.' using errcode = '22023';
  end if;

  foreach farmer in array farmers loop
    insert into public.orders (
      user_id, farmer_id, email, status, delivery_status, shipping_name, shipping_phone,
      shipping_address, city, postal_code, payment_method, delivery_method, payment_status,
      total_amount, confirmed_received
    )
    select buyer_id, farmer, nullif(btrim(p_contact->>'email'), ''), 'Pending', 'Pending',
      btrim(p_contact->>'shipping_name'), btrim(p_contact->>'shipping_phone'),
      case when delivery_method_value = 'Pickup' then 'Farm Pickup' else btrim(p_contact->>'shipping_address') end,
      case when delivery_method_value = 'Pickup' then 'Farm Pickup' else btrim(p_contact->>'city') end,
      case when delivery_method_value = 'Pickup' then '0000' else btrim(p_contact->>'postal_code') end,
      payment_method_value, delivery_method_value, 'Unpaid',
      sum(line.price * line.quantity) + public.marketplace_delivery_fee(delivery_method_value),
      false
    from jsonb_to_recordset(order_lines) as line(farmer_id uuid, price numeric, quantity integer)
    where line.farmer_id = farmer
    returning * into placed_order;

    insert into public.order_items (order_id, product_id, product_name, price, price_at_time, quantity, subtotal)
    select placed_order.id, line.product_id, line.name, line.price, line.price, line.quantity, line.price * line.quantity
    from jsonb_to_recordset(order_lines) as line(product_id bigint, farmer_id uuid, name text, price numeric, quantity integer)
    where line.farmer_id = farmer
    order by line.product_id;

    select * into placed_order from public.orders o where o.id = placed_order.id;
    placed_orders := placed_orders || jsonb_build_array(to_jsonb(placed_order));
  end loop;
  return placed_orders;
end;
$$;

revoke all on function public.place_marketplace_order(jsonb, jsonb, boolean) from public, anon;
grant execute on function public.place_marketplace_order(jsonb, jsonb, boolean) to authenticated;

do $$
begin
  if exists (select from pg_publication where pubname = 'supabase_realtime' and not puballtables)
    and not exists (select from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'products') then
    alter publication supabase_realtime add table public.products;
  end if;
end;
$$;
