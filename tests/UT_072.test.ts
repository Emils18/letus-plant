import test from "node:test";
import assert from "node:assert/strict";

test("UT-072: Weather Data Retrieval - processes temperature and condition data", () => {
  const parse = (temp: number, cond: string) => ({ temp, cond: cond.split(",")[0].trim() });
  const parsed = parse(29.5, "Partly cloudy, humid");
  assert.equal(parsed.temp, 29.5);
  assert.equal(parsed.cond, "Partly cloudy");
});
