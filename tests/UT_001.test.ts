import test from "node:test";
import assert from "node:assert/strict";
import { loginBuyer, type UserAccount } from "./helpers/greenguard-units.ts";

test("UT-001: Buyer Login - submits valid registered buyer credentials and redirects", () => {
  const users: UserAccount[] = [
    { id: "buyer-1", email: "buyer@greenguard.test", password: "Password123!", role: "buyer" },
  ];
  const result = loginBuyer(users, "buyer@greenguard.test", "Password123!");
  assert.equal(result.success, true);
  assert.equal(result.redirectTo, "/shop");
  assert.equal(result.user?.role, "buyer");
});
