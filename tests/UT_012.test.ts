import test from "node:test";
import assert from "node:assert/strict";
import { filterAndSortProducts, type Product } from "./helpers/greenguard-units.ts";

test("UT-012: Category Filter - displays only products matching selected category", () => {
  const products: Product[] = [
    { id: 1, name: "Romaine Lettuce", category: "Leafy Greens", price: 120, stock: 15, description: "Fresh", imageUrl: "/a.jpg", farmerId: "f1" },
    { id: 2, name: "Cherry Tomatoes", category: "Fruiting", price: 150, stock: 10, description: "Sweet", imageUrl: "/b.jpg", farmerId: "f2" },
  ];
  const filtered = filterAndSortProducts(products, { category: "Leafy Greens" });
  assert.equal(filtered.length, 1);
  assert.equal(filtered[0].category, "Leafy Greens");
});
