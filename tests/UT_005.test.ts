import test from "node:test";
import assert from "node:assert/strict";
import { requestPasswordReset, type UserAccount } from "./helpers/greenguard-units.ts";

test("UT-005: Password Reset - sends reset email for registered email address", () => {
  const users: UserAccount[] = [
    { id: "buyer-1", email: "buyer@greenguard.test", password: "Password123!", role: "buyer" },
  ];
  const sentTo: string[] = [];
  const result = requestPasswordReset(users, "buyer@greenguard.test", (to) => sentTo.push(to));
  assert.equal(result.success, true);
  assert.equal(result.emailDispatched, true);
  assert.deepEqual(sentTo, ["buyer@greenguard.test"]);
});
