import { NextRequest, NextResponse } from "next/server";
import { supabase } from "@/lib/supabase";

function json(data: unknown, status = 200) {
  return NextResponse.json(data, { status });
}

type CheckoutItem = {
  productId: number;
  productName: string;
  price: number;
  quantity: number;
};

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
        farmer: product.farmer || "Local Farmer",
        category: product.category,
        price: Number(product.price || 0),
        stock: Number(product.stock || 0),
        badge: product.badge || "AI Verified",
        image:
          product.image ||
          "https://images.unsplash.com/photo-1540420773420-3366772f4999?q=80&w=1200",
        freshnessInfo:
          product.freshnessInfo ||
          product.freshness_info ||
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
        userId,
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

      if (!userId) {
        return json(
          {
            success: false,
            message: "You must be logged in to place an order.",
          },
          401
        );
      }

      if (
        !fullName ||
        !email ||
        !phone ||
        !paymentMethod ||
        !deliveryMethod ||
        !items ||
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

      const normalizedItems = items.map((item: CheckoutItem) => ({
        product_id: item.productId,
        product_name: item.productName,
        price: Number(item.price || 0),
        quantity: Number(item.quantity || 0),
        subtotal: Number(item.price || 0) * Number(item.quantity || 0),
      }));

      for (const item of normalizedItems) {
        if (!item.product_id || item.price <= 0 || item.quantity <= 0) {
          return json(
            {
              success: false,
              message: "Invalid order item detected.",
            },
            400
          );
        }

        const { data: product, error: productError } = await supabase
          .from("products")
          .select("id, stock")
          .eq("id", item.product_id)
          .single();

        if (productError || !product) {
          return json(
            {
              success: false,
              message: `Product not found: ${item.product_name}`,
            },
            404
          );
        }

        if (Number(product.stock || 0) < item.quantity) {
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
        (sum: number, item: any) => sum + item.subtotal,
        0
      );

      const shipping = deliveryMethod === "Delivery" ? 50 : 0;
      const totalAmount = subtotal + shipping;

      const paymentStatus =
        paymentMethod === "Cash on Delivery"
          ? "Unpaid"
          : "Pending Verification";

      const { data: orderData, error: orderError } = await supabase
        .from("orders")
        .insert([
          {
            user_id: userId,
            email,
            status: "Pending",
            shipping_name: fullName,
            shipping_phone: phone,
            shipping_address: address || "Farm Pickup",
            city: city || "Farm Pickup",
            postal_code: postalCode || "0000",
            payment_method: paymentMethod,
            delivery_method: deliveryMethod,
            payment_status: paymentStatus,
            total_amount: totalAmount,
          },
        ])
        .select()
        .single();

      if (orderError) throw orderError;

      const orderItemsPayload = normalizedItems.map((item: any) => ({
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

      for (const item of normalizedItems) {
        const { data: product } = await supabase
          .from("products")
          .select("stock")
          .eq("id", item.product_id)
          .single();

        const newStock = Math.max(
          Number(product?.stock || 0) - item.quantity,
          0
        );

        await supabase
          .from("products")
          .update({ stock: newStock })
          .eq("id", item.product_id);
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