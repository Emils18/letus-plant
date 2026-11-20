import test from "node:test";
import assert from "node:assert/strict";
import { createOrder, type CartItem, type CheckoutForm, type OrderRecord, type UserAccount } from "./helpers/greenguard-units.ts";

test("UT-041: Order Creation - creates order and returns order confirmation", () => {
  const buyer: UserAccount = { id: "b1", email: "b@test.com", role: "buyer" };
  const cart: CartItem[] = [{ id: 1, name: "Lettuce", category: "Leafy Greens", price: 120, stock: 5, description: "Fresh", imageUrl: "/a.jpg", farmerId: "f1", quantity: 2 }];
  const form: CheckoutForm = { fullName: "Juan", email: "b@test.com", phone: "09171234567", deliveryMethod: "Delivery", address: "123 St", city: "Cebu", postalCode: "6015" };
  const orders: OrderRecord[] = [];
  const res = createOrder(orders, buyer, cart, form);
  assert.equal(res.success, true);
  assert.equal(res.order?.totalAmount, 290);
});
