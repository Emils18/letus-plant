import assert from "node:assert/strict";
import test from "node:test";
import { reportGuidance, scanClass, scanConfidencePercent, scanGuidance } from "../lib/scan-guidance.ts";

test("looks up the supported diagnoses without treating Unhealthy as Healthy", () => {
  assert.equal(scanGuidance("Downy_Mildew")?.pathogen_name, "Bremia lactucae");
  assert.match(scanGuidance("Powdery_Mildew")?.pathogen_name ?? "", /Erysiphe cichoracearum/);
  assert.equal(scanGuidance("Septoria leaf spot")?.pathogen_name, "Septoria lactucae");
  assert.equal(scanClass("No disease"), "healthy");
  assert.equal(scanGuidance("Unhealthy"), null);
});

test("preserves saved report details and fills gaps with labeled reference guidance", () => {
  const report = reportGuidance({
    disease_name: "Downy Mildew",
    selling_recommendation: "Stored recommendation",
    treatment_recommendations: ["Stored treatment"],
  });
  assert.equal(report.selling, "Stored recommendation");
  assert.deepEqual(report.treatments, ["Stored treatment"]);
  assert.equal(report.usesReference, true);
  assert.equal(report.pathogen, "Bremia lactucae");
  assert.equal(reportGuidance({ disease_name: "Unknown" }).usesReference, false);
});

test("retains missing confidence and accepts both formats used by historical scans", () => {
  assert.equal(scanConfidencePercent(0.94), 94);
  assert.equal(scanConfidencePercent("94"), 94);
  assert.equal(scanConfidencePercent("1%"), 1);
  for (const value of [null, "", "unknown", 101, -1]) {
    assert.equal(scanConfidencePercent(value), null);
  }
});
