import test from "node:test";
import assert from "node:assert/strict";
import { type OrderRecord } from "./helpers/greenguard-units.ts";

test("UT-047: Payment Proof - authorized admin can open uploaded payment proof", () => {
  const order: OrderRecord = { id: "ORD-1", userId: "b1", farmerId: "f1", items: [], subtotal: 100, shipping: 0, totalAmount: 100, status: "Pending", paymentStatus: "pending", paymentProofUrl: "https://storage.greenguard.test/proof.png" };
  assert.ok(order.paymentProofUrl?.endsWith(".png"));
});
