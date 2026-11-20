import test from "node:test";
import assert from "node:assert/strict";
import { progressOrderStatus, type OrderRecord } from "./helpers/greenguard-units.ts";

test("UT-045: Order Status - progresses order through Pending, Confirmed, Preparing, Shipped, Delivered", () => {
  const order: OrderRecord = { id: "ORD-1", userId: "b1", farmerId: "f1", items: [], subtotal: 100, shipping: 0, totalAmount: 100, status: "Pending", paymentStatus: "unpaid" };
  for (const status of ["Confirmed", "Preparing", "Shipped", "Delivered"] as const) {
    progressOrderStatus(order, status);
    assert.equal(order.status, status);
  }
});
