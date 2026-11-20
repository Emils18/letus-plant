import test from "node:test";
import assert from "node:assert/strict";
import { confirmBuyerReceipt, type OrderRecord } from "./helpers/greenguard-units.ts";

test("UT-049: Receipt Confirmation - marks order Completed and delivery Received", () => {
  const order: OrderRecord = { id: "ORD-1", userId: "b1", farmerId: "f1", items: [], subtotal: 100, shipping: 0, totalAmount: 100, status: "Delivered", paymentStatus: "unpaid", deliveryStatus: "Pending" };
  confirmBuyerReceipt(order);
  assert.equal(order.status, "Completed");
  assert.equal(order.deliveryStatus, "Received");
  assert.equal(order.paymentStatus, "paid");
});
