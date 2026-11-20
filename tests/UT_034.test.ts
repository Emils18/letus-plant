import test from "node:test";
import assert from "node:assert/strict";
import { calculateCartTotals } from "./helpers/greenguard-units.ts";

test("UT-034: Empty Cart - disables checkout when cart has no items", () => {
  assert.equal(calculateCartTotals([], "Delivery").canCheckout, false);
});
