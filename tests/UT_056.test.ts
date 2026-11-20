import test from "node:test";
import assert from "node:assert/strict";
import { computeDashboardMetrics, type OrderRecord } from "./helpers/greenguard-units.ts";

test("UT-056: Admin Dashboard - reconciles administrative totals against underlying records", () => {
  const orders: OrderRecord[] = [
    { id: "ORD-1", userId: "b1", farmerId: "f1", items: [], subtotal: 500, shipping: 0, totalAmount: 500, status: "Completed", paymentStatus: "paid" },
  ];
  const metrics = computeDashboardMetrics(orders);
  assert.equal(metrics.totalOrders, 1);
  assert.equal(metrics.grossSalesPaidOnly, 500);
});
