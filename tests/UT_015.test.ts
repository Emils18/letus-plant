import test from "node:test";
import assert from "node:assert/strict";
import { createProductListing, filterAndSortProducts, type Product } from "./helpers/greenguard-units.ts";

test("UT-015: Create Product - saves valid listing and makes it visible in marketplace", () => {
  const products: Product[] = [];
  const res = createProductListing(products, {
    name: "TEST Lettuce",
    category: "Leafy Greens",
    price: 95,
    stock: 10,
    description: "Hydroponic crisp lettuce",
    imageUrl: "/images/products/lettuce3.png",
    farmerId: "farmer-1",
  });
  assert.equal(res.success, true);
  assert.equal(filterAndSortProducts(products, {})[0]?.name, "TEST Lettuce");
});
