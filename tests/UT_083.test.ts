import test from "node:test";
import assert from "node:assert/strict";
import { promoteUserToAdmin, type UserAccount } from "./helpers/greenguard-units.ts";

test("UT-083: Role Authorization - denies restricted admin action for non-admin account", () => {
  const buyer: UserAccount = { id: "b1", email: "b@test.com", role: "buyer" };
  const target: UserAccount = { id: "f1", email: "f@test.com", role: "farmer" };
  const res = promoteUserToAdmin(buyer, target, true);
  assert.equal(res.success, false);
  assert.equal(res.message, "Admin permission is required.");
});
