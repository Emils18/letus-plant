import test from "node:test";
import assert from "node:assert/strict";
import { getInitialCheckoutForm } from "./helpers/greenguard-units.ts";

test("UT-033: Checkout Form - resets checkout form fields on fresh page load", () => {
  const form = getInitialCheckoutForm();
  assert.equal(form.fullName, "");
  assert.equal(form.email, "");
  assert.equal(form.phone, "");
  assert.equal(form.address, "");
});
