import test from "node:test";
import assert from "node:assert/strict";
import { runYoloInferenceMock } from "./helpers/greenguard-units.ts";

test("UT-065: YOLOv8n Inference - returns configured prediction output for supported image", () => {
  const prediction = runYoloInferenceMock(2048);
  assert.equal(prediction.success, true);
  assert.equal(prediction.displayName, "Downy_Mildew");
});
