import test from "node:test";
import assert from "node:assert/strict";

test("UT-070: Drone Device Status - displays received status or unavailable state", () => {
  const status = (connected: boolean, battery?: number) => (connected ? `CONNECTED (${battery ?? 0}%)` : "UNAVAILABLE");
  assert.equal(status(true, 88), "CONNECTED (88%)");
  assert.equal(status(false), "UNAVAILABLE");
});
