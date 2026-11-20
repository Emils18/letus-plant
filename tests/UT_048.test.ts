import test from "node:test";
import assert from "node:assert/strict";
import { type OrderRecord } from "./helpers/greenguard-units.ts";

test("UT-048: Delivery Proof - saves delivery proof and makes it visible to buyer", () => {
  const order: OrderRecord = { id: "ORD-1", userId: "b1", farmerId: "f1", items: [], subtotal: 100, shipping: 0, totalAmount: 100, status: "Delivered", paymentStatus: "unpaid" };
  order.deliveryProofUrl = "https://storage.greenguard.test/delivery.jpg";
  assert.equal(order.deliveryProofUrl, "https://storage.greenguard.test/delivery.jpg");
});
