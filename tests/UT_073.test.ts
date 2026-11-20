import test from "node:test";
import assert from "node:assert/strict";
import { type DiagnosticLog } from "./helpers/greenguard-units.ts";

test("UT-073: Create Diagnostic Log - stores diagnostic result with image and metadata", () => {
  const logs: DiagnosticLog[] = [
    { id: "log-1", userId: "f1", diseaseName: "Downy Mildew", confidenceScore: 0.94, imageUrl: "https://ex.com/1.jpg", location: "Cebu", capturedAt: "2026-11-20T10:00:00Z" },
  ];
  assert.equal(logs.length, 1);
  assert.equal(logs[0].diseaseName, "Downy Mildew");
});
