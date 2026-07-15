import { NextRequest, NextResponse } from "next/server";
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

type ProductRow = {
  id: number;
  name: string;
  price: number | string | null;
  stock: number | string | null;
  farmer_id: string | null;
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

      const products = (data || []).map((product) => ({
        id: product.id,
        name: product.name,
        farmer: product.farmer || product.farmer_name || "Local Farmer",
        farmerId: product.farmer_id || null,
        location: product.location || null,
        category: product.category,
        price: Number(product.price || 0),
        stock: Number(product.stock || 0),
        badge: product.badge || "AI Verified",
        image:
          product.image ||
          product.image_url ||
          "https://images.unsplash.com/photo-1540420773420-3366772f4999?q=80&w=1200",
        freshnessInfo:
          product.freshnessInfo ||
          product.freshness_info ||
          product.description ||
          "AI verified lettuce crop.",
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
        items: (order.order_items || []).map((item: any) => ({
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
        paymentMethod,
        deliveryMethod,
        items,
      } = body;

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

      // Verify the signed-in user from the access token. Do not trust user IDs from the frontend.
      const {
        data: { user: authenticatedUser },
        error: authError,
      } = await supabase.auth.getUser(accessToken);

      if (authError || !authenticatedUser) {
        return json(
          {
            success: false,
            message: "Your session is invalid or expired. Please log in again.",
          },
          401
        );
      }

      const { data: profile, error: profileError } = await supabase
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
        !paymentMethod ||
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

      const allowedPaymentMethods =
        deliveryMethod === "Pickup"
          ? ["Cash", "GCash", "Card"]
          : ["Cash on Delivery", "GCash", "Card"];

      if (!allowedPaymentMethods.includes(paymentMethod)) {
        return json(
          {
            success: false,
            message:
              deliveryMethod === "Pickup"
                ? "Pickup orders can only use Cash, GCash, or Card."
                : "Delivery orders can only use Cash on Delivery, GCash, or Card.",
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

      const productIds = Array.from(requestedQuantities.keys());

      // Read the real product owner, price, name, and stock from the database.
      const { data: productRows, error: productsError } = await supabase
        .from("products")
        .select("id, name, price, stock, farmer_id")
        .in("id", productIds);

      if (productsError) throw productsError;

      const databaseProducts = (productRows || []) as ProductRow[];

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
      const paymentStatus =
        paymentMethod === "Cash on Delivery" || paymentMethod === "Cash"
          ? "Unpaid"
          : "Pending Verification";

      const { data: orderData, error: orderError } = await supabase
        .from("orders")
        .insert([
          {
            user_id: authenticatedUser.id,
            farmer_id: farmerId,
            email,
            status: "Pending",
            shipping_name: fullName,
            shipping_phone: phone,
            shipping_address:
              deliveryMethod === "Pickup" ? "Farm Pickup" : address,
            city: deliveryMethod === "Pickup" ? "Farm Pickup" : city,
            postal_code: deliveryMethod === "Pickup" ? "0000" : postalCode,
            payment_method: paymentMethod,
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

      const { error: itemsError } = await supabase
        .from("order_items")
        .insert(orderItemsPayload);

      if (itemsError) throw itemsError;
// CREATE NOTIFICATION FOR FARMER
const { error: notificationError } = await supabase
  .from("notifications")
  .insert({
    user_id: farmerId,
    order_id: orderData.id,
    title: "New Order",
    message: "Someone ordered your product.",
    type: "new_order",
    is_read: false,
  });

if (notificationError) {
  console.error("CREATE NOTIFICATION FAILED:", notificationError.message);
  throw notificationError;
}
      // Reduce stock only after the order and order items are saved.
      for (const item of normalizedItems) {
        const newStock = Math.max(item.current_stock - item.quantity, 0);

        const { error: stockError } = await supabase
          .from("products")
          .update({ stock: newStock })
          .eq("id", item.product_id);

        if (stockError) throw stockError;
      }

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
