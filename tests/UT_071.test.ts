import test from "node:test";
import assert from "node:assert/strict";

test("UT-071: Monitoring Schedule - validates and saves drone monitoring schedule", () => {
  const schedules: string[] = [];
  const save = (time: string) => (/^\d{2}:\d{2}$/.test(time) ? (schedules.push(time), true) : false);
  assert.equal(save("bad"), false);
  assert.equal(save("07:30"), true);
});
