import { createClient, type SupabaseClient } from "@supabase/supabase-js";
import { NextRequest, NextResponse } from "next/server";

function json(data: unknown, status = 200) {
  return NextResponse.json(data, { status });
}

function getServiceClient() {
  const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const key = process.env.SUPABASE_SERVICE_ROLE_KEY;
  if (!url || !key) {
    return { client: null, url: url || "", error: "Server Supabase service credentials are not configured." };
  }
  return {
    client: createClient(url, key, { auth: { persistSession: false, autoRefreshToken: false } }),
    url,
    error: null,
  };
}

function isMissingTable(error: { message?: string; code?: string } | null) {
  const message = String(error?.message || "").toLowerCase();
  return error?.code === "42P01" || message.includes("does not exist") || message.includes("schema cache");
}

async function authorizeAdmin(request: NextRequest) {
  const configured = getServiceClient();
  if (!configured.client || !configured.url || configured.error) {
    return { response: json({ success: false, message: configured.error }, 500) };
  }

  const token = request.headers.get("authorization")?.replace(/^Bearer\s+/i, "");
  if (!token) return { response: json({ success: false, message: "Sign in as an admin to manage users." }, 401) };

  const anonKey = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;
  if (!anonKey) {
    return { response: json({ success: false, message: "Supabase public key is not configured on the server." }, 500) };
  }

  const authClient = createClient(configured.url, anonKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const {
    data: { user },
    error: authError,
  } = await authClient.auth.getUser(token);
  if (authError || !user) {
    return { response: json({ success: false, message: "Your admin session expired. Sign in again." }, 401) };
  }

  const { data: profile, error: profileError } = await configured.client
    .from("users")
    .select("role")
    .eq("id", user.id)
    .maybeSingle();
  if (profileError) return { response: json({ success: false, message: profileError.message }, 500) };
  if (String(profile?.role || "").toLowerCase() !== "admin") {
    return { response: json({ success: false, message: "Admin permission is required." }, 403) };
  }

  return { client: configured.client, userId: user.id };
}

async function deleteWhere(client: SupabaseClient, table: string, column: string, value: string) {
  const { error } = await client.from(table).delete().eq(column, value);
  if (error && !isMissingTable(error)) throw new Error(`${table}: ${error.message}`);
}

async function wipeUserOwnedRows(client: SupabaseClient, userId: string) {
  await deleteWhere(client, "order_messages", "sender_id", userId);
  await deleteWhere(client, "notifications", "user_id", userId);
  await deleteWhere(client, "diagnostic_logs", "user_id", userId);
  await deleteWhere(client, "products", "farmer_id", userId);

  const { data: orders, error: ordersError } = await client
    .from("orders")
    .select("id")
    .or(`user_id.eq.${userId},farmer_id.eq.${userId}`);
  if (ordersError && !isMissingTable(ordersError)) {
    throw new Error(`orders lookup: ${ordersError.message}`);
  }

  const orderIds = (orders || []).map((order) => order.id).filter(Boolean);
  if (orderIds.length) {
    const { error: itemError } = await client.from("order_items").delete().in("order_id", orderIds);
    if (itemError && !isMissingTable(itemError)) throw new Error(`order_items: ${itemError.message}`);

    const { error: messageError } = await client
      .from("order_messages")
      .delete()
      .in("order_id", orderIds.map(String));
    if (messageError && !isMissingTable(messageError)) throw new Error(`order_messages: ${messageError.message}`);

    const { error: deleteOrdersError } = await client.from("orders").delete().in("id", orderIds);
    if (deleteOrdersError && !isMissingTable(deleteOrdersError)) {
      throw new Error(`orders: ${deleteOrdersError.message}`);
    }
  }
}

async function deleteAuthAccounts(client: SupabaseClient, userId: string, email?: string | null) {
  const { error } = await client.auth.admin.deleteUser(userId, false);
  if (error && !/not found|user not found/i.test(error.message) && error.code !== "user_not_found") {
    throw new Error(error.message);
  }

  const targetEmail = email?.trim().toLowerCase();
  if (!targetEmail) return;

  for (let page = 1; page <= 10; page += 1) {
    const { data, error: listError } = await client.auth.admin.listUsers({ page, perPage: 200 });
    if (listError) throw new Error(listError.message);
    const users = data?.users || [];
    for (const user of users) {
      if (user.email?.trim().toLowerCase() !== targetEmail) continue;
      const { error: extraError } = await client.auth.admin.deleteUser(user.id, false);
      if (extraError && !/not found|user not found/i.test(extraError.message)) {
        throw new Error(extraError.message);
      }
    }
    if (users.length < 200) break;
  }
}

export async function GET(request: NextRequest) {
  try {
    const context = await authorizeAdmin(request);
    if (context.response) return context.response;
    const { data, error } = await context.client
      .from("users")
      .select("id, full_name, email, role, created_at")
      .order("created_at", { ascending: false });
    if (error) return json({ success: false, message: error.message }, 500);
    return json({ success: true, users: data || [] });
  } catch (error) {
    return json({ success: false, message: error instanceof Error ? error.message : "Unknown server error" }, 500);
  }
}

export async function PATCH(request: NextRequest) {
  try {
    const context = await authorizeAdmin(request);
    if (context.response) return context.response;
    const body = await request.json();
    const userId = String(body.userId || "");
    const role = String(body.role || "").toLowerCase();
    if (!userId) return json({ success: false, message: "Missing userId." }, 400);
    if (!["admin", "farmer", "buyer"].includes(role)) return json({ success: false, message: "Invalid role." }, 400);

    const { data, error } = await context.client
      .from("users")
      .update({ role })
      .eq("id", userId)
      .select("id, full_name, email, role, created_at")
      .maybeSingle();
    if (error) return json({ success: false, message: error.message }, 500);
    if (!data) return json({ success: false, message: "No user was updated. Check user ID." }, 404);
    return json({ success: true, message: `Role updated to ${role}.`, user: data });
  } catch (error) {
    return json({ success: false, message: error instanceof Error ? error.message : "Unknown server error" }, 500);
  }
}

export async function DELETE(request: NextRequest) {
  try {
    const context = await authorizeAdmin(request);
    if (context.response) return context.response;
    const { client, userId: adminId } = context;
    const targetId = new URL(request.url).searchParams.get("userId");
    if (!targetId) return json({ success: false, message: "Missing userId." }, 400);
    if (targetId === adminId) {
      return json({ success: false, message: "You cannot delete the admin account you are currently using." }, 400);
    }

    const { data: profile } = await client
      .from("users")
      .select("id, email")
      .eq("id", targetId)
      .maybeSingle();

    await wipeUserOwnedRows(client, targetId);
    await deleteAuthAccounts(client, targetId, profile?.email);

    const { error: profileDeleteError } = await client.from("users").delete().eq("id", targetId);
    if (profileDeleteError && !isMissingTable(profileDeleteError)) {
      return json({
        success: false,
        message: `The login was removed, but the profile could not be deleted: ${profileDeleteError.message}`,
      }, 409);
    }

    const { data: remainingProfile } = await client.from("users").select("id").eq("id", targetId).maybeSingle();
    const { data: remainingAuth } = await client.auth.admin.getUserById(targetId);
    if (remainingProfile || (remainingAuth.user && !remainingAuth.user.deleted_at)) {
      return json({
        success: false,
        message: "Deletion could not be verified. The account still exists in Auth or users.",
      }, 409);
    }

    return json({
      success: true,
      message: "Account permanently deleted. That email can be registered again.",
    });
  } catch (error) {
    return json({ success: false, message: error instanceof Error ? error.message : "Unknown server error" }, 500);
  }
}
