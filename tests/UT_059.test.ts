import test from "node:test";
import assert from "node:assert/strict";
import { searchAdminUsers, type UserAccount } from "./helpers/greenguard-units.ts";

test('UT-059: User Search - searching "XYZ" returns no matching users', () => {
  const users: UserAccount[] = [{ id: "b1", email: "buyer@test.com", role: "buyer" }];
  assert.equal(searchAdminUsers(users, "XYZ").length, 0);
});
