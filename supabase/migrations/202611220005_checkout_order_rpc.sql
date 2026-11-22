-- Checkout-only installation of the atomic marketplace order RPC and stock reservation trigger.
-- This is split out so deploying checkout does not require unrelated farmer inventory policies.

begin;

-- Apply checkout stock changes in the same statement as the order items.
-- The product row lock prevents checkout, archive, and restock from overwriting one another.
create or replace function public.take_stock_for_order_item()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  order_farmer_id uuid;
begin
  select o.farmer_id into order_farmer_id from public.orders o
  where o.id = new.order_id and o.user_id = auth.uid() and lower(o.status::text) = 'pending';

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
    and p.stock >= new.quantity;

  if not found then
    raise exception 'Some products are no longer available in the requested quantity.' using errcode = '22023';
  end if;
  return new;
end;
$$;

revoke all on function public.take_stock_for_order_item() from public, anon, authenticated;

drop trigger if exists greenguard_reserve_order_item_stock on public.order_items;
create trigger greenguard_reserve_order_item_stock
after insert on public.order_items
for each row execute function public.take_stock_for_order_item();

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
      payment_method_value, delivery_method_value, payment_method_value,
      sum(line.price * line.quantity) + case when p_single_farmer and delivery_method_value = 'Delivery' then 50 else 0 end,
      false
    from jsonb_to_recordset(order_lines) as line(farmer_id uuid, price numeric, quantity integer)
    where line.farmer_id = farmer
    returning * into placed_order;

    insert into public.order_items (order_id, product_id, product_name, price, price_at_time, quantity, subtotal)
    select placed_order.id, line.product_id, line.name, line.price, line.price, line.quantity, line.price * line.quantity
    from jsonb_to_recordset(order_lines) as line(product_id bigint, farmer_id uuid, name text, price numeric, quantity integer)
    where line.farmer_id = farmer
    order by line.product_id;

    placed_orders := placed_orders || jsonb_build_array(to_jsonb(placed_order));
  end loop;
  return placed_orders;
end;
$$;

revoke all on function public.place_marketplace_order(jsonb, jsonb, boolean) from public, anon;
grant execute on function public.place_marketplace_order(jsonb, jsonb, boolean) to authenticated;

notify pgrst, 'reload schema';
commit;
