import test from "node:test";
import assert from "node:assert/strict";
import { addItemToCart, updateCartItemQuantity, type CartItem, type Product } from "./helpers/greenguard-units.ts";

test("UT-035: Stock Validation - limits cart quantity to available stock", () => {
  const product: Product = { id: 1, name: "Romaine", category: "Leafy Greens", price: 100, stock: 3, description: "Crisp", imageUrl: "/a.jpg", farmerId: "f1" };
  let cart: CartItem[] = [{ ...product, quantity: 3 }];
  assert.equal(addItemToCart(cart, product).added, false);
  cart = updateCartItemQuantity(cart, 1, 5);
  assert.equal(cart[0].quantity, 3);
});
