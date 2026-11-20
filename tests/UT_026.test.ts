import test from "node:test";
import assert from "node:assert/strict";
import { deleteProductListing, type Product } from "./helpers/greenguard-units.ts";

test("UT-026: Delete Product - removes product listing after confirmation", () => {
  const products: Product[] = [
    { id: 1, name: "Butterhead", category: "Leafy Greens", price: 110, stock: 10, description: "Fresh", imageUrl: "/a.png", farmerId: "f1" },
  ];
  assert.equal(deleteProductListing(products, 1, false).success, false);
  assert.equal(deleteProductListing(products, 1, true).success, true);
  assert.equal(products.length, 0);
});
