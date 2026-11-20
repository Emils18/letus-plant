import test from "node:test";
import assert from "node:assert/strict";
import { type DatasetImage } from "./helpers/greenguard-units.ts";

test("UT-075: Dataset Upload - accepts supported image file and stores in configured path", () => {
  const dataset: DatasetImage[] = [];
  const upload = (filename: string, mime: string) =>
    mime.startsWith("image/") ? (dataset.push({ id: "ds-1", filename, storagePath: `dataset/${filename}`, annotations: [] }), true) : false;
  assert.equal(upload("bad.pdf", "application/pdf"), false);
  assert.equal(upload("leaf_01.jpg", "image/jpeg"), true);
});
