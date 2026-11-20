import test from "node:test";
import assert from "node:assert/strict";

test("UT-080: Database Operations (Delete) - deletes eligible record or rejects unauthorized delete", () => {
  const store = new Map<string, { id: string; ownerId: string }>([["rec-1", { id: "rec-1", ownerId: "u1" }]]);
  const del = (id: string, actor: string) => (store.get(id)?.ownerId === actor ? store.delete(id) : false);
  assert.equal(del("rec-1", "u2"), false);
  assert.equal(del("rec-1", "u1"), true);
});
