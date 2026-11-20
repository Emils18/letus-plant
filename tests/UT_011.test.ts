import test from "node:test";
import assert from "node:assert/strict";
import { getProductDetails, type Product } from "./helpers/greenguard-units.ts";

test("UT-011: Product Details - displays correct product information when opened", () => {
  const products: Product[] = [
    { id: 1, name: "Romaine Lettuce", category: "Leafy Greens", price: 120, stock: 15, description: "Crisp romaine.", imageUrl: "/images/products/letuce1.jpg", farmerId: "farmer-1" },
  ];
  const product = getProductDetails(products, 1);
  assert.ok(product);
  assert.equal(product.name, "Romaine Lettuce");
  assert.equal(product.price, 120);
});
