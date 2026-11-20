import test from "node:test";
import assert from "node:assert/strict";
import { validateCheckoutSubmission, type CartItem, type CheckoutForm, type UserAccount } from "./helpers/greenguard-units.ts";

test("UT-039: Delivery Address Validation - blocks delivery checkout when address fields are empty", () => {
  const buyer: UserAccount = { id: "b1", email: "b@test.com", role: "buyer" };
  const cart: CartItem[] = [{ id: 1, name: "Lettuce", category: "Leafy Greens", price: 100, stock: 5, description: "Fresh", imageUrl: "/a.jpg", farmerId: "f1", quantity: 1 }];
  const form: CheckoutForm = { fullName: "Juan", email: "b@test.com", phone: "09171234567", deliveryMethod: "Delivery", address: "", city: "", postalCode: "" };
  const res = validateCheckoutSubmission(buyer, cart, form);
  assert.equal(res.valid, false);
  assert.equal(res.message, "Please provide your full delivery address.");
});
