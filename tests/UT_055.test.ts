import test from "node:test";
import assert from "node:assert/strict";
import { computeDashboardMetrics, type OrderRecord } from "./helpers/greenguard-units.ts";

test("UT-055: Farmer Dashboard - reconciles farmer order count and paid revenue against records", () => {
  const orders: OrderRecord[] = [
    { id: "ORD-1", userId: "b1", farmerId: "f1", items: [], subtotal: 300, shipping: 0, totalAmount: 300, status: "Completed", paymentStatus: "paid" },
    { id: "ORD-2", userId: "b1", farmerId: "f1", items: [], subtotal: 150, shipping: 0, totalAmount: 150, status: "Pending", paymentStatus: "unpaid" },
  ];
  const metrics = computeDashboardMetrics(orders);
  assert.equal(metrics.totalOrders, 2);
  assert.equal(metrics.grossSalesPaidOnly, 300);
});
