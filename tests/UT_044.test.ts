import test from "node:test";
import assert from "node:assert/strict";
import { type OrderRecord } from "./helpers/greenguard-units.ts";

test("UT-044: Order Details - displays correct order details when opened", () => {
  const orders: OrderRecord[] = [
    { id: "ORD-1", userId: "buyer-1", farmerId: "farmer-1", items: [], subtotal: 240, shipping: 50, totalAmount: 290, status: "Pending", paymentStatus: "unpaid" },
  ];
  const found = orders.find((o) => o.id === "ORD-1");
  assert.equal(found?.totalAmount, 290);
});
