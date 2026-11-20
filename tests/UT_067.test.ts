import test from "node:test";
import assert from "node:assert/strict";
import { validateAiImageInput } from "./helpers/greenguard-units.ts";

test("UT-067: Invalid Image Handling - rejects corrupted or empty image without crashing", () => {
  const res = validateAiImageInput({ mimeType: "image/jpeg", sizeBytes: 512, corrupted: true });
  assert.equal(res.valid, false);
  assert.equal(res.message, "Image file is corrupted or unreadable.");
});
