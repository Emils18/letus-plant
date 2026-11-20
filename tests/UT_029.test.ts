import test from "node:test";
import assert from "node:assert/strict";
import { calculateCartTotals, updateCartItemQuantity, type CartItem } from "./helpers/greenguard-units.ts";

test("UT-029: Quantity - updates item quantity and recalculates subtotal", () => {
  let cart: CartItem[] = [{ id: 1, name: "Romaine", category: "Leafy Greens", price: 100, stock: 5, description: "Crisp", imageUrl: "/a.jpg", farmerId: "f1", quantity: 1 }];
  cart = updateCartItemQuantity(cart, 1, 1);
  assert.equal(cart[0].quantity, 2);
  assert.equal(calculateCartTotals(cart, "Pickup").subtotal, 200);
});
