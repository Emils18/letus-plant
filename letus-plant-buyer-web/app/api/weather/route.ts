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

  const locationsToTry = [
    requestedLocation,
    "Lapu-Lapu City, Cebu, PH",
    "Cebu City, PH",
    "Mandaue City, PH",
  ].filter(Boolean);

  let lastError = "Unable to load weather data.";

  for (const location of locationsToTry) {
    try {
      const url = new URL("https://api.weatherapi.com/v1/current.json");
      url.searchParams.set("key", apiKey);
      url.searchParams.set("q", location);
      url.searchParams.set("aqi", "no");

      const response = await fetch(url.toString(), {
        cache: "no-store",
      });

      const data = await response.json();

      if (!response.ok || data.error) {
        lastError = data.error?.message || `Failed for ${location}`;
        continue;
      }

      const fullText = data.current?.condition?.text || "Unknown";

      // Separate Condition and Description
      const condition = fullText.split(" ")[0]; // e.g. "Patchy", "Light", "Cloudy"
      const description = fullText;             // Full detailed text

      return json({
        success: true,
        data: {
          location: `${data.location?.name || location}, ${data.location?.country || "PH"}`,
          temperature: Number(data.current?.temp_c || 0),
          condition: condition,
          description: description,
          humidity: Number(data.current?.humidity || 0),
          windSpeed: Number(data.current?.wind_kph || 0) / 3.6,
          updatedAt: data.current?.last_updated 
            ? new Date(data.current.last_updated).toISOString() 
            : new Date().toISOString(),
        },
      });
    } catch (error) {
      lastError = error instanceof Error ? error.message : "Unknown error";
    }
  }

  return json(
    {
      success: false,
      message: lastError,
    },
    502
  );
}