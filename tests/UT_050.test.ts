import test from "node:test";
import assert from "node:assert/strict";
import { sendOrderMessage, type ChatMessage, type OrderRecord, type UserAccount } from "./helpers/greenguard-units.ts";

test("UT-050: Buyer-Farmer Chat - sends message from buyer to farmer", () => {
  const messages: ChatMessage[] = [];
  const buyer: UserAccount = { id: "b1", email: "b@test.com", role: "buyer" };
  const order: OrderRecord = { id: "ORD-1", userId: "b1", farmerId: "f1", items: [], subtotal: 100, shipping: 0, totalAmount: 100, status: "Confirmed", paymentStatus: "unpaid" };
  const res = sendOrderMessage(messages, order, buyer, "Is this fresh?");
  assert.equal(res.success, true);
  assert.equal(messages[0].senderRole, "buyer");
});
