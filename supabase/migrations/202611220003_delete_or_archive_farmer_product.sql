-- Apply manually in Supabase SQL Editor. This does not touch orders, payments,
-- messages, health records, or rows belonging to another farmer.
alter table public.products
  add column if not exists archived_at timestamptz;

-- Keep the existing archive RPC available to already released clients.
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

  select lower(u.role::text) into v_role
  from public.users u where u.id = v_user_id;
  if v_role is distinct from 'farmer' then
    raise exception 'Only a farmer can archive a listing.' using errcode = '42501';
  end if;

  perform 1 from public.products p
  where p.id = p_product_id and p.farmer_id = v_user_id
  for update;
  if not found then
    raise exception 'Listing not found or not owned by this farmer.' using errcode = 'P0002';
  end if;

  select exists (
    select 1 from public.order_items oi where oi.product_id = p_product_id
  ) into v_has_order_history;

  update public.products p
  set archived_at = now(), stock = 0, status = 'Out of Stock', updated_at = now()
  where p.id = p_product_id and p.farmer_id = v_user_id and p.archived_at is null;

  return jsonb_build_object('has_order_history', v_has_order_history);
end;
$function$;

-- Permanently remove only an unreferenced listing. Keep referenced listings archived.
-- Other restrictive foreign keys also fall back to archival without deleting child rows.
create or replace function public.delete_farmer_product(p_product_id bigint)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_user_id uuid := auth.uid();
  v_role text;
  v_has_order_history boolean;
  v_image text;
  v_image_url text;
  v_image_cleanup_safe boolean := false;
  v_has_other_references boolean := false;
  v_fk record;
begin
  if v_user_id is null then
    raise exception 'Authentication is required.' using errcode = '28000';
  end if;

  select lower(u.role::text) into v_role
  from public.users u where u.id = v_user_id;
  if v_role is distinct from 'farmer' then
    raise exception 'Only a farmer can delete a listing.' using errcode = '42501';
  end if;

  perform 1 from public.products p
  where p.id = p_product_id and p.farmer_id = v_user_id
  for update;
  if not found then
    raise exception 'Listing not found or not owned by this farmer.' using errcode = 'P0002';
  end if;

  select exists (
    select 1 from public.order_items oi where oi.product_id = p_product_id
  ) into v_has_order_history;

  if v_has_order_history then
    update public.products p
    set archived_at = coalesce(p.archived_at, now()), stock = 0, status = 'Out of Stock', updated_at = now()
    where p.id = p_product_id and p.farmer_id = v_user_id;
    return jsonb_build_object(
      'action', 'archived', 'has_order_history', true, 'image_cleanup_safe', false
    );
  end if;

  -- Avoid cascading deletion of any dependent record. Products with any FK references
  -- outside order history are archived instead; no child rows are deleted.
  for v_fk in
    select child_ns.nspname as schema_name,
           child.relname as table_name,
           (
             select pg_catalog.string_agg(
               pg_catalog.format('c.%I = p.%I', child_column.attname, parent_column.attname),
               ' AND ' order by child_key.ordinality
             )
             from pg_catalog.unnest(fk.conkey) with ordinality as child_key(attnum, ordinality)
             join pg_catalog.pg_attribute child_column
               on child_column.attrelid = fk.conrelid
              and child_column.attnum = child_key.attnum
             join pg_catalog.unnest(fk.confkey) with ordinality as parent_key(attnum, ordinality)
               on parent_key.ordinality = child_key.ordinality
             join pg_catalog.pg_attribute parent_column
               on parent_column.attrelid = fk.confrelid
              and parent_column.attnum = parent_key.attnum
           ) as reference_predicate
    from pg_catalog.pg_constraint fk
    join pg_catalog.pg_class child on child.oid = fk.conrelid
    join pg_catalog.pg_namespace child_ns on child_ns.oid = child.relnamespace
    where fk.contype = 'f'
      and fk.confrelid = 'public.products'::regclass
  loop
    execute pg_catalog.format(
      'select exists (select 1 from %I.%I c where exists (select 1 from public.products p where p.id = $1 and %s))',
      v_fk.schema_name,
      v_fk.table_name,
      v_fk.reference_predicate
    ) into v_has_other_references using p_product_id;
    if v_has_other_references then
      exit;
    end if;
  end loop;

  if v_has_other_references then
    update public.products p
    set archived_at = coalesce(p.archived_at, now()), stock = 0, status = 'Out of Stock', updated_at = now()
    where p.id = p_product_id and p.farmer_id = v_user_id;
    return jsonb_build_object(
      'action', 'archived', 'has_order_history', false,
      'blocked_by_reference', true, 'image_cleanup_safe', false
    );
  end if;

  select p.image, p.image_url into v_image, v_image_url
  from public.products p where p.id = p_product_id;

  select not exists (
    select 1
    from public.products other
    cross join lateral (values (v_image), (v_image_url)) as target_image(url)
    cross join lateral (values (other.image), (other.image_url)) as referenced_image(url)
    where other.id <> p_product_id
      and target_image.url is not null
      and referenced_image.url is not null
      and (case
        when pg_catalog.strpos(target_image.url, '/storage/v1/object/public/products/') > 0
          then pg_catalog.split_part(
            pg_catalog.split_part(target_image.url, '/storage/v1/object/public/products/', 2),
            '?', 1
          )
        else target_image.url
      end) = (case
        when pg_catalog.strpos(referenced_image.url, '/storage/v1/object/public/products/') > 0
          then pg_catalog.split_part(
            pg_catalog.split_part(referenced_image.url, '/storage/v1/object/public/products/', 2),
            '?', 1
          )
        else referenced_image.url
      end)
  ) into v_image_cleanup_safe;

  begin
    delete from public.products p
    where p.id = p_product_id and p.farmer_id = v_user_id;
    if not found then
      raise exception 'Listing could not be deleted.' using errcode = 'P0002';
    end if;
  exception when foreign_key_violation then
    update public.products p
    set archived_at = coalesce(p.archived_at, now()), stock = 0, status = 'Out of Stock', updated_at = now()
    where p.id = p_product_id and p.farmer_id = v_user_id;
    return jsonb_build_object(
      'action', 'archived', 'has_order_history', false,
      'blocked_by_reference', true, 'image_cleanup_safe', false
    );
  end;

  return jsonb_build_object(
    'action', 'deleted', 'has_order_history', false,
    'image_cleanup_safe', v_image_cleanup_safe
  );
end;
$function$;

revoke all on function public.archive_farmer_product(bigint) from public, anon;
grant execute on function public.archive_farmer_product(bigint) to authenticated;
revoke all on function public.restock_farmer_product(bigint, integer) from public, anon;
grant execute on function public.restock_farmer_product(bigint, integer) to authenticated;
revoke all on function public.delete_farmer_product(bigint) from public, anon;
grant execute on function public.delete_farmer_product(bigint) to authenticated;

notify pgrst, 'reload schema';
