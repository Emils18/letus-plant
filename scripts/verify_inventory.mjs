import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { pathToFileURL } from "node:url";

const { PGlite } = await import(process.argv[2] ? pathToFileURL(process.argv[2]).href : "@electric-sql/pglite");
const db = new PGlite();
const buyer="00000000-0000-4000-8000-000000000001";
const farmer="00000000-0000-4000-8000-000000000002";
const otherFarmer="00000000-0000-4000-8000-000000000003";
await db.exec(`
  create role anon;
  create role authenticated;
  create schema auth;
  create function auth.uid() returns uuid language sql stable as
    $$select nullif(current_setting('request.jwt.claim.sub', true),'')::uuid$$;
  grant usage on schema auth to public;
  create table public.users(id uuid primary key, role text);
  create table public.products(id bigint primary key, farmer_id uuid, stock integer, status text, name text, price numeric, updated_at timestamptz);
  create table public.orders(id uuid primary key default gen_random_uuid(), user_id uuid, farmer_id uuid,
    email text, status text, delivery_status text, shipping_name text, shipping_phone text, shipping_address text,
    city text, postal_code text, payment_method text, delivery_method text, payment_status text, total_amount numeric,
    confirmed_received boolean);
  create table public.order_items(order_id uuid references public.orders, product_id bigint references public.products, product_name text, price numeric, price_at_time numeric, quantity integer, subtotal numeric);
  grant select, insert, update on all tables in schema public to anon,authenticated;
  create publication supabase_realtime;
  insert into public.users values ('${buyer}','buyer'),('${farmer}','farmer'),('${otherFarmer}','farmer');
  insert into public.products values (1,'${farmer}',20,'Available','Lettuce',40,null),(2,'${otherFarmer}',10,'Available','Lettuce',60,null);
`);
const migration = readFileSync(new URL("../supabase/migrations/202611210003_manage_product_inventory.sql",import.meta.url),"utf8");
await db.exec(migration);
await db.exec(migration);
const order = async (method, items, single) => {
  const {rows} = await db.query("select public.place_marketplace_order($1::jsonb,$2::jsonb,$3) as orders",[
    JSON.stringify({shipping_name:"Buyer",shipping_phone:"555",shipping_address:"Farm road",city:"Cebu",postal_code:"6000",delivery_method:method,payment_method:"To be agreed in person",payment_status:"Paid",delivery_fee:0}),
    JSON.stringify(items), single,
  ]);
  return rows[0].orders;
};
const item=(product_id,quantity)=>({product_id,quantity,price:0});
await db.exec(`set role authenticated; set request.jwt.claim.sub = '${buyer}';`);
for (const mode of [true,false,null]) {
  const [saved] = await order("Delivery",[item(1,2)],mode);
  assert.equal(Number(saved.total_amount),130);
  assert.equal(saved.payment_status,"Unpaid");
  assert.equal(saved.payment_method,"To be agreed in person");
}
assert.equal(Number((await order("Pickup",[item(1,1)],false))[0].total_amount),40);
assert.deepEqual((await order("Delivery",[item(1,1),item(2,1)],false)).map(o=>Number(o.total_amount)).sort(),[110,90]);
await assert.rejects(order("Delivery",[item(1,1),item(2,1)],true));
const before=(await db.query("select count(*)::int as n from public.orders")).rows[0].n;
await assert.rejects(order("Delivery",[item(1,999)],false));
assert.equal((await db.query("select count(*)::int as n from public.orders")).rows[0].n,before);

const legacy=(await db.query("insert into public.orders(user_id,farmer_id,status,delivery_method,total_amount,payment_status) values ($1,$2,'Pending','Delivery',0,'Paid') returning id,payment_status",[buyer,farmer])).rows[0];
await assert.rejects(db.query("insert into public.orders(user_id,farmer_id,status,delivery_method) values ($1,$2,'Pending','No charge')",[buyer,farmer]), /Choose Delivery or Pickup/);
assert.equal(legacy.payment_status,"Unpaid");
await db.query("insert into public.order_items(order_id,product_id,quantity,price,subtotal) values ($1,1,1,0,0),($1,1,2,0,0)",[legacy.id]);
await db.query("update public.orders set total_amount=0, delivery_method='Pickup',status='Completed', payment_status='Paid' where id=$1",[legacy.id]);
const {rows:[after]}=await db.query("select total_amount,delivery_method,status,payment_status from public.orders where id=$1",[legacy.id]);
assert.equal(Number(after.total_amount),170);
assert.equal(after.delivery_method,"Delivery");
assert.equal(after.status,"Completed");
assert.equal(after.payment_status,"Paid");
const stock=(await db.query("select stock from public.products where id=1")).rows[0].stock;
await db.exec(`set request.jwt.claim.sub = '${farmer}';`);
assert.equal((await db.query("select public.restock_farmer_product(1,2) as stock")).rows[0].stock,stock+2);
assert.equal((await db.query("select public.archive_farmer_product(1) as result")).rows[0].result.has_order_history,true);
await db.exec("reset role; set role anon; set request.jwt.claim.sub = '';");
await assert.rejects(order("Delivery",[item(2,1)],true), /permission denied/);
await db.close();
console.log("Inventory SQL passed: repeat migration, trusted prices and fees, grouped and pickup orders, rollback, legacy signed-in writer, state compatibility, restock/archive and anon RPC denial.");
