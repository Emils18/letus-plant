import test from "node:test";
import assert from "node:assert/strict";
import { logoutAdmin, type UserAccount } from "./helpers/greenguard-units.ts";

test("UT-009: Admin Logout - ends admin session and returns to public homepage", () => {
  const session: { user: UserAccount | null } = {
    user: { id: "admin-1", email: "admin@greenguard.test", role: "admin" },
  };
  const result = logoutAdmin(session);
  assert.equal(result.sessionCleared, true);
  assert.equal(result.redirectTo, "/");
  assert.equal(session.user, null);
});
