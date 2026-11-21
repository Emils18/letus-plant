import { NextRequest, NextResponse } from "next/server";
import { createClient } from "@supabase/supabase-js";
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
        payment_status: order.payment_status || "Unpaid",
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
          !Number.isInteger(productId) ||
          productId <= 0 ||
          !Number.isInteger(quantity) ||
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

        requestedQuantities.set(
          productId,
          (requestedQuantities.get(productId) || 0) + quantity
        );
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

      if (orderError) {
        return json({ success: false, message: orderError.message }, orderError.code === "22023" ? 409 : 500);
      }
      const orderData = placedOrders?.[0];
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
