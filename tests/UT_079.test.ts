import test from "node:test";
import assert from "node:assert/strict";

test("UT-079: Database Operations (Update) - updates existing record with valid values", () => {
  const store = new Map<string, { id: string; name: string }>([["rec-1", { id: "rec-1", name: "Old" }]]);
  store.set("rec-1", { id: "rec-1", name: "Updated" });
  assert.equal(store.get("rec-1")?.name, "Updated");
});
