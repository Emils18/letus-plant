import test from "node:test";
import assert from "node:assert/strict";
import { loginBuyer, type UserAccount } from "./helpers/greenguard-units.ts";

test("UT-061: Mobile Login - authenticates valid credentials and rejects invalid credentials", () => {
  const users: UserAccount[] = [{ id: "m1", email: "m@test.com", password: "Secret!", role: "farmer" }];
  assert.equal(loginBuyer(users, "m@test.com", "Secret!").success, true);
  assert.equal(loginBuyer(users, "m@test.com", "Wrong").success, false);
});
