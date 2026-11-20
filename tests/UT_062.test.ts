import test from "node:test";
import assert from "node:assert/strict";
import { registerBuyer, type UserAccount } from "./helpers/greenguard-units.ts";

test("UT-062: Mobile Registration - validates required fields and creates account", () => {
  const users: UserAccount[] = [];
  assert.equal(registerBuyer(users, "", "").success, false);
  assert.equal(registerBuyer(users, "mobile@test.com", "Secret123!").success, true);
});
