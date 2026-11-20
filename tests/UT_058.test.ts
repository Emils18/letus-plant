import test from "node:test";
import assert from "node:assert/strict";
import { searchAdminUsers, type UserAccount } from "./helpers/greenguard-units.ts";

test('UT-058: User Search - searching "FAR" filters matching farmer users', () => {
  const users: UserAccount[] = [
    { id: "b1", email: "buyer@test.com", role: "buyer", fullName: "Buyer" },
    { id: "f1", email: "farmer@test.com", role: "farmer", fullName: "FAR Green" },
  ];
  const results = searchAdminUsers(users, "FAR");
  assert.equal(results.length, 1);
  assert.equal(results[0].id, "f1");
});
