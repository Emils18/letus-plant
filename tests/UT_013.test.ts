import test from "node:test";
import assert from "node:assert/strict";
import { filterAndSortProducts, type Product } from "./helpers/greenguard-units.ts";

test("UT-013: Price Sorting - orders products according to selected price direction", () => {
  const products: Product[] = [
    { id: 1, name: "Romaine", category: "Leafy Greens", price: 120, stock: 5, description: "Fresh", imageUrl: "/a.jpg", farmerId: "f1" },
    { id: 2, name: "Iceberg", category: "Leafy Greens", price: 85, stock: 5, description: "Fresh", imageUrl: "/b.jpg", farmerId: "f1" },
    { id: 3, name: "Tomato", category: "Fruiting", price: 150, stock: 5, description: "Fresh", imageUrl: "/c.jpg", farmerId: "f2" },
  ];
  assert.deepEqual(filterAndSortProducts(products, { sortBy: "Price: Low to High" }).map((p) => p.price), [85, 120, 150]);
  assert.deepEqual(filterAndSortProducts(products, { sortBy: "Price: High to Low" }).map((p) => p.price), [150, 120, 85]);
});
