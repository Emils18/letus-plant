import test from "node:test";
import assert from "node:assert/strict";
import { canAccessAdminPage } from "./helpers/greenguard-units.ts";

test("UT-010: Admin Access Control - denies unauthenticated access to protected admin page", () => {
  const unauthenticated = canAccessAdminPage(null);
  assert.equal(unauthenticated.allowed, false);
  assert.equal(unauthenticated.status, 307);
  assert.equal(unauthenticated.redirectTo, "/");
});
