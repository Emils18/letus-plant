import test from "node:test";
import assert from "node:assert/strict";
import { markNotificationRead, type AppNotification } from "./helpers/greenguard-units.ts";

test("UT-084: Notification Read State - marks notification as read and persists updated state", () => {
  const notifications: AppNotification[] = [{ id: "n1", userId: "b1", message: "Shipped", read: false }];
  const updated = markNotificationRead(notifications, "n1");
  assert.equal(updated?.read, true);
  assert.equal(notifications[0].read, true);
});
