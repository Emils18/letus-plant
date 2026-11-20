import test from "node:test";
import assert from "node:assert/strict";
import { registerBuyer, type UserAccount } from "./helpers/greenguard-units.ts";

test("UT-002: Buyer Registration - rejects duplicate email and advises user to log in", () => {
  const users: UserAccount[] = [
    { id: "buyer-1", email: "buyer@greenguard.test", password: "Password123!", role: "buyer" },
  ];
  const result = registerBuyer(users, "buyer@greenguard.test", "Password123!");
  assert.equal(result.success, false);
  assert.equal(result.message, "This email is already registered. Please log in instead.");
});
