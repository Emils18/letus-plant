import test from "node:test";
import assert from "node:assert/strict";
import { sendOrderMessage, type OrderRecord, type UserAccount } from "./helpers/greenguard-units.ts";

test("UT-053: Completed Order Chat - enforces read-only chat after order completion", () => {
  const buyer: UserAccount = { id: "b1", email: "b@test.com", role: "buyer" };
  const order: OrderRecord = { id: "ORD-1", userId: "b1", farmerId: "f1", items: [], subtotal: 100, shipping: 0, totalAmount: 100, status: "Completed", paymentStatus: "paid" };
  const res = sendOrderMessage([], order, buyer, "Thanks!");
  assert.equal(res.success, false);
  assert.equal(res.error, "Chat is read-only after order completion.");
});
