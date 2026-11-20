import test from "node:test";
import assert from "node:assert/strict";
import { registerBuyer } from "./helpers/greenguard-units.ts";

test("UT-003: Buyer Registration - prevents submission without email and password", () => {
  const result = registerBuyer([], "", "");
  assert.equal(result.success, false);
  assert.equal(result.message, "Email and password required.");
});
