import test from "node:test";
import assert from "node:assert/strict";
import { requestPasswordReset } from "./helpers/greenguard-units.ts";

test("UT-007: Password Reset - prompts for email when forgot-password form is empty", () => {
  const result = requestPasswordReset([], "   ");
  assert.equal(result.success, false);
  assert.equal(result.message, "Please enter your email first.");
});
