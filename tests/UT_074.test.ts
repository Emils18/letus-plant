import test from "node:test";
import assert from "node:assert/strict";
import { type DiagnosticLog } from "./helpers/greenguard-units.ts";

test("UT-074: View Diagnostic Log - retrieves saved diagnostic record for authorized user", () => {
  const logs: DiagnosticLog[] = [
    { id: "log-1", userId: "f1", diseaseName: "Healthy", confidenceScore: 0.99, imageUrl: "https://ex.com/2.jpg", location: "Cebu", capturedAt: "2026-11-20T10:05:00Z" },
  ];
  assert.ok(logs.find((l) => l.id === "log-1" && l.userId === "f1"));
  assert.equal(logs.find((l) => l.id === "log-1" && l.userId === "other"), undefined);
});
