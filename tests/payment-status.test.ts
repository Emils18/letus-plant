import assert from "node:assert/strict";
import test from "node:test";
import { paymentStatusLabel } from "../lib/payment-status.ts";

test("separates payment method and payment status for new and historical orders", () => {
  assert.equal(paymentStatusLabel("Unpaid", "To be agreed in person"), "Unpaid");
  assert.equal(paymentStatusLabel("To be agreed in person"), "Unpaid");
  assert.equal(paymentStatusLabel("Cash on Delivery", "Cash on Delivery"), "Unpaid");
  assert.equal(paymentStatusLabel(" paid "), "Paid");
  assert.equal(paymentStatusLabel("Refunded"), "Refunded");
});
