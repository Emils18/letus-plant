import { createClient } from "@supabase/supabase-js";
import { NextRequest, NextResponse } from "next/server";
import { scanConfidencePercent, scanGuidance } from "@/lib/scan-guidance";

function json(data: unknown, status = 200) {
  return NextResponse.json(data, { status, headers: { "Cache-Control": "no-store" } });
}

export async function POST(request: NextRequest) {
  try {
    const token = (request.headers.get("authorization") || "")
      .replace(/^Bearer\s+/i, "")
      .trim();

    if (!token) {
      return json({
        success: false,
        message: "Please sign in before scanning.",
      }, 401);
    }

    const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL;
    const anonKey = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;

    if (!supabaseUrl || !anonKey) {
      return json({
        success: false,
        message: "Database configuration is missing.",
      }, 500);
    }

    const userClient = createClient(supabaseUrl, anonKey, {
      auth: {
        persistSession: false,
        autoRefreshToken: false,
      },
      global: {
        headers: {
          Authorization: `Bearer ${token}`,
        },
      },
    });

    const {
      data: { user },
      error: authError,
    } = await userClient.auth.getUser(token);

    if (authError || !user) {
      return json({
        success: false,
        message: "Your session expired. Please sign in again.",
      }, 401);
    }

    const {
      data: profile,
      error: profileError,
    } = await userClient
      .from("users")
      .select("role")
      .eq("id", user.id)
      .maybeSingle();

    if (profileError) {
      return json({
        success: false,
        message: profileError.message,
      }, 500);
    }

    if (
      String(profile?.role || user.user_metadata?.role || "")
        .toLowerCase() !== "farmer"
    ) {
      return json({
        success: false,
        message: "Disease scanning is available to farmer accounts.",
      }, 403);
    }

    const form = await request.formData();
    const image = form.get("image");
    const requestedSessionId = String(
      form.get("scan_session_id") || "",
    ).trim();

    if (
      !(image instanceof File) ||
      !image.type.startsWith("image/") ||
      image.size === 0 ||
      image.size > 12 * 1024 * 1024
    ) {
      return json({
        success: false,
        message: "Choose a valid image under 12 MB.",
      }, 400);
    }

    if (requestedSessionId) {
      const { data: activeSession, error: sessionError } = await userClient
        .from("scan_sessions")
        .select("id, status")
        .eq("id", requestedSessionId)
        .eq("user_id", user.id)
        .maybeSingle();

      if (sessionError) {
        return json({ success: false, message: `Could not verify the scan session: ${sessionError.message}` }, 500);
      }

      if (!activeSession || String(activeSession.status || "").toLowerCase() !== "active") {
        return json({
          success: false,
          message: "This scan session is no longer active. Refresh the page and start a new session.",
        }, 409);
      }
    }

    // Connect to the existing GreenGuard AI model.
    const servers = [
      process.env.GREENGUARD_AI_URL,
      "http://192.168.254.192:5000",
      "http://192.168.254.143:5000",
    ].filter((value): value is string => Boolean(value));

    let diagnosis: Record<string, unknown> | null = null;

    let lastError =
      "GreenGuard AI could not be reached. Check GREENGUARD_AI_URL and the AI server.";

    for (const server of [...new Set(servers)]) {
      try {
        const health = await fetch(`${server}/health`, {
          cache: "no-store",
          signal: AbortSignal.timeout(4000),
        });

        const healthData = await health.json();

        if (
          !health.ok ||
          healthData.online !== true ||
          healthData.model_loaded !== true
        ) {
          continue;
        }

        const body = new FormData();
        body.set("image", image, image.name || "lettuce.jpg");

        const response = await fetch(`${server}/scan`, {
          method: "POST",
          body,
          cache: "no-store",
          signal: AbortSignal.timeout(90000),
        });

        const result = await response.json();

        if (
          !response.ok ||
          result.success !== true ||
          result.diagnosis_available !== true ||
          !result.result
        ) {
          lastError =
            result.message ||
            "The AI could not produce a diagnosis. Try a clearer lettuce photo.";

          continue;
        }

        diagnosis = result.result as Record<string, unknown>;
        break;
      } catch {
        // Try the next configured AI server.
      }
    }

    if (!diagnosis) {
      return json({
        success: false,
        message: lastError,
      }, 502);
    }

    // Preserve the actual confidence returned by the AI model.
    const rawConfidence = diagnosis.confidence;
    const confidencePercent = typeof rawConfidence === "number" || typeof rawConfidence === "string"
      ? scanConfidencePercent(rawConfidence)
      : null;
    if (confidencePercent === null) {
      return json({
        success: false,
        message: "The AI returned an invalid confidence value.",
      }, 502);
    }
    const confidence = confidencePercent / 100;

    const diseaseName = String(
      diagnosis.display_name ||
      diagnosis.class_name ||
      "Unknown Result"
    ).replaceAll("_", " ").trim();

    const guidance = scanGuidance(diseaseName) || {
      pathogen_name: "Not available",
      disease_description:
        "This result is not one of GreenGuard AI's four supported model classes.",
      pathogen_description:
        "No supported pathogen description is available for this result.",
      treatment_recommendations: [
        "Do not apply a disease-specific treatment based only on this result.",
        "Capture a clearer lettuce photo and scan again.",
        "Request an assessment from a local agricultural technician if the result remains unclear.",
      ],
      selling_recommendation: "Hold for manual inspection",
      selling_explanation:
        "Do not use an unsupported result alone to decide whether lettuce is suitable for sale.",
    };

    // Save the captured image.
    const now = new Date().toISOString();

    const safeFileName = image.name.replace(
      /[^a-zA-Z0-9._-]/g,
      "_"
    );

    const storagePath =
      `${user.id}/web_${Date.now()}_${safeFileName}`;

    let imageUrl: string | null = null;

    const { error: uploadError } = await userClient.storage
      .from("diagnostic-images")
      .upload(storagePath, image, {
        contentType: image.type,
        upsert: true,
      });

    if (!uploadError) {
      imageUrl = userClient.storage
        .from("diagnostic-images")
        .getPublicUrl(storagePath)
        .data.publicUrl;
    } else {
      console.warn(
        "Diagnostic image upload failed:",
        uploadError.message
      );
    }

    const textField = (key: string) => {
      const value = form.get(key);
      return typeof value === "string" ? value.trim().slice(0, 160) : "";
    };
    const location = textField("location");
    const weatherCondition = textField("weather_condition");
    const temperatureText = textField("temperature");
    const temperature = temperatureText === "" ? null : Number(temperatureText);

    let scanSessionId = requestedSessionId;
    if (!scanSessionId) {
      const { data: session, error: sessionError } = await userClient
        .from("scan_sessions")
        .insert({
          user_id: user.id,
          started_at: now,
          status: "active",
        })
        .select("id")
        .single();

      if (sessionError || !session?.id) {
        return json({
          success: false,
          message: `Diagnosis completed but the scan session could not be started: ${sessionError?.message || "session ID missing"}`,
        }, 500);
      }
      scanSessionId = String(session.id);
    }

    // Save the diagnosis and its recommendation snapshot together.
    const record = {
      user_id: user.id,
      scan_session_id: scanSessionId,
      disease_name: diseaseName,
      confidence_score: confidence,
      pathogen_name: guidance.pathogen_name,
      disease_description: guidance.disease_description,
      pathogen_description: guidance.pathogen_description,
      treatment_recommendations:
        guidance.treatment_recommendations,
      selling_recommendation:
        guidance.selling_recommendation,
      selling_explanation:
        guidance.selling_explanation,
      ...(location ? { location } : {}),
      ...(weatherCondition ? { weather_condition: weatherCondition } : {}),
      ...(temperature !== null && Number.isFinite(temperature) ? { temperature } : {}),
      device_id: "GreenGuard-Web-Scan",
      captured_at: now,
      created_at: now,
      ...(imageUrl ? { image_url: imageUrl } : {}),
    };

    const { error: saveError } = await userClient
      .from("diagnostic_logs")
      .insert(record);

    if (saveError) {
      return json({
        success: false,
        message:
          `Diagnosis ready but could not save the health log: ${saveError.message}`,
      }, 500);
    }

    return json({
      success: true,
      disease_name: diseaseName,
      confidence_score: confidence,
      confidence_percent: confidencePercent,
      image_saved: Boolean(imageUrl),
      scan_session_id: scanSessionId,
      record: {
        ...record,
        treatment_recommendations:
          guidance.treatment_recommendations,
      },
    });
  } catch (error) {
    console.error("GreenGuard scan API error:", error);

    return json({
      success: false,
      message:
        error instanceof Error
          ? error.message
          : "An unexpected error occurred while scanning.",
    }, 500);
  }
}
