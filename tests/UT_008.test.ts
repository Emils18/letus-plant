import test from "node:test";
import assert from "node:assert/strict";
import { requestPasswordReset } from "./helpers/greenguard-units.ts";

test("UT-008: Password Reset - displays safe generic message for unregistered email", () => {
  const sentTo: string[] = [];
  const result = requestPasswordReset([], "unknown@greenguard.test", (to) => sentTo.push(to));
  assert.equal(result.success, true);
  assert.equal(result.message, "Password reset link sent! Check your inbox.");
  assert.equal(result.emailDispatched, false);
  assert.deepEqual(sentTo, []);
});
