import test from "node:test";
import assert from "node:assert/strict";
import { completePasswordReset, loginBuyer, type UserAccount } from "./helpers/greenguard-units.ts";

test("UT-006: Password Reset - allows login using new password after completing reset", () => {
  const users: UserAccount[] = [
    { id: "buyer-1", email: "buyer@greenguard.test", password: "Password123!", role: "buyer" },
  ];
  const reset = completePasswordReset(users, "buyer@greenguard.test", "NewSecurePass99!");
  assert.equal(reset.success, true);
  assert.equal(loginBuyer(users, "buyer@greenguard.test", "Password123!").success, false);
  assert.equal(loginBuyer(users, "buyer@greenguard.test", "NewSecurePass99!").success, true);
});
