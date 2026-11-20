import test from "node:test";
import assert from "node:assert/strict";
import { createProductListing } from "./helpers/greenguard-units.ts";

test("UT-021: Create Product - rejects zero stock quantity", () => {
  const res = createProductListing([], {
    name: "Green Lettuce",
    category: "Leafy Greens",
    price: 50,
    stock: 0,
    imageUrl: "/images/products/lettuce3.png",
    farmerId: "farmer-1",
  });
  assert.equal(res.success, false);
  assert.equal(res.message, "Stock must be at least 1.");
});
