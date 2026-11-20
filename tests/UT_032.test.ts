import test from "node:test";
import assert from "node:assert/strict";
import { persistCart, restoreCart, type CartItem } from "./helpers/greenguard-units.ts";

test("UT-032: Cart Persistence - retains cart items across page refresh", () => {
  const storage = new Map<string, string>();
  const cart: CartItem[] = [{ id: 1, name: "Romaine", category: "Leafy Greens", price: 100, stock: 5, description: "Crisp", imageUrl: "/a.jpg", farmerId: "f1", quantity: 2 }];
  persistCart(storage, cart);
  const restored = restoreCart(storage);
  assert.equal(restored.length, 1);
  assert.equal(restored[0].quantity, 2);
});
