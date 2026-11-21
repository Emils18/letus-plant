import assert from "node:assert/strict";
import test from "node:test";
import { canUseLegacyCheckout, isMissingCheckoutRpc } from "../lib/checkout-compatibility.ts";

test("checkout only falls back when the RPC and inventory column are absent", () => {
  assert.equal(isMissingCheckoutRpc({ code: "PGRST202", message: "Could not find place_marketplace_order in the schema cache" }), true);
  assert.equal(canUseLegacyCheckout({ code: "42703", message: "column products.archived_at does not exist" }), true);
  assert.equal(isMissingCheckoutRpc({ code: "PGRST202", message: "another function is missing" }), false);
  assert.equal(isMissingCheckoutRpc({ code: "22023", message: "Insufficient stock" }), false);
  assert.equal(isMissingCheckoutRpc({ code: "57014", message: "Timeout" }), false);
  assert.equal(canUseLegacyCheckout(null), false);
  assert.equal(canUseLegacyCheckout({ code: "42501", message: "permission denied for archived_at" }), false);
});
