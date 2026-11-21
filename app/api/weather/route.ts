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

  const rawLatitude = request.nextUrl.searchParams.get("latitude");
  const rawLongitude = request.nextUrl.searchParams.get("longitude");
  const latitude = Number(rawLatitude);
  const longitude = Number(rawLongitude);
  if (
    !rawLatitude?.trim() || !rawLongitude?.trim() ||
    !Number.isFinite(latitude) || latitude < -90 || latitude > 90 ||
    !Number.isFinite(longitude) || longitude < -180 || longitude > 180
  ) {
    return json({ success: false, message: "Location unavailable. Allow location access and try again." }, 400);
  }

  try {
      const url = new URL("https://api.weatherapi.com/v1/forecast.json");
      url.searchParams.set("key", apiKey);
      url.searchParams.set("q", `${latitude},${longitude}`);
      url.searchParams.set("days", "1");
      url.searchParams.set("aqi", "no");
      url.searchParams.set("alerts", "no");

      const response = await fetch(url.toString(), { cache: "no-store" });

      const data = await response.json();

      if (!response.ok || data.error) {
        return json({ success: false, message: data.error?.message || "Unable to load weather for your current location." }, 502);
      }

      const temperature = Number(data.current?.temp_c);
      const humidity = Number(data.current?.humidity);
      const windSpeed = Number(data.current?.wind_kph);
      if (!Number.isFinite(temperature) || !Number.isFinite(humidity) || !Number.isFinite(windSpeed)) {
        return json({ success: false, message: "Weather details are unavailable for your current location." }, 502);
      }
      const fullText = data.current?.condition?.text || "Unknown";
      if (fullText === "Unknown") {
        return json({ success: false, message: "Weather condition is unavailable for your current location." }, 502);
      }
      const rawRainChance = data.forecast?.forecastday?.[0]?.day?.daily_chance_of_rain;
      const rainChance = rawRainChance != null && rawRainChance !== "" && Number.isFinite(Number(rawRainChance))
        ? Number(rawRainChance)
        : null;
      const providerLocation = [data.location?.name, data.location?.region, data.location?.country]
        .filter((part) => typeof part === "string" && part.trim())
        .join(", ");

      return json({
        success: true,
        data: {
          location: providerLocation || "Location name unavailable",
          temperature,
          condition: fullText.split(",")[0].trim(), // e.g. "Clear", "Cloudy"
          description: fullText,
          humidity,
          windSpeed: windSpeed / 3.6, // to m/s
          rainChance,
          updatedAt: data.current?.last_updated || null,
          timeZone: data.location?.tz_id || null,
          fetchedAt: new Date().toISOString(),
        },
      });
  } catch (error) {
    return json({ success: false, message: error instanceof Error ? error.message : "Unable to load weather for your current location." }, 502);
  }
}
