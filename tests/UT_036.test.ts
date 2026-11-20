import test from "node:test";
import assert from "node:assert/strict";
import { addItemToCart, type Product } from "./helpers/greenguard-units.ts";

test("UT-036: Stock Validation - prevents adding zero-stock product to cart", () => {
  const outOfStock: Product = { id: 1, name: "Romaine", category: "Leafy Greens", price: 100, stock: 0, description: "Crisp", imageUrl: "/a.jpg", farmerId: "f1" };
  const result = addItemToCart([], outOfStock);
  assert.equal(result.added, false);
  assert.equal(result.message, "Product is out of stock.");
});
