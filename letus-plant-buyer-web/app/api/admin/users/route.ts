import { NextRequest, NextResponse } from "next/server";
import { createClient } from "@supabase/supabase-js";

function json(data: unknown, status = 200) {
  return NextResponse.json(data, { status });
}

function getServiceClient() {
  const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const key = process.env.SUPABASE_SERVICE_ROLE_KEY;
  if (!url || !key) return { client: null, url, error: "Server Supabase service credentials are not configured." };
  return {
    client: createClient(url, key, { auth: { persistSession: false, autoRefreshToken: false } }),
    url,
    error: null,
  };
}

async function authorizeAdmin(request: NextRequest) {
  const configured = getServiceClient();
  if (!configured.client || !configured.url || configured.error) {
    return { response: json({ success: false, message: configured.error }, 500) };
  }

  const token = request.headers.get("authorization")?.replace(/^Bearer\s+/i, "");
  if (!token) return { response: json({ success: false, message: "Sign in as an admin to manage users." }, 401) };

  const anonKey = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;
  if (!anonKey) return { response: json({ success: false, message: "Supabase public key is not configured on the server." }, 500) };

  const authClient = createClient(configured.url, anonKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data: { user }, error: authError } = await authClient.auth.getUser(token);
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
    if (targetId === adminId) return json({ success: false, message: "You cannot delete the admin account you are currently using." }, 400);

    const { data: target, error: lookupError } = await client.auth.admin.getUserById(targetId);
    const authUserMissing = lookupError &&
      (lookupError.code === "user_not_found" || /not found|user not found/i.test(lookupError.message));
    if (lookupError && !authUserMissing) {
      return json({ success: false, message: `Could not verify the Auth account: ${lookupError.message}` }, 500);
    }

    if (target.user) {
      const { error: authDeleteError } = await client.auth.admin.deleteUser(targetId);
      if (authDeleteError) {
        return json({
          success: false,
          message: `Supabase Auth did not delete this account, so no success was reported: ${authDeleteError.message}`,
        }, 409);
      }
    }

    const { error: profileDeleteError } = await client.from("users").delete().eq("id", targetId);
    if (profileDeleteError) {
      return json({
        success: false,
        message: `The Auth login was removed, but its public profile could not be deleted. Check foreign-key references on public.users: ${profileDeleteError.message}`,
      }, 409);
    }

    const { data: remainingProfile, error: verifyProfileError } = await client
      .from("users")
      .select("id")
      .eq("id", targetId)
      .maybeSingle();
    const { data: remainingAuth } = await client.auth.admin.getUserById(targetId);
    if (verifyProfileError || remainingProfile || remainingAuth.user) {
      return json({
        success: false,
        message: "Deletion could not be verified. The account was not reported as deleted; refresh and retry or check the database references.",
      }, 409);
    }

    return json({ success: true, message: "Account and user profile permanently deleted." });
  } catch (error) {
    return json({ success: false, message: error instanceof Error ? error.message : "Unknown server error" }, 500);
  }
}
