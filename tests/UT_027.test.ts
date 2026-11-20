import test from "node:test";
import assert from "node:assert/strict";
import { filterAndSortProducts, updateProductStock, type Product } from "./helpers/greenguard-units.ts";

test("UT-027: Out-of-Stock Handling - marks zero-stock product hidden and unpurchasable", () => {
  const products: Product[] = [
    { id: 1, name: "Butterhead", category: "Leafy Greens", price: 110, stock: 5, description: "Fresh", imageUrl: "/a.png", farmerId: "f1" },
  ];
  const res = updateProductStock(products, 1, 0);
  assert.equal(res.success, true);
  assert.equal(res.outOfStock, true);
  assert.equal(filterAndSortProducts(products, {}).length, 0);
});
