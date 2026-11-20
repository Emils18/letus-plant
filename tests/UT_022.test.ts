import test from "node:test";
import assert from "node:assert/strict";
import { createProductListing } from "./helpers/greenguard-units.ts";

test("UT-022: Create Product - applies default description when description is empty", () => {
  const res = createProductListing([], {
    name: "Green Lettuce",
    category: "Leafy Greens",
    price: 50,
    stock: 5,
    description: "",
    imageUrl: "/images/products/lettuce3.png",
    farmerId: "farmer-1",
  });
  assert.equal(res.success, true);
  assert.equal(res.product?.description, "Freshly harvested organic lettuce.");
});
