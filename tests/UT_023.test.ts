import test from "node:test";
import assert from "node:assert/strict";
import { getProductPreviewState } from "./helpers/greenguard-units.ts";

test("UT-023: Product Preview - flags invalid values instead of presenting them as valid", () => {
  const preview = getProductPreviewState({ name: "", price: 0, stock: -1, imageUrl: null });
  assert.equal(preview.hasInvalidValues, true);
  assert.deepEqual(preview.warnings, ["Missing name", "Invalid price", "Invalid stock", "Missing image"]);
});
