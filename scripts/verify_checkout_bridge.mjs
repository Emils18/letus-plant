import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { createServer } from "node:http";

let phase = "legacy";
let directOrders = 0;
const fixture = createServer(async (request, reply) => {
  const url = new URL(request.url, "http://localhost");
  const body = JSON.parse((await Array.fromAsync(request)).map(x=>x.toString()).join("") || "null");
  const send = (code, value) => {
    reply.writeHead(code, {"Content-Type":"application/json"});
    reply.end(JSON.stringify(value));
  };
  assert.equal(request.headers.authorization, "Bearer integration-test-token");
  if (url.pathname === "/auth/v1/user") return send(200,{id:"buyer-id",user_metadata:{}});
  if (url.pathname === "/rest/v1/users") return send(200,[{role:"buyer"}]);
  if (url.pathname.endsWith("/rpc/place_marketplace_order")) {
    if (phase === "legacy") return send(404,{code:"PGRST202",message:"Could not find place_marketplace_order in the schema cache"});
    if (phase === "rejected") return send(400,{code:"22023",message:"Insufficient stock"});
    assert.equal(body.p_contact.delivery_method,"Delivery");
    assert.deepEqual(body.p_items,[{product_id:1,quantity:2}]);
    return send(200,[{id:"rpc-order",farmer_id:"farmer-id",total_amount:130,payment_status:"Unpaid"}]);
  }
  if (url.pathname === "/rest/v1/products" && request.method === "GET") {
    if (url.searchParams.get("select") === "archived_at")
      return send(400,{code:"42703",message:"column products.archived_at does not exist"});
    return send(200,[{id:1,name:"Lettuce",price:40,stock:10,farmer_id:"farmer-id"}]);
  }
  if (url.pathname === "/rest/v1/orders") {
    directOrders++;
    assert.equal(body[0].total_amount,130);
    assert.equal(body[0].payment_status,"Unpaid");
    assert.equal(body[0].user_id,"buyer-id");
    return send(201,{id:"legacy-order",...body[0]});
  }
  if (url.pathname === "/rest/v1/order_items") {
    assert.equal(body[0].price,40);
    return send(201,[]);
  }
  if (url.pathname === "/rest/v1/products" && request.method === "PATCH") {
    assert.equal(body.stock,8);
    return send(200,[]);
  }
  if (url.pathname === "/rest/v1/notifications") return send(201,[]);
  return send(500,{message:"Unhandled fixture request"});
});
await new Promise(resolve=>fixture.listen(0,"127.0.0.1",resolve));
const appPort=3186;
const next=spawn(process.execPath,["node_modules/next/dist/bin/next","dev","--webpack","--hostname","127.0.0.1","--port",String(appPort)],{
  env:{...process.env,NEXT_TELEMETRY_DISABLED:"1",NEXT_PUBLIC_SUPABASE_URL:"http://127.0.0.1:"+fixture.address().port,NEXT_PUBLIC_SUPABASE_ANON_KEY:"local-fixture-key"},
  stdio:"inherit",windowsHide:true,
});
try {
  const endpoint="http://127.0.0.1:"+appPort+"/api?type=create-order";
  for (let i=0;i<40;i++) {
    try { await fetch(endpoint,{signal:AbortSignal.timeout(10000)}); break; }
    catch { await new Promise(resolve=>setTimeout(resolve,500)); }
  }
  const checkout=async (token)=>{
    const response=await fetch(endpoint,{method:"POST",headers:{"Content-Type":"application/json",...(token?{Authorization:"Bearer integration-test-token"}:{})},
      body:JSON.stringify({fullName:"Buyer",email:"buyer@example.invalid",phone:"555",address:"Farm Road",city:"Cebu",postalCode:"6000",deliveryMethod:"Delivery",deliveryFee:0,items:[{productId:1,quantity:2,price:0}]}),
      signal:AbortSignal.timeout(20000),
    });
    return [response.status,await response.json()];
  };
  assert.equal((await checkout(false))[0],401);
  assert.equal((await checkout(true))[1].data?.id,"legacy-order");
  phase="migrated";
  assert.equal((await checkout(true))[1].data?.id,"rpc-order");
  phase="rejected";
  assert.equal((await checkout(true))[0],409);
  assert.equal(directOrders,1);
  console.log("HTTP checkout bridge passed: sign-in gate, legacy schema, migrated RPC, trusted legacy fee and no replay on rejected checkout.");
} finally { next.kill(); fixture.close(); }
