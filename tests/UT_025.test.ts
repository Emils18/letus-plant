import test from "node:test";
import assert from "node:assert/strict";
import { updateProductStock, type Product } from "./helpers/greenguard-units.ts";

test("UT-025: Update Stock - changes stock quantity and reflects updated value", () => {
  const products: Product[] = [
    { id: 1, name: "Butterhead", category: "Leafy Greens", price: 110, stock: 10, description: "Fresh", imageUrl: "/a.png", farmerId: "f1" },
  ];
  const res = updateProductStock(products, 1, 25);
  assert.equal(res.success, true);
  assert.equal(products[0].stock, 25);
});
