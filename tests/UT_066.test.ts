import test from "node:test";
import assert from "node:assert/strict";
import { formatDetectionResult } from "./helpers/greenguard-units.ts";

test("UT-066: Detection Result - presents model output and confidence in defined format", () => {
  const formatted = formatDetectionResult({ displayName: "Downy_Mildew", confidence: 0.94 });
  assert.equal(formatted.label, "Downy Mildew");
  assert.equal(formatted.confidencePercent, "94.0%");
});
