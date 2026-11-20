import test from "node:test";
import assert from "node:assert/strict";
import { sendOrderMessage, type ChatMessage, type OrderRecord, type UserAccount } from "./helpers/greenguard-units.ts";

test("UT-051: Buyer-Farmer Chat - sends message from farmer to buyer", () => {
  const messages: ChatMessage[] = [];
  const farmer: UserAccount = { id: "f1", email: "f@test.com", role: "farmer" };
  const order: OrderRecord = { id: "ORD-1", userId: "b1", farmerId: "f1", items: [], subtotal: 100, shipping: 0, totalAmount: 100, status: "Confirmed", paymentStatus: "unpaid" };
  const res = sendOrderMessage(messages, order, farmer, "Harvested today!");
  assert.equal(res.success, true);
  assert.equal(messages[0].senderRole, "farmer");
});
