import test from "node:test";
import assert from "node:assert/strict";
import { generateSummaryReport, type UserAccount } from "./helpers/greenguard-units.ts";

test("UT-082: Report Access - denies unauthorized buyer access to restricted reports", () => {
  const buyer: UserAccount = { id: "b1", email: "b@test.com", role: "buyer" };
  const res = generateSummaryReport(buyer, [], []);
  assert.equal(res.success, false);
  assert.equal(res.status, 403);
});
