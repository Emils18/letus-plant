import { NextRequest, NextResponse } from "next/server";
import { createClient } from "@supabase/supabase-js";

function json(data: unknown, status = 200) {
  return NextResponse.json(data, { status });
}

function getServiceClient() {
  const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const serviceRoleKey = process.env.SUPABASE_SERVICE_ROLE_KEY;

  if (!supabaseUrl || !serviceRoleKey) {
    return {
      client: null,
      error:
        "Missing env. Required: NEXT_PUBLIC_SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY",
    };
  }

  const client = createClient(supabaseUrl, serviceRoleKey, {
    auth: {
      persistSession: false,
      autoRefreshToken: false,
    },
  });

  return { client, error: null };
}

export async function GET() {
  try {
    const { client, error } = getServiceClient();

    if (!client || error) {
      return json({ success: false, message: error }, 500);
    }

    const { data, error: usersError } = await client
      .from("users")
      .select("id, full_name, email, role, created_at")
      .order("created_at", { ascending: false });

    if (usersError) {
      return json(
        {
          success: false,
          message: usersError.message,
        },
        500
      );
    }

    return json({
      success: true,
      users: data || [],
    });
  } catch (error) {
    return json(
      {
        success: false,
        message: error instanceof Error ? error.message : "Unknown server error",
      },
      500
    );
  }
}

export async function PATCH(request: NextRequest) {
  try {
    const { client, error } = getServiceClient();

    if (!client || error) {
      return json({ success: false, message: error }, 500);
    }

    const body = await request.json();

    const userId = body.userId as string;
    const role = body.role as "admin" | "farmer" | "buyer";

    if (!userId) {
      return json({ success: false, message: "Missing userId." }, 400);
    }

    if (!["admin", "farmer", "buyer"].includes(role)) {
      return json({ success: false, message: "Invalid role." }, 400);
    }

    const { data, error: updateError } = await client
      .from("users")
      .update({ role })
      .eq("id", userId)
      .select("id, full_name, email, role, created_at")
      .maybeSingle();

    if (updateError) {
      return json(
        {
          success: false,
          message: updateError.message,
        },
        500
      );
    }

    if (!data) {
      return json(
        {
          success: false,
          message: "No user was updated. Check user ID.",
        },
        404
      );
    }

    return json({
      success: true,
      message: `Role updated to ${role}.`,
      user: data,
    });
  } catch (error) {
    return json(
      {
        success: false,
        message: error instanceof Error ? error.message : "Unknown server error",
      },
      500
    );
  }
}

export async function DELETE(request: NextRequest) {
  try {
    const { client, error } = getServiceClient();

    if (!client || error) {
      return json({ success: false, message: error }, 500);
    }

    const { searchParams } = new URL(request.url);
    const userId = searchParams.get("userId");

    if (!userId) {
      return json({ success: false, message: "Missing userId." }, 400);
    }

    const { error: deleteError } = await client
      .from("users")
      .delete()
      .eq("id", userId);

    if (!deleteError) {
      await client.auth.admin.deleteUser(userId).catch(() => {});

      return json({
        success: true,
        message: "User deleted successfully.",
        mode: "hard_delete",
      });
    }

    const deletedEmail = `deleted_${Date.now()}_${userId}@removed.local`;

    const { data, error: softDeleteError } = await client
      .from("users")
      .update({
        full_name: "Deleted User",
        email: deletedEmail,
      })
      .eq("id", userId)
      .select("id, full_name, email, role, created_at")
      .maybeSingle();

    if (softDeleteError) {
      return json(
        {
          success: false,
          message: softDeleteError.message,
        },
        500
      );
    }

    if (!data) {
      return json(
        {
          success: false,
          message: "No user was deleted or hidden. Check user ID.",
        },
        404
      );
    }

    return json({
      success: true,
      message: "User hidden from admin list.",
      mode: "soft_delete",
      user: data,
    });
  } catch (error) {
    return json(
      {
        success: false,
        message: error instanceof Error ? error.message : "Unknown server error",
      },
      500
    );
  }
}