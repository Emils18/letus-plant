import test from "node:test";
import assert from "node:assert/strict";
import { computeDashboardMetrics, type OrderRecord } from "./helpers/greenguard-units.ts";

test("UT-057: Gross Sales - distinguishes paid revenue from unpaid or pending order value", () => {
  const orders: OrderRecord[] = [
    { id: "ORD-1", userId: "b1", farmerId: "f1", items: [], subtotal: 400, shipping: 0, totalAmount: 400, status: "Completed", paymentStatus: "paid" },
    { id: "ORD-2", userId: "b1", farmerId: "f1", items: [], subtotal: 250, shipping: 0, totalAmount: 250, status: "Pending", paymentStatus: "unpaid" },
  ];
  const metrics = computeDashboardMetrics(orders);
  assert.equal(metrics.grossSalesPaidOnly, 400);
  assert.equal(metrics.pendingOrderValue, 250);
});
