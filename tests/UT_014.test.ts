import test from "node:test";
import assert from "node:assert/strict";
import { filterAndSortProducts, type Product } from "./helpers/greenguard-units.ts";

test('UT-014: Product Search - searching "lettuce" returns matching lettuce products', () => {
  const products: Product[] = [
    { id: 1, name: "Romaine Lettuce", category: "Leafy Greens", price: 120, stock: 5, description: "Fresh", imageUrl: "/a.jpg", farmerId: "f1" },
    { id: 2, name: "Cherry Tomatoes", category: "Fruiting", price: 150, stock: 5, description: "Fresh", imageUrl: "/b.jpg", farmerId: "f2" },
  ];
  const results = filterAndSortProducts(products, { search: "lettuce" });
  assert.equal(results.length, 1);
  assert.equal(results[0].name, "Romaine Lettuce");
});
