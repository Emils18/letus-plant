import { NextRequest, NextResponse } from "next/server";
import { createClient } from "@supabase/supabase-js";
import { canUseLegacyCheckout, isMissingCheckoutRpc } from "@/lib/checkout-compatibility";
import { paymentStatusLabel } from "@/lib/payment-status";
import { supabase } from "@/lib/supabase";

function json(data: unknown, status = 200) {
  return NextResponse.json(data, { status });
}

type CheckoutItem = {
  productId: number;
  productName?: string;
  price?: number;
  quantity: number;
};

function getBearerToken(request: NextRequest) {
  const authorization = request.headers.get("authorization") || "";

  if (!authorization.startsWith("Bearer ")) {
    return "";
  }

  return authorization.slice(7).trim();
}

export async function GET(request: NextRequest) {
  const { searchParams } = new URL(request.url);
  const type = searchParams.get("type");
  const userId = searchParams.get("userId");

  try {
    if (type === "products") {
      const { data, error } = await supabase
        .from("products")
        .select("*")
        .order("created_at", { ascending: false });

      if (error) throw error;

      const products = (data || []).filter((product) => product.archived_at == null).map((product) => ({
  id: product.id,
  name: product.name,
  farmer: product.farmer || product.farmer_name || "",
  farmerId: product.farmer_id || null,
  location: product.location || null,
  category: product.category || "",
  price: Number(product.price ?? 0),
  stock: Number(product.stock ?? 0),
  image: product.image || product.image_url || "",
  freshnessInfo:
    product.freshnessInfo ||
    product.freshness_info ||
    product.description ||
    "",
  createdAt: product.created_at,
}));

      return json({ success: true, data: products });
    }

    if (type === "orders") {
      let query = supabase
        .from("orders")
        .select("*, order_items(*)")
        .order("created_at", { ascending: false });

      if (userId) {
        query = query.eq("user_id", userId);
      }

      const { data, error } = await query;

      if (error) throw error;

      const orders = (data || []).map((order) => ({
        id: order.id,
        orderCode: order.order_code || null,
        date: order.created_at,
        fullName: order.shipping_name,
        email: order.email,
        phone: order.shipping_phone,
        address: order.shipping_address,
        city: order.city,
        postalCode: order.postal_code,
        paymentMethod: order.payment_method,
        deliveryMethod: order.delivery_method,
        total_amount: Number(order.total_amount || 0),
        status: order.status || "Pending",
        delivery_status: order.delivery_status || "Pending",
        payment_status: paymentStatusLabel(order.payment_status, order.payment_method),
        proof_image_url: order.proof_image_url || order.delivery_proof_url || null,
        items: (order.order_items || []).map((item: { product_id?: number; product_name?: string; price?: number | string; quantity?: number | string; subtotal?: number | string }) => ({
          productId: item.product_id,
          productName: item.product_name,
          price: Number(item.price || 0),
          quantity: Number(item.quantity || 0),
          subtotal: Number(item.subtotal || 0),
        })),
      }));

      return json({ success: true, data: orders });
    }

    return json({ success: false, message: "Invalid GET type" }, 400);
  } catch (error) {
    return json(
      {
        success: false,
        message: "Server error",
        error: error instanceof Error ? error.message : "Unknown error",
      },
      500
    );
  }
}

export async function POST(request: NextRequest) {
  const { searchParams } = new URL(request.url);
  const type = searchParams.get("type");

  try {
    const body = await request.json();

    if (type === "create-order") {
      const {
        fullName,
        email,
        phone,
        address,
        city,
        postalCode,
        deliveryMethod,
        items,
      } = body;
      const agreedPaymentMethod = "To be agreed in person";

      const accessToken = getBearerToken(request);

      if (!accessToken) {
        return json(
          {
            success: false,
            message: "You must be logged in to place an order.",
          },
          401
        );
      }

      const buyerClient = createClient(
        process.env.NEXT_PUBLIC_SUPABASE_URL!,
        process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
        {
          auth: { persistSession: false, autoRefreshToken: false },
          global: { headers: { Authorization: `Bearer ${accessToken}` } },
        },
      );

      // Verify the signed-in user from the access token. Do not trust user IDs from the frontend.
      const {
        data: { user: authenticatedUser },
        error: authError,
      } = await buyerClient.auth.getUser(accessToken);

      if (authError || !authenticatedUser) {
        return json(
          {
            success: false,
            message: "Your session is invalid or expired. Please log in again.",
          },
          401
        );
      }

      const { data: profile, error: profileError } = await buyerClient
        .from("users")
        .select("role")
        .eq("id", authenticatedUser.id)
        .maybeSingle();

      if (profileError) throw profileError;

      const role = String(
        profile?.role || authenticatedUser.user_metadata?.role || ""
      ).toLowerCase();

      if (role !== "buyer") {
        return json(
          {
            success: false,
            message: "Only buyer accounts can place marketplace orders.",
          },
          403
        );
      }

      if (
        !fullName ||
        !email ||
        !phone ||
        !deliveryMethod ||
        !Array.isArray(items) ||
        items.length === 0
      ) {
        return json(
          {
            success: false,
            message: "Missing required checkout fields.",
          },
          400
        );
      }

      if (deliveryMethod !== "Delivery" && deliveryMethod !== "Pickup") {
        return json(
          {
            success: false,
            message: "Invalid delivery method.",
          },
          400
        );
      }

      if (
        deliveryMethod === "Delivery" &&
        (!address || !city || !postalCode)
      ) {
        return json(
          {
            success: false,
            message: "Please provide your full delivery address.",
          },
          400
        );
      }

      // Combine duplicate product entries before checking stock.
      const requestedQuantities = new Map<number, number>();

      for (const item of items as CheckoutItem[]) {
        const productId = Number(item.productId);
        const quantity = Number(item.quantity);

        if (
          !Number.isSafeInteger(productId) ||
          productId <= 0 ||
          !Number.isSafeInteger(quantity) || quantity > 2147483647 ||
          quantity <= 0
        ) {
          return json(
            {
              success: false,
              message: "Invalid order item detected.",
            },
            400
          );
        }

        const combined = (requestedQuantities.get(productId) || 0) + quantity;
        if (combined > 2147483647) return json({success: false, message: "Order quantity is too large."}, 400);
        requestedQuantities.set(productId, combined);
      }

      const { data: placedOrders, error: orderError } = await buyerClient.rpc("place_marketplace_order", {
        p_contact: {
          email,
          shipping_name: fullName,
          shipping_phone: phone,
          shipping_address: address,
          city,
          postal_code: postalCode,
          payment_method: agreedPaymentMethod,
          delivery_method: deliveryMethod,
        },
        p_items: Array.from(requestedQuantities, ([product_id, quantity]) => ({ product_id, quantity })),
        p_single_farmer: true,
      });

      let placedOrder = placedOrders?.[0];
      if (isMissingCheckoutRpc(orderError)) {
        // Production can run this route before the inventory migration. A
        // missing RPC is the only error that proves no checkout ran.
        const { error: schemaError } = await buyerClient.from("products").select("archived_at").limit(0);
        if (!canUseLegacyCheckout(schemaError)) {
          return json({ success: false, message: "Checkout is being updated. Please try again shortly." }, 503);
        }
        const productIds = Array.from(requestedQuantities.keys());

        // Read the real product owner, price, name, and stock from the database.
        const { data: productRows, error: productsError } = await buyerClient
          .from("products")
          .select("id, name, price, stock, farmer_id")
          .in("id", productIds);

        if (productsError) throw productsError;

        const databaseProducts = (productRows || []) as { id: number; name: string; price: number; stock: number; farmer_id: string | null }[];

        if (databaseProducts.length !== productIds.length) {
          return json(
            {
              success: false,
              message: "One or more products could not be found.",
            },
            404
          );
        }

        const farmerIds = new Set(
          databaseProducts.map((product) => product.farmer_id).filter(Boolean)
        );

        if (
          farmerIds.size !== 1 ||
          databaseProducts.some((product) => !product.farmer_id)
        ) {
          return json(
            {
              success: false,
              message: "Please checkout products from one farmer at a time.",
            },
            400
          );
        }

        const farmerId = Array.from(farmerIds)[0] as string;

        const normalizedItems = databaseProducts.map((product) => {
          const quantity = requestedQuantities.get(Number(product.id)) || 0;
          const price = Number(product.price || 0);
          const stock = Number(product.stock || 0);

          return {
            product_id: Number(product.id),
            product_name: product.name,
            price,
            quantity,
            subtotal: price * quantity,
            current_stock: stock,
          };
        });

        for (const item of normalizedItems) {
          if (item.price <= 0 || item.quantity <= 0) {
            return json(
              {
                success: false,
                message: `Invalid product data for ${item.product_name}.`,
              },
              400
            );
          }

          if (item.current_stock < item.quantity) {
            return json(
              {
                success: false,
                message: `Not enough stock for ${item.product_name}.`,
              },
              400
            );
          }
        }

        const subtotal = normalizedItems.reduce(
          (sum, item) => sum + item.subtotal,
          0
        );
        const shipping = deliveryMethod === "Delivery" ? 50 : 0;
        const totalAmount = subtotal + shipping;
        const paymentStatus = "Unpaid";

        const { data: orderData, error: orderError } = await buyerClient
          .from("orders")
          .insert([
            {
              user_id: authenticatedUser.id,
              farmer_id: farmerId,
              email,
              status: "Pending",
              delivery_status: "Pending",
              shipping_name: fullName,
              shipping_phone: phone,
              shipping_address:
                deliveryMethod === "Pickup" ? "Farm Pickup" : address,
              city: deliveryMethod === "Pickup" ? "Farm Pickup" : city,
              postal_code: deliveryMethod === "Pickup" ? "0000" : postalCode,
              payment_method: agreedPaymentMethod,
              delivery_method: deliveryMethod,
              payment_status: paymentStatus,
              total_amount: totalAmount,
            },
          ])
          .select()
          .single();

        if (orderError) throw orderError;

        const orderItemsPayload = normalizedItems.map((item) => ({
          order_id: orderData.id,
          product_id: item.product_id,
          product_name: item.product_name,
          price: item.price,
          quantity: item.quantity,
          subtotal: item.subtotal,
        }));

        const { error: itemsError } = await buyerClient
          .from("order_items")
          .insert(orderItemsPayload);

        if (itemsError) throw itemsError;
        // Reduce stock only after the order and order items are saved.
        for (const item of normalizedItems) {
          const newStock = Math.max(item.current_stock - item.quantity, 0);

          const { error: stockError } = await buyerClient
            .from("products")
            .update({ stock: newStock })
            .eq("id", item.product_id);

          if (stockError) throw stockError;
        }

        placedOrder = orderData;
      } else if (orderError) {
        return json({ success: false, message: orderError.message }, orderError.code === "22023" ? 409 : 500);
      }
      const orderData = placedOrder;
      if (!orderData) throw new Error("The order was not created.");

      const { error: notificationError } = await buyerClient
        .from("notifications")
        .insert({
          user_id: orderData.farmer_id,
          order_id: orderData.id,
          title: "New Order",
          message: "Someone ordered your product.",
          type: "new_order",
          is_read: false,
        });
      if (notificationError) console.error("CREATE NOTIFICATION FAILED:", notificationError.message);

      return json({
        success: true,
        message: "Order placed successfully",
        data: orderData,
      });
    }

    return json({ success: false, message: "Invalid POST type" }, 400);
  } catch (error) {
    console.error("API Error:", error);

    return json(
      {
        success: false,
        message: "Server error. Check console.",
        error: error instanceof Error ? error.message : "Unknown error",
      },
      500
    );
  }
}
