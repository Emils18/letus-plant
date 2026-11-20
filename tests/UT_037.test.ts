import test from "node:test";
import assert from "node:assert/strict";
import { canOpenCheckoutView } from "./helpers/greenguard-units.ts";

test("UT-037: Authentication Requirement - blocks unauthenticated checkout access and requires login", () => {
  const guard = canOpenCheckoutView(null);
  assert.equal(guard.allowed, false);
  assert.equal(guard.redirectToAuth, true);
});
