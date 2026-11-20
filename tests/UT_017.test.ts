import test from "node:test";
import assert from "node:assert/strict";
import { createProductListing } from "./helpers/greenguard-units.ts";

test("UT-017: Create Product - blocks publication when no product image is selected", () => {
  const res = createProductListing([], {
    name: "Green Lettuce",
    category: "Leafy Greens",
    price: 95,
    stock: 10,
    imageUrl: null,
    farmerId: "farmer-1",
  });
  assert.equal(res.success, false);
  assert.equal(res.message, "Please select a product image.");
});
