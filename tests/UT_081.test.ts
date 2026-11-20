import test from "node:test";
import assert from "node:assert/strict";
import { generateSummaryReport, type OrderRecord, type UserAccount } from "./helpers/greenguard-units.ts";

test("UT-081: Generate Report - generates report with expected records and calculated totals", () => {
  const admin: UserAccount = { id: "a1", email: "a@test.com", role: "admin" };
  const orders: OrderRecord[] = [{ id: "ORD-1", userId: "b1", farmerId: "f1", items: [], subtotal: 200, shipping: 50, totalAmount: 250, status: "Completed", paymentStatus: "paid" }];
  const res = generateSummaryReport(admin, orders, []);
  assert.equal(res.success, true);
  assert.equal(res.report?.revenue, 250);
});
