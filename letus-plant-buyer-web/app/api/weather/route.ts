import { NextRequest, NextResponse } from "next/server";

function json(data: unknown, status = 200) {
  return NextResponse.json(data, {
    status,
    headers: {
      "Cache-Control": "no-store, max-age=0",
    },
  });
}

export async function GET(request: NextRequest) {
  const apiKey = "b0c48f9b43c44a919de41229260407";

  const requestedLocation = String(
    request.nextUrl.searchParams.get("location") || ""
  ).trim();

  // Priority locations for Lapu-Lapu / Cebu
  const locationsToTry = [
    requestedLocation,
    "Lapu-Lapu City, Cebu, Philippines",
    "Lapu-Lapu City",
    "Cebu City, Philippines",
    "Mandaue City, Cebu",
    "Cebu, Philippines",
  ].filter(Boolean);

  let lastError = "Unable to load weather data.";

  for (const location of locationsToTry) {
    try {
      const url = new URL("https://api.weatherapi.com/v1/current.json");
      url.searchParams.set("key", apiKey);
      url.searchParams.set("q", location);
      url.searchParams.set("aqi", "no");

      const response = await fetch(url.toString(), { cache: "no-store" });

      const data = await response.json();

      if (!response.ok || data.error) {
        lastError = data.error?.message || `Failed for ${location}`;
        continue;
      }

      const fullText = data.current?.condition?.text || "Unknown";

      return json({
        success: true,
        data: {
          location: `${data.location?.name || "Lapu-Lapu City"}, Cebu`,
          temperature: Number(data.current?.temp_c || 0),
          condition: fullText.split(",")[0].trim(), // e.g. "Clear", "Cloudy"
          description: fullText,
          humidity: Number(data.current?.humidity || 0),
          windSpeed: Number(data.current?.wind_kph || 0) / 3.6, // to m/s
          updatedAt: new Date().toISOString(),
        },
      });
    } catch (error) {
      lastError = error instanceof Error ? error.message : "Unknown error";
    }
  }

  return json({
    success: false,
    message: lastError,
  }, 502);
}