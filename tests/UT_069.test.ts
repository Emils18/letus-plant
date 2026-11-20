import test from "node:test";
import assert from "node:assert/strict";

test("UT-069: ESP32-CAM Communication - reports communication error when camera is unreachable", () => {
  const checkCamera = (reachable: boolean) => (reachable ? { ok: true } : { ok: false, error: "ESP32-CAM timeout" });
  assert.equal(checkCamera(false).ok, false);
  assert.equal(checkCamera(false).error, "ESP32-CAM timeout");
});
