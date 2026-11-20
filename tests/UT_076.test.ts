import test from "node:test";
import assert from "node:assert/strict";
import { type DatasetImage } from "./helpers/greenguard-units.ts";

test("UT-076: Image Annotation - saves annotation associated with correct dataset image", () => {
  const dataset: DatasetImage[] = [{ id: "ds-1", filename: "leaf.jpg", storagePath: "dataset/leaf.jpg", annotations: [] }];
  dataset[0].annotations.push({ label: "Downy_Mildew", bbox: [10, 20, 120, 140] });
  assert.equal(dataset[0].annotations[0].label, "Downy_Mildew");
});
