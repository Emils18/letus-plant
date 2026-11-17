import { createClient } from "@supabase/supabase-js";
import { NextRequest, NextResponse } from "next/server";

function json(data: unknown, status = 200) {
  return NextResponse.json(data, { status, headers: { "Cache-Control": "no-store" } });
}

export async function POST(request: NextRequest) {
  const token = (request.headers.get("authorization") || "").replace(/^Bearer\s+/i, "").trim();
  if (!token) return json({ success: false, message: "Please sign in before scanning." }, 401);

  const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const anonKey = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;
  if (!supabaseUrl || !anonKey) return json({ success: false, message: "Database configuration is missing." }, 500);

  const userClient = createClient(supabaseUrl, anonKey, {
    auth: { persistSession: false, autoRefreshToken: false },
    global: { headers: { Authorization: `Bearer ${token}` } },
  });
  const { data: { user }, error: authError } = await userClient.auth.getUser(token);
  if (authError || !user) return json({ success: false, message: "Your session expired. Please sign in again." }, 401);

  const { data: profile, error: profileError } = await userClient.from("users").select("role").eq("id", user.id).maybeSingle();
  if (profileError) return json({ success: false, message: profileError.message }, 500);
  if (String(profile?.role || user.user_metadata?.role || "").toLowerCase() !== "farmer") {
    return json({ success: false, message: "Disease scanning is available to farmer accounts." }, 403);
  }

  const form = await request.formData();
  const image = form.get("image");
  if (!(image instanceof File) || !image.type.startsWith("image/") || image.size === 0 || image.size > 12 * 1024 * 1024) {
    return json({ success: false, message: "Choose a valid image under 12 MB." }, 400);
  }

  const servers = [
    process.env.GREENGUARD_AI_URL,
    "http://192.168.254.192:5000",
    "http://192.168.254.143:5000",
  ].filter((value): value is string => Boolean(value));
  let diagnosis: Record<string, unknown> | null = null;
  let lastError = "GreenGuard AI could not be reached. Connect the website host and AI laptop to the same network, then check GREENGUARD_AI_URL.";

  for (const server of [...new Set(servers)]) {
    try {
      const health = await fetch(`${server}/health`, { cache: "no-store", signal: AbortSignal.timeout(4000) });
      const healthData = await health.json();
      if (!health.ok || healthData.online !== true || healthData.model_loaded !== true) continue;

      const body = new FormData();
      body.set("image", image, image.name || "lettuce.jpg");
      const response = await fetch(`${server}/scan`, { method: "POST", body, cache: "no-store", signal: AbortSignal.timeout(90000) });
      const result = await response.json();
      if (!response.ok || result.success !== true || result.diagnosis_available !== true || !result.result) {
        lastError = result.message || "The AI could not produce a diagnosis. Try a clear photo of one lettuce leaf.";
        continue;
      }
      diagnosis = result.result as Record<string, unknown>;
      break;
    } catch {
      // Try the backup AI server if the primary is offline.
    }
  }

  if (!diagnosis) return json({ success: false, message: lastError }, 502);

  const now = new Date().toISOString();
  const storagePath = `${user.id}/web_${Date.now()}_${image.name.replace(/[^a-zA-Z0-9._-]/g, "_")}`;
  let imageUrl: string | null = null;
  const { error: uploadError } = await userClient.storage.from("diagnostic-images").upload(storagePath, image, {
    contentType: image.type,
    upsert: true,
  });
  if (!uploadError) imageUrl = userClient.storage.from("diagnostic-images").getPublicUrl(storagePath).data.publicUrl;

  const diseaseName = String(diagnosis.display_name || diagnosis.class_name || "Unknown Result").replaceAll("_", " ");
  const confidence = Number(diagnosis.confidence ?? 0);
  const location = String(form.get("location") || "Lapu-Lapu City, Cebu").trim();
  const { error: saveError } = await userClient.from("diagnostic_logs").insert({
    user_id: user.id,
    disease_name: diseaseName,
    confidence_score: confidence,
    location,
    device_id: "GreenGuard-Web-Scan",
    captured_at: now,
    created_at: now,
    ...(imageUrl ? { image_url: imageUrl } : {}),
  });
  if (saveError) return json({ success: false, message: `Diagnosis ready but could not save the health log: ${saveError.message}` }, 500);

  return json({ success: true, disease_name: diseaseName, confidence_score: confidence, image_saved: Boolean(imageUrl) });
}
