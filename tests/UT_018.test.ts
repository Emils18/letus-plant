import test from "node:test";
import assert from "node:assert/strict";
import { createProductListing } from "./helpers/greenguard-units.ts";

test("UT-018: Create Product - rejects negative product price", () => {
  const res = createProductListing([], {
    name: "Green Lettuce",
    category: "Leafy Greens",
    price: -10,
    stock: 10,
    imageUrl: "/images/products/lettuce3.png",
    farmerId: "farmer-1",
  });
  assert.equal(res.success, false);
  assert.equal(res.message, "Price must be at least 1.");
});
