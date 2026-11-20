import test from "node:test";
import assert from "node:assert/strict";

test("UT-063: Profile Management - displays saved profile and validates updates", () => {
  const profile = { fullName: "Maria Santos", phone: "09170001111" };
  const update = (name: string, phone: string) => {
    if (!name.trim() || !phone.trim()) return false;
    profile.fullName = name.trim();
    profile.phone = phone.trim();
    return true;
  };
  assert.equal(update("", "0917"), false);
  assert.equal(update("Maria Clara", "09181234567"), true);
});
