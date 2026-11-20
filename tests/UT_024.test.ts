import test from "node:test";
import assert from "node:assert/strict";
import { editProductListing, type Product } from "./helpers/greenguard-units.ts";

test("UT-024: Edit Product - updates existing product information and saves changes", () => {
  const products: Product[] = [
    { id: 1, name: "Old Lettuce", category: "Leafy Greens", price: 80, stock: 10, description: "Old", imageUrl: "/a.png", farmerId: "f1" },
  ];
  const updated = editProductListing(products, 1, { name: "Fresh Butterhead", price: 110 });
  assert.equal(updated.success, true);
  assert.equal(products[0].name, "Fresh Butterhead");
  assert.equal(products[0].price, 110);
});
