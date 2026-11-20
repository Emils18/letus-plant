import test from "node:test";
import assert from "node:assert/strict";
import { validateAiImageInput } from "./helpers/greenguard-units.ts";

test("UT-064: Image Input - accepts supported image input and rejects unsupported/empty input", () => {
  assert.equal(validateAiImageInput({ mimeType: "image/jpeg", sizeBytes: 1024 }).valid, true);
  assert.equal(validateAiImageInput({ mimeType: "text/plain", sizeBytes: 1024 }).valid, false);
});
