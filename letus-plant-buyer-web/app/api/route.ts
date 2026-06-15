import { NextRequest, NextResponse } from "next/server";
import { supabase } from "@/lib/supabase";

function json(data: unknown, status = 200) {
  return NextResponse.json(data, { status });
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
      return json({ success: true, data });
    }

    if (type === "orders") {
      // Filter orders so buyers only see their own
      let query = supabase
        .from("orders")
        .select("*, order_items(*)")
        .order("created_at", { ascending: false });

      if (userId) {
        query = query.eq("user_id", userId);
      }

      const { data, error } = await query;
      if (error) throw error;

      return json({ success: true, data });
    }

    return json({ success: false, message: "Invalid GET type" }, 400);
  } catch (error) {
    return json({ success: false, message: "Server error", error: error instanceof Error ? error.message : "Unknown error" }, 500);
  }
}

export async function POST(request: NextRequest) {
  const { searchParams } = new URL(request.url);
  const type = searchParams.get("type");

  try {
    const body = await request.json();

    if (type === "create-order") {
      // NEW: Catching deliveryMethod from the frontend
      const { userId, fullName, email, phone, address, city, postalCode, paymentMethod, deliveryMethod, items } = body;

      if (!userId) return json({ success: false, message: "You must be logged in to place an order." }, 401);

      if (!fullName || !email || !phone || !paymentMethod || !deliveryMethod || !items || items.length === 0) {
        return json({ success: false, message: "Missing required checkout fields" }, 400);
      }

      const normalizedItems = items.map((item: any) => ({
        product_id: item.productId,
        product_name: item.productName,
        price: item.price,
        quantity: item.quantity,
        subtotal: item.price * item.quantity,
      }));

      const subtotal = normalizedItems.reduce((sum: number, item: any) => sum + item.subtotal, 0);
      
      // Calculate Shipping based on the new delivery method
      const shipping = deliveryMethod === "Delivery" ? 50 : 0; 
      const totalAmount = subtotal + shipping;

      // Determine Payment Status
      const paymentStatus = paymentMethod === "Cash on Delivery" ? "Unpaid" : "Pending Verification";

      // 1. Insert into orders table
      const { data: orderData, error: orderError } = await supabase
        .from("orders")
        .insert([
          {
            user_id: userId,
            email: email,
            status: "Pending",
            shipping_name: fullName,
            shipping_phone: phone,
            shipping_address: address || "Farm Pickup", // Fallback if pickup
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

      // 2. Insert into order_items table
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

      return json({ success: true, message: "Order placed successfully", data: orderData });
    }

    return json({ success: false, message: "Invalid POST type" }, 400);
  } catch (error) {
    console.error("API Error:", error);
    return json({ success: false, message: "Server error. Check console.", error: error instanceof Error ? error.message : "Unknown error" }, 500);
  }
}