import test from "node:test";
import assert from "node:assert/strict";
import { registerBuyer } from "./helpers/greenguard-units.ts";

test("UT-004: Buyer Registration - validates invalid email format", () => {
  const result = registerBuyer([], "not-an-email", "Password123!");
  assert.equal(result.success, false);
  assert.equal(result.message, "Please enter a valid email address.");
});
