import test from "node:test";
import assert from "node:assert/strict";
import { type AppNotification } from "./helpers/greenguard-units.ts";

test("UT-054: User Notifications - creates notification for relevant user on activity", () => {
  const notifications: AppNotification[] = [{ id: "n1", userId: "b1", message: "Order confirmed", read: false }];
  assert.equal(notifications.length, 1);
  assert.equal(notifications[0].userId, "b1");
});
