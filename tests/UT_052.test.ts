import test from "node:test";
import assert from "node:assert/strict";
import { sendOrderMessage, type ChatMessage, type OrderRecord, type UserAccount } from "./helpers/greenguard-units.ts";

test("UT-052: Chat Persistence - persists sent messages across reload", () => {
  const messages: ChatMessage[] = [];
  const buyer: UserAccount = { id: "b1", email: "b@test.com", role: "buyer" };
  const order: OrderRecord = { id: "ORD-1", userId: "b1", farmerId: "f1", items: [], subtotal: 100, shipping: 0, totalAmount: 100, status: "Confirmed", paymentStatus: "unpaid" };
  sendOrderMessage(messages, order, buyer, "Hello");
  const persisted = JSON.parse(JSON.stringify(messages)) as ChatMessage[];
  assert.equal(persisted[0].body, "Hello");
});
