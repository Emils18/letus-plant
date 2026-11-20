import test from "node:test";
import assert from "node:assert/strict";
import { promoteUserToAdmin, type UserAccount } from "./helpers/greenguard-units.ts";

test("UT-060: Make Admin - requires confirmation before changing user role", () => {
  const admin: UserAccount = { id: "a1", email: "admin@test.com", role: "admin" };
  const candidate: UserAccount = { id: "b1", email: "buyer@test.com", role: "buyer" };
  assert.equal(promoteUserToAdmin(admin, candidate, false).requiresConfirmation, true);
  assert.equal(candidate.role, "buyer");
  assert.equal(promoteUserToAdmin(admin, candidate, true).success, true);
  assert.equal(candidate.role, "admin");
});
