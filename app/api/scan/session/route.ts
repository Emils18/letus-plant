import { createClient } from "@supabase/supabase-js";
import { NextRequest, NextResponse } from "next/server";
import { scanClass, scanConfidencePercent } from "@/lib/scan-guidance";

function json(data: unknown, status = 200) {
  return NextResponse.json(data, {
    status,
    headers: { "Cache-Control": "no-store" },
  });
}

const countKeys = {
  healthy: "healthy",
  "downy mildew": "downy",
  "powdery mildew": "powdery",
  "septoria blight": "septoria",
} as const;

export async function POST(request: NextRequest) {
  try {
    const token = (request.headers.get("authorization") || "")
      .replace(/^Bearer\s+/i, "")
      .trim();
    if (!token) {
      return json({ success: false, message: "Please sign in to finish this scan session." }, 401);
    }

    const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL;
    const anonKey = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;
    if (!supabaseUrl || !anonKey) {
      return json({ success: false, message: "Database configuration is missing." }, 500);
    }

    const userClient = createClient(supabaseUrl, anonKey, {
      auth: { persistSession: false, autoRefreshToken: false },
      global: { headers: { Authorization: `Bearer ${token}` } },
    });
    const { data: { user }, error: authError } = await userClient.auth.getUser(token);
    if (authError || !user) {
      return json({ success: false, message: "Your session expired. Please sign in again." }, 401);
    }

    const { data: profile, error: profileError } = await userClient
      .from("users")
      .select("role")
      .eq("id", user.id)
      .maybeSingle();
    if (profileError) return json({ success: false, message: profileError.message }, 500);
    if (String(profile?.role || user.user_metadata?.role || "").toLowerCase() !== "farmer") {
      return json({ success: false, message: "Scan sessions are available to farmer accounts." }, 403);
    }

    const body = await request.json();
    const sessionId = String(body.scan_session_id || "").trim();
    if (!sessionId) {
      return json({ success: false, message: "A scan session ID is required." }, 400);
    }

    const { data: scanSession, error: sessionError } = await userClient
      .from("scan_sessions")
      .select("id, status, completed_at")
      .eq("id", sessionId)
      .eq("user_id", user.id)
      .maybeSingle();
    if (sessionError) return json({ success: false, message: sessionError.message }, 500);
    if (!scanSession) return json({ success: false, message: "Scan session not found." }, 404);
    if (!["active", "completed"].includes(String(scanSession.status || ""))) {
      return json({ success: false, message: "This scan session cannot be completed." }, 409);
    }

    const pageSize = 500;
    const records: { disease_name: string | null; confidence_score: number | string | null }[] = [];
    for (let offset = 0; ; offset += pageSize) {
      const { data: scans, error: scansError } = await userClient
        .from("diagnostic_logs")
        .select("disease_name, confidence_score")
        .eq("user_id", user.id)
        .eq("scan_session_id", sessionId)
        .order("id")
        .range(offset, offset + pageSize - 1);
      if (scansError) return json({ success: false, message: scansError.message }, 500);
      records.push(...(scans || []));
      if (!scans || scans.length < pageSize) break;
    }

    if (records.length === 0) {
      return json({ success: false, message: "This session has no saved scans to summarize." }, 409);
    }

    const counts = { healthy: 0, downy: 0, powdery: 0, septoria: 0 };
    const confidenceValues: number[] = [];
    const diseaseConfidence: Record<keyof typeof counts, number[]> = {
      healthy: [],
      downy: [],
      powdery: [],
      septoria: [],
    };

    for (const scan of records) {
      const name = scanClass(scan.disease_name);
      const key = Object.hasOwn(countKeys, name) ? countKeys[name as keyof typeof countKeys] : null;
      if (key) counts[key]++;

      const confidence = scanConfidencePercent(scan.confidence_score);
      if (confidence !== null) {
        confidenceValues.push(confidence);
        if (key) diseaseConfidence[key].push(confidence / 100);
      }
    }

    const mean = (values: number[]) => values.length
      ? values.reduce((sum, value) => sum + value, 0) / values.length
      : 0;
    const totalScanned = records.length;
    const riskCount = totalScanned - counts.healthy;
    const percent = (count: number) => totalScanned ? count / totalScanned * 100 : 0;
    let completedAt = scanSession.completed_at || new Date().toISOString();

    if (scanSession.status === "active") {
      const { data: updated, error: updateError } = await userClient
      .from("scan_sessions")
      .update({
        completed_at: completedAt,
        total_scanned: totalScanned,
        healthy_count: counts.healthy,
        not_healthy_count: riskCount,
        downy_mildew_count: counts.downy,
        powdery_mildew_count: counts.powdery,
        septoria_blight_count: counts.septoria,
        healthy_percentage: percent(counts.healthy),
        not_healthy_percentage: percent(riskCount),
        healthy_avg_confidence: mean(diseaseConfidence.healthy),
        downy_avg_confidence: mean(diseaseConfidence.downy),
        powdery_avg_confidence: mean(diseaseConfidence.powdery),
        septoria_avg_confidence: mean(diseaseConfidence.septoria),
        status: "completed",
      })
      .eq("id", sessionId)
      .eq("user_id", user.id)
      .eq("status", "active")
      .select("completed_at")
      .maybeSingle();
      if (updateError) return json({ success: false, message: updateError.message }, 500);
      if (!updated) {
        const { data: saved, error } = await userClient
          .from("scan_sessions")
          .select("completed_at")
          .eq("id", sessionId)
          .eq("user_id", user.id)
          .eq("status", "completed")
          .maybeSingle();
        if (error || !saved?.completed_at) {
          return json({ success: false, message: "Could not confirm the completed session." }, 409);
        }
        completedAt = saved.completed_at;
      }
    }

    return json({
      success: true,
      summary: {
        total_scanned: totalScanned,
        healthy_count: counts.healthy,
        risk_count: riskCount,
        downy_mildew_count: counts.downy,
        powdery_mildew_count: counts.powdery,
        septoria_blight_count: counts.septoria,
        average_confidence: confidenceValues.length ? mean(confidenceValues) : null,
        completed_at: completedAt,
      },
    });
  } catch (error) {
    console.error("GreenGuard scan session error:", error);
    return json({
      success: false,
      message: error instanceof Error ? error.message : "Could not finish the scan session.",
    }, 500);
  }
}
