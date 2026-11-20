import test from "node:test";
import assert from "node:assert/strict";
import { cancelBuyerOrder, type OrderRecord } from "./helpers/greenguard-units.ts";

test("UT-046: Buyer Cancellation - buyer can cancel an eligible pending order", () => {
  const order: OrderRecord = { id: "ORD-1", userId: "buyer-1", farmerId: "f1", items: [], subtotal: 100, shipping: 0, totalAmount: 100, status: "Pending", paymentStatus: "unpaid" };
  const res = cancelBuyerOrder(order, "buyer-1");
  assert.equal(res.success, true);
  assert.equal(order.status, "Cancelled");
});
