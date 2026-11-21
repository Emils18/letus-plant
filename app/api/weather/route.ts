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

  if (!requestedLocation || requestedLocation.length > 160) {
    return json({ success: false, message: "Choose a location to see weather." }, 400);
  }

  try {
    const url = new URL("https://api.weatherapi.com/v1/forecast.json");
    url.searchParams.set("key", process.env.WEATHER_API_KEY || apiKey);
    url.searchParams.set("q", requestedLocation);
    url.searchParams.set("days", "1");
    url.searchParams.set("aqi", "no");
    url.searchParams.set("alerts", "no");
    const response = await fetch(url, { cache: "no-store", signal: AbortSignal.timeout(10000) });
    const data = await response.json();
    const current = data.current;
    const forecast = data.forecast?.forecastday?.[0]?.day;
    if (!response.ok || !data.location?.name || !current?.condition?.text ||
        ![current.temp_c, current.humidity, current.wind_kph,
          forecast?.daily_chance_of_rain, forecast?.mintemp_c, forecast?.maxtemp_c].every(Number.isFinite)) {
      return json({ success: false, message: "Weather data is unavailable for this location." }, 502);
    }

    return json({
      success: true,
      data: {
        location: [...new Set([data.location.name, data.location.region].filter(Boolean))].join(", "),
        temperature: current.temp_c,
        condition: current.condition.text,
        description: current.condition.text,
        humidity: current.humidity,
        windSpeed: current.wind_kph / 3.6,
        rainChance: forecast.daily_chance_of_rain,
        forecast: `${forecast.mintemp_c}°C to ${forecast.maxtemp_c}°C · ${forecast.condition?.text || ""}`.replace(/ · $/, ""),
        updatedAt: current.last_updated || null,
      },
    });
  } catch {
    return json({ success: false, message: "The weather service could not be reached. Try again shortly." }, 502);
  }
}
