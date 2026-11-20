import test from "node:test";
import assert from "node:assert/strict";
import { createProductListing } from "./helpers/greenguard-units.ts";

test("UT-016: Create Product - blocks publication when product name is empty", () => {
  const res = createProductListing([], {
    name: "   ",
    category: "Leafy Greens",
    price: 95,
    stock: 10,
    imageUrl: "/images/products/lettuce3.png",
    farmerId: "farmer-1",
  });
  assert.equal(res.success, false);
  assert.equal(res.message, "Product name is required.");
});
