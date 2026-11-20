import test from "node:test";
import assert from "node:assert/strict";
import { calculateCartTotals, type CartItem } from "./helpers/greenguard-units.ts";

test("UT-031: Shipping Calculation - sets shipping fee to ₱50 for delivery", () => {
  const cart: CartItem[] = [{ id: 1, name: "Romaine", category: "Leafy Greens", price: 100, stock: 5, description: "Crisp", imageUrl: "/a.jpg", farmerId: "f1", quantity: 1 }];
  const totals = calculateCartTotals(cart, "Delivery");
  assert.equal(totals.shipping, 50);
  assert.equal(totals.total, 150);
});
