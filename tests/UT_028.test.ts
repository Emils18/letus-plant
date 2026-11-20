import test from "node:test";
import assert from "node:assert/strict";
import { addItemToCart, type Product } from "./helpers/greenguard-units.ts";

test("UT-028: Add to Cart - adds available product to the shopping cart", () => {
  const product: Product = { id: 1, name: "Romaine Lettuce", category: "Leafy Greens", price: 100, stock: 3, description: "Crisp", imageUrl: "/a.jpg", farmerId: "f1" };
  const { cart, added } = addItemToCart([], product);
  assert.equal(added, true);
  assert.equal(cart.length, 1);
});
