"use client";

import {
  useCallback,
  useEffect,
  useMemo,
  useState,
} from "react";

import { supabase } from "@/lib/supabase";

type HealthLog = {
  id: string;
  user_id?: string | null;
  image_url?: string | null;
  disease_name?: string | null;
  result?: string | null;
  confidence_score?: number | string | null;
  confidence?: number | string | null;
  temperature?: number | string | null;
  temp?: number | string | null;
  weather_condition?: string | null;
  weather?: string | null;
  location?: string | null;
  device_id?: string | null;
  captured_at?: string | null;
  created_at?: string | null;
};

type UserProfile = {
  id: string;
  role: string;
  full_name?: string | null;
};

type FarmerProduct = {
  id: number | string;
  stock?: number | string | null;
  location?: string | null;
};

type FarmerOrder = {
  id: string;
  status?: string | null;
};

type WeatherData = {
  location: string;
  temperature: number;
  condition: string;
  description: string;
  humidity: number;
  windSpeed: number;
  updatedAt: string;
};

type FarmerNotice = {
  id: string;
  title: string;
  message: string;
  tone: "warning" | "danger" | "info" | "success";
};

function GreenGuardIcon({
  className = "h-10 w-10",
}: {
  className?: string;
}) {
  return (
    <svg
      viewBox="0 0 100 100"
      className={className}
      fill="none"
      xmlns="http://www.w3.org/2000/svg"
    >
      <path
        d="M50 6C61 16 73 20 87 22V47C87 70 72 86 50 94C28 86 13 70 13 47V22C27 20 39 16 50 6Z"
        fill="white"
        stroke="#5DBB3F"
        strokeWidth="6"
        strokeLinejoin="round"
      />

      <path
        d="M50 22C59 31 67 43 64 57C61 68 55 74 50 80C45 74 39 68 36 57C33 43 41 31 50 22Z"
        fill="#67C839"
      />

      <path
        d="M36 39C27 39 20 47 20 56C20 67 31 74 47 81C42 70 38 58 36 39Z"
        fill="#1FA33F"
      />

      <path
        d="M64 39C73 39 80 47 80 56C80 67 69 74 53 81C58 70 62 58 64 39Z"
        fill="#169A3A"
      />

      <path
        d="M50 34V79"
        stroke="white"
        strokeWidth="5"
        strokeLinecap="round"
      />

      <path
        d="M35 46C40 59 46 70 50 79"
        stroke="white"
        strokeWidth="5"
        strokeLinecap="round"
      />

      <path
        d="M65 46C60 59 54 70 50 79"
        stroke="white"
        strokeWidth="5"
        strokeLinecap="round"
      />
    </svg>
  );
}

function readText(
  log: HealthLog,
  keys: Array<keyof HealthLog>,
  fallback: string
) {
  for (const key of keys) {
    const value = log[key];

    if (
      value !== null &&
      value !== undefined &&
      String(value).trim() !== ""
    ) {
      return String(value);
    }
  }

  return fallback;
}

function getDiseaseName(log: HealthLog) {
  return readText(
    log,
    ["disease_name", "result"],
    "Unknown Result"
  );
}

function getConfidence(log: HealthLog) {
  const raw =
    log.confidence_score ??
    log.confidence;

  if (raw === null || raw === undefined) {
    return "N/A";
  }

  const value = Number(raw);

  if (Number.isNaN(value)) {
    return String(raw);
  }

  if (value <= 1) {
    return `${(value * 100).toFixed(1)}%`;
  }

  return `${value.toFixed(1)}%`;
}

function getTemperature(log: HealthLog) {
  const raw =
    log.temperature ??
    log.temp;

  if (raw === null || raw === undefined) {
    return "N/A";
  }

  const value = Number(raw);

  if (Number.isNaN(value)) {
    return String(raw);
  }

  return `${value.toFixed(1)}°C`;
}

function getDate(log: HealthLog) {
  const raw =
    log.captured_at ||
    log.created_at;

  if (!raw) {
    return "No date";
  }

  const date = new Date(raw);

  if (Number.isNaN(date.getTime())) {
    return raw;
  }

  return date.toLocaleString();
}

function formatWeatherTime(
  value?: string | null
) {
  if (!value) {
    return "Not updated yet";
  }

  const date = new Date(value);

  if (Number.isNaN(date.getTime())) {
    return value;
  }

  return date.toLocaleString();
}

function isHealthy(name: string) {
  const value = name.toLowerCase();

  return (
    value.includes("healthy") ||
    value.includes("none") ||
    value.includes("no disease")
  );
}

function isUsefulLocation(
  value?: string | null
) {
  const location =
    String(value || "").trim();

  const normalized =
    location.toLowerCase();

  if (!location) {
    return false;
  }

  return ![
    "n/a",
    "unknown",
    "local farm",
    "farm pickup",
    "no location",
  ].includes(normalized);
}

function noticeToneClass(
  tone: FarmerNotice["tone"]
) {
  if (tone === "danger") {
    return "border-red-400/25 bg-red-400/10 text-red-200";
  }

  if (tone === "warning") {
    return "border-amber-400/25 bg-amber-400/10 text-amber-200";
  }

  if (tone === "success") {
    return "border-[#5DBB63]/25 bg-[#5DBB63]/10 text-[#9BE49F]";
  }

  return "border-blue-400/25 bg-blue-400/10 text-blue-200";
}

export default function HealthLogsPage() {
  const [loading, setLoading] =
    useState(true);

  const [
    weatherLoading,
    setWeatherLoading,
  ] = useState(false);

  const [logs, setLogs] =
    useState<HealthLog[]>([]);

  const [profile, setProfile] =
    useState<UserProfile | null>(null);

  const [
    farmerProducts,
    setFarmerProducts,
  ] = useState<FarmerProduct[]>([]);

  const [
    farmerOrders,
    setFarmerOrders,
  ] = useState<FarmerOrder[]>([]);

  const [weather, setWeather] =
    useState<WeatherData | null>(null);

  const [
    weatherError,
    setWeatherError,
  ] = useState("");

  const [search, setSearch] =
    useState("");

  const isFarmer =
    String(profile?.role || "").toLowerCase() ===
    "farmer";

  const weatherLocation = useMemo(() => {
    const logLocation =
      logs.find((log) =>
        isUsefulLocation(log.location)
      )?.location;

    const productLocation =
      farmerProducts.find((product) =>
        isUsefulLocation(product.location)
      )?.location;

    return String(
      logLocation ||
        productLocation ||
        "Lapu-Lapu City, Cebu, PH"
    ).trim();
  }, [farmerProducts, logs]);

  const loadWeather = useCallback(
    async (
      location: string,
      showError = true
    ) => {
      setWeatherLoading(true);

      try {
        const response = await fetch(
          `/api/weather?location=${encodeURIComponent(
            location
          )}`,
          {
            cache: "no-store",
          }
        );

        const result =
          await response.json();

        if (
          !response.ok ||
          !result.success
        ) {
          throw new Error(
            result.message ||
              "Unable to load live weather."
          );
        }

        setWeather(
          result.data as WeatherData
        );

        setWeatherError("");
      } catch (error) {
        const message =
          error instanceof Error
            ? error.message
            : "Unable to load live weather.";

        setWeatherError(message);

        if (showError) {
          alert(message);
        }
      } finally {
        setWeatherLoading(false);
      }
    },
    []
  );

  const loadLogs =
    useCallback(async () => {
      setLoading(true);

      try {
        const {
          data: { session },
        } =
          await supabase.auth.getSession();

        if (!session?.user) {
          throw new Error(
            "Please login first."
          );
        }

        const {
          data: userProfile,
          error: profileError,
        } = await supabase
          .from("users")
          .select(
            "id, role, full_name"
          )
          .eq("id", session.user.id)
          .maybeSingle();

        if (profileError) {
          throw new Error(
            profileError.message
          );
        }

        const currentProfile =
          userProfile as UserProfile | null;

        const currentRole =
          String(
            currentProfile?.role || ""
          ).toLowerCase();

        setProfile(currentProfile);

        if (currentRole === "farmer") {
          const [
            logsResult,
            productsResult,
            ordersResult,
          ] = await Promise.all([
            supabase
              .from(
                "diagnostic_logs"
              )
              .select("*")
              .eq(
                "user_id",
                session.user.id
              )
              .order("created_at", {
                ascending: false,
              }),

            supabase
              .from("products")
              .select(
                "id, stock, location"
              )
              .eq(
                "farmer_id",
                session.user.id
              )
              .order("created_at", {
                ascending: false,
              }),

            supabase
              .from("orders")
              .select("id, status")
              .eq(
                "farmer_id",
                session.user.id
              )
              .order("created_at", {
                ascending: false,
              }),
          ]);

          if (logsResult.error) {
            throw new Error(
              logsResult.error.message
            );
          }

          if (productsResult.error) {
            throw new Error(
              productsResult.error.message
            );
          }

          if (ordersResult.error) {
            throw new Error(
              ordersResult.error.message
            );
          }

          setLogs(
            (logsResult.data as HealthLog[]) ||
              []
          );

          setFarmerProducts(
            (productsResult.data as FarmerProduct[]) ||
              []
          );

          setFarmerOrders(
            (ordersResult.data as FarmerOrder[]) ||
              []
          );
        } else {
          const {
            data,
            error,
          } = await supabase
            .from("diagnostic_logs")
            .select("*")
            .order("created_at", {
              ascending: false,
            });

          if (error) {
            throw new Error(
              error.message
            );
          }

          setLogs(
            (data as HealthLog[]) || []
          );

          setFarmerProducts([]);

          setFarmerOrders([]);

          setWeather(null);

          setWeatherError("");
        }
      } catch (error) {
        alert(
          error instanceof Error
            ? error.message
            : "Failed to load health logs."
        );
      } finally {
        setLoading(false);
      }
    }, []);

  useEffect(() => {
    loadLogs();
  }, [loadLogs]);

  useEffect(() => {
    if (!isFarmer) {
      return;
    }

    loadWeather(weatherLocation);

    const intervalId =
      window.setInterval(() => {
        loadWeather(
          weatherLocation,
          false
        );
      }, 10 * 60 * 1000);

    return () =>
      window.clearInterval(intervalId);
  }, [
    isFarmer,
    loadWeather,
    weatherLocation,
  ]);

  const filteredLogs = useMemo(() => {
    const query =
      search.toLowerCase();

    return logs.filter((log) => {
      return (
        getDiseaseName(log)
          .toLowerCase()
          .includes(query) ||

        readText(
          log,
          [
            "weather_condition",
            "weather",
          ],
          ""
        )
          .toLowerCase()
          .includes(query) ||

        readText(
          log,
          ["location"],
          ""
        )
          .toLowerCase()
          .includes(query)
      );
    });
  }, [logs, search]);

  const healthyCount =
    logs.filter((log) =>
      isHealthy(
        getDiseaseName(log)
      )
    ).length;

  const riskCount =
    logs.length - healthyCount;

  const recentLogs =
    logs.slice(0, 3);

  const latestLog =
    logs[0];

  const pendingOrderCount =
    farmerOrders.filter(
      (order) =>
        String(
          order.status || ""
        ).toLowerCase() ===
        "pending"
    ).length;

  const lowStockCount =
    farmerProducts.filter(
      (product) =>
        Number(product.stock || 0) <=
        5
    ).length;

  const farmerNotices =
    useMemo<FarmerNotice[]>(() => {
      const notices:
        FarmerNotice[] = [];

      if (weather) {
        const weatherText =
          `${weather.condition} ${weather.description}`.toLowerCase();

        if (weather.humidity >= 75) {
          notices.push({
            id: "humidity",
            title:
              "Weather Advisory",
            message:
              "High humidity detected. Monitor lettuce leaves for fungal disease symptoms.",
            tone: "warning",
          });
        }

        if (
          weatherText.includes("rain")
        ) {
          notices.push({
            id: "rain",
            title: "Rain Advisory",
            message:
              "Rain is detected. Avoid unnecessary watering and check farm drainage.",
            tone: "info",
          });
        }

        if (
          weatherText.includes("cloud")
        ) {
          notices.push({
            id: "cloudy",
            title:
              "Leaf Moisture Advisory",
            message:
              "Cloudy conditions today. Inspect leaves for prolonged moisture.",
            tone: "info",
          });
        }

        if (
          weather.temperature >= 30
        ) {
          notices.push({
            id: "heat",
            title: "Heat Advisory",
            message:
              "High temperature detected. Water during cooler hours and monitor heat stress.",
            tone: "warning",
          });
        }
      }

      if (latestLog) {
        const disease =
          getDiseaseName(latestLog);

        const isKnownResult =
          !disease
            .toLowerCase()
            .includes("unknown");

        if (
          isKnownResult &&
          !isHealthy(disease)
        ) {
          notices.push({
            id: "disease",
            title:
              "Disease Detection",
            message: `Disease alert: ${disease} was detected. Inspect nearby plants.`,
            tone: "danger",
          });
        }
      }

      if (
        pendingOrderCount > 0
      ) {
        notices.push({
          id: "orders",
          title: "Buyer Orders",
          message: `You have ${pendingOrderCount} pending buyer order${
            pendingOrderCount === 1
              ? ""
              : "s"
          }.`,
          tone: "info",
        });
      }

      if (lowStockCount > 0) {
        notices.push({
          id: "stock",
          title: "Low Stock",
          message: `${lowStockCount} product${
            lowStockCount === 1
              ? " has"
              : "s have"
          } low stock. Review your listings.`,
          tone: "warning",
        });
      }

      if (
        notices.length === 0
      ) {
        notices.push({
          id: "clear",
          title: "Farm Status",
          message:
            "No urgent weather, disease, order, or stock notices right now.",
          tone: "success",
        });
      }

      return notices;
    }, [
      latestLog,
      lowStockCount,
      pendingOrderCount,
      weather,
    ]);

  async function handleRefreshAll() {
    await loadLogs();

    if (isFarmer) {
      await loadWeather(
        weatherLocation
      );
    }
  }

  if (loading) {
    return (
      <main className="flex min-h-screen items-center justify-center bg-[#07100B] text-white">
        <div className="text-center">
          <div className="mx-auto mb-5 h-14 w-14 animate-spin rounded-full border-4 border-[#5DBB63]/20 border-t-[#5DBB63]" />

          <p className="text-sm font-black uppercase tracking-[4px] text-[#5DBB63]">
            Loading Health Logs
          </p>
        </div>
      </main>
    );
  }

  return (
    <main className="min-h-screen bg-[#07100B] pb-24 text-white">
      <div className="pointer-events-none fixed inset-0 overflow-hidden">
        <div className="absolute -left-[18%] top-[-18%] h-[720px] w-[720px] rounded-full bg-[#5DBB63]/15 blur-[140px]" />

        <div className="absolute -right-[18%] bottom-[-22%] h-[820px] w-[820px] rounded-full bg-[#2F6B3B]/20 blur-[170px]" />
      </div>

      <header className="sticky top-0 z-50 border-b border-white/10 bg-[#07100B]/75 px-6 py-5 shadow-2xl shadow-black/20 backdrop-blur-2xl">
        <div className="mx-auto flex max-w-[1200px] items-center justify-between">
          <div className="flex items-center gap-4">
            <div className="flex h-12 w-12 items-center justify-center rounded-2xl bg-white shadow-[0_0_35px_rgba(93,187,99,0.35)]">
              <GreenGuardIcon className="h-10 w-10" />
            </div>

            <div>
              <h1 className="text-2xl font-black tracking-tighter">
                Health Logs
              </h1>

              <p className="text-[10px] font-bold uppercase tracking-[3px] text-[#5DBB63]">
                GreenGuard AI
              </p>
            </div>
          </div>

          <button
            onClick={
              handleRefreshAll
            }
            disabled={
              loading ||
              weatherLoading
            }
            className="rounded-2xl border border-[#5DBB63]/30 bg-[#5DBB63]/10 px-5 py-2.5 text-sm font-black text-[#5DBB63] transition hover:bg-[#5DBB63] hover:text-[#07100B] disabled:opacity-60"
          >
            {loading ||
            weatherLoading
              ? "Refreshing..."
              : "Refresh"}
          </button>
        </div>
      </header>

      <div className="relative z-10 mx-auto w-full max-w-[1200px] px-6 pt-10">
        <section className="mb-10 rounded-[2rem] border border-[#5DBB63]/20 bg-gradient-to-br from-[#132019]/95 via-[#0D1711]/95 to-[#07100B]/95 p-10 shadow-2xl shadow-black/30">
          <div className="mb-5 inline-flex rounded-full border border-[#5DBB63]/20 bg-[#5DBB63]/10 px-4 py-2 text-xs font-black uppercase tracking-[3px] text-[#5DBB63]">
            Scan History / Health Logs
          </div>

          <h2 className="text-5xl font-black tracking-tighter">
            Crop Health Monitoring
          </h2>

          <p className="mt-4 max-w-3xl text-lg text-white/55">
            Review prototype/demo
            lettuce scan records,
            disease results,
            confidence scores, live
            weather, and monitoring
            history. Real ESP32-CAM
            integration is still under
            development.
          </p>

          <p className="mt-3 text-sm text-white/35">
            Current role:{" "}
            {profile?.role ||
              "Unknown"}
          </p>
        </section>

        <section className="mb-8 grid grid-cols-1 gap-5 md:grid-cols-3">
          <div className="rounded-[1.7rem] border border-white/10 bg-white/[0.035] p-6">
            <p className="text-4xl font-black text-white">
              {logs.length}
            </p>

            <p className="mt-1 text-xs font-bold uppercase tracking-[2px] text-white/40">
              Total Logs
            </p>
          </div>

          <div className="rounded-[1.7rem] border border-white/10 bg-white/[0.035] p-6">
            <p className="text-4xl font-black text-[#5DBB63]">
              {healthyCount}
            </p>

            <p className="mt-1 text-xs font-bold uppercase tracking-[2px] text-white/40">
              Healthy Results
            </p>
          </div>

          <div className="rounded-[1.7rem] border border-white/10 bg-white/[0.035] p-6">
            <p className="text-4xl font-black text-orange-300">
              {riskCount}
            </p>

            <p className="mt-1 text-xs font-bold uppercase tracking-[2px] text-white/40">
              Risk Results
            </p>
          </div>
        </section>

        <section className="mb-8 rounded-[2rem] border border-white/10 bg-white/[0.035] p-7 shadow-2xl shadow-black/20 backdrop-blur-xl">
          <div className="mb-5">
            <h3 className="text-2xl font-black tracking-tight">
              Recent Scan Records
            </h3>

            <p className="mt-1 text-sm text-white/45">
              Latest prototype/demo
              diagnostic records for
              this monitoring view.
            </p>
          </div>

          {recentLogs.length ===
          0 ? (
            <div className="flex min-h-[180px] items-center justify-center rounded-3xl border border-dashed border-white/10 bg-black/10 text-sm text-white/40">
              No recent scan records
              found.
            </div>
          ) : (
            <div className="grid gap-4 lg:grid-cols-3">
              {recentLogs.map(
                (log) => {
                  const disease =
                    getDiseaseName(log);

                  const healthy =
                    isHealthy(disease);

                  return (
                    <div
                      key={log.id}
                      className="rounded-[1.5rem] border border-white/10 bg-black/10 p-5"
                    >
                      <div className="flex items-start justify-between gap-3">
                        <div>
                          <p className="text-lg font-black">
                            {disease}
                          </p>

                          <p className="mt-1 text-xs text-white/40">
                            {getDate(
                              log
                            )}
                          </p>
                        </div>

                        <span
                          className={`rounded-full border px-3 py-1 text-[10px] font-black uppercase tracking-[1.5px] ${
                            healthy
                              ? "border-[#5DBB63]/30 bg-[#5DBB63]/10 text-[#5DBB63]"
                              : "border-orange-400/30 bg-orange-400/10 text-orange-300"
                          }`}
                        >
                          {healthy
                            ? "Healthy"
                            : "Risk"}
                        </span>
                      </div>

                      <div className="mt-4 grid gap-2 text-sm text-white/55">
                        <p>
                          Confidence:{" "}
                          <span className="font-black text-[#5DBB63]">
                            {getConfidence(
                              log
                            )}
                          </span>
                        </p>

                        <p>
                          Temperature:{" "}
                          {getTemperature(
                            log
                          )}
                        </p>

                        <p>
                          Location:{" "}
                          {readText(
                            log,
                            ["location"],
                            "N/A"
                          )}
                        </p>
                      </div>
                    </div>
                  );
                }
              )}
            </div>
          )}
        </section>

        {isFarmer && (
          <section className="mb-8 grid gap-6 lg:grid-cols-[0.9fr_1.1fr]">
            <div className="rounded-[2rem] border border-[#5DBB63]/20 bg-gradient-to-br from-[#132019]/95 to-[#0A140E]/95 p-7 shadow-2xl shadow-black/20">
              <div className="flex items-start justify-between gap-4">
                <div>
                  <p className="text-xs font-black uppercase tracking-[3px] text-[#5DBB63]">
                    Live Weather
                  </p>

                  <h3 className="mt-2 text-2xl font-black">
                    {weather?.location ||
                      weatherLocation}
                  </h3>
                </div>

                <button
                  onClick={() =>
                    loadWeather(
                      weatherLocation
                    )
                  }
                  disabled={
                    weatherLoading
                  }
                  className="rounded-2xl border border-[#5DBB63]/30 bg-[#5DBB63]/10 px-4 py-2 text-xs font-black text-[#5DBB63] transition hover:bg-[#5DBB63] hover:text-[#07100B] disabled:opacity-60"
                >
                  {weatherLoading
                    ? "Refreshing..."
                    : "Refresh"}
                </button>
              </div>

              {weather ? (
                <div className="mt-6 grid grid-cols-2 gap-3">
                  <WeatherMetric
                    label="Temperature"
                    value={`${weather.temperature.toFixed(
                      1
                    )}°C`}
                  />

                  <WeatherMetric
                    label="Condition"
                    value={
                      weather.condition
                    }
                  />

                  <WeatherMetric
                    label="Description"
                    value={
                      weather.description
                    }
                    capitalize
                  />

                  <WeatherMetric
                    label="Humidity"
                    value={`${weather.humidity}%`}
                  />

                  <WeatherMetric
                    label="Wind Speed"
                    value={`${weather.windSpeed.toFixed(
                      1
                    )} m/s`}
                  />

                  <WeatherMetric
                    label="Updated"
                    value={formatWeatherTime(
                      weather.updatedAt
                    )}
                  />
                </div>
              ) : (
                <div className="mt-6 rounded-2xl border border-white/10 bg-black/15 p-5 text-sm text-white/50">
                  {weatherLoading
                    ? "Loading live weather..."
                    : weatherError ||
                      "Live weather is not available yet."}
                </div>
              )}
            </div>

            <div className="rounded-[2rem] border border-white/10 bg-white/[0.035] p-7 shadow-2xl shadow-black/20 backdrop-blur-xl">
              <p className="text-xs font-black uppercase tracking-[3px] text-[#5DBB63]">
                Farmer Advisory &
                Notifications
              </p>

              <h3 className="mt-2 text-2xl font-black">
                Live farm notices
              </h3>

              <div className="mt-5 grid gap-3">
                {farmerNotices.map(
                  (notice) => (
                    <div
                      key={
                        notice.id
                      }
                      className={`rounded-2xl border p-4 ${noticeToneClass(
                        notice.tone
                      )}`}
                    >
                      <p className="text-xs font-black uppercase tracking-[2px]">
                        {
                          notice.title
                        }
                      </p>

                      <p className="mt-1 text-sm font-bold leading-6">
                        {
                          notice.message
                        }
                      </p>
                    </div>
                  )
                )}
              </div>
            </div>
          </section>
        )}

        <section className="overflow-hidden rounded-[2rem] border border-white/10 bg-white/[0.035] shadow-2xl shadow-black/20 backdrop-blur-xl">
          <div className="border-b border-white/10 px-8 py-7">
            <div className="flex flex-col gap-4 lg:flex-row lg:items-center lg:justify-between">
              <div>
                <h3 className="text-2xl font-black tracking-tight">
                  Diagnostic Records
                </h3>

                <p className="mt-1 text-sm text-white/45">
                  Buyer view is read-only.
                  Farmer records remain a
                  prototype/demo flow while
                  real ESP32-CAM integration
                  is still under development.
                </p>
              </div>

              <input
                type="text"
                placeholder="Search health logs..."
                value={search}
                onChange={(event) =>
                  setSearch(
                    event.target.value
                  )
                }
                className="w-full rounded-2xl border border-white/10 bg-black/20 px-5 py-3 text-sm text-white outline-none transition-all placeholder:text-white/30 focus:border-[#5DBB63]/50 focus:ring-4 focus:ring-[#5DBB63]/10 lg:w-[360px]"
              />
            </div>
          </div>

          <div className="grid gap-4 p-6">
            {filteredLogs.length ===
            0 ? (
              <div className="flex min-h-[220px] items-center justify-center rounded-3xl border border-dashed border-white/10 bg-black/10 text-sm text-white/40">
                No health logs found.
              </div>
            ) : (
              filteredLogs.map(
                (log) => {
                  const disease =
                    getDiseaseName(log);

                  const healthy =
                    isHealthy(disease);

                  return (
                    <div
                      key={log.id}
                      className="rounded-[1.5rem] border border-white/10 bg-black/10 p-5 transition hover:border-[#5DBB63]/30 hover:bg-white/[0.04]"
                    >
                      <div className="flex flex-col gap-5 md:flex-row">
                        {log.image_url ? (
                          <img
                            src={
                              log.image_url
                            }
                            alt="Health log image"
                            className="h-40 w-full rounded-2xl object-cover md:w-56"
                          />
                        ) : (
                          <div className="flex h-40 w-full items-center justify-center rounded-2xl bg-black/20 text-white/30 md:w-56">
                            No Image
                          </div>
                        )}

                        <div className="flex-1">
                          <div className="mb-3 flex flex-wrap items-center gap-3">
                            <h4 className="text-xl font-black">
                              {
                                disease
                              }
                            </h4>

                            <span
                              className={`rounded-full border px-3 py-1 text-[11px] font-black uppercase tracking-[2px] ${
                                healthy
                                  ? "border-[#5DBB63]/30 bg-[#5DBB63]/10 text-[#5DBB63]"
                                  : "border-orange-400/30 bg-orange-400/10 text-orange-300"
                              }`}
                            >
                              {healthy
                                ? "Healthy"
                                : "Risk"}
                            </span>
                          </div>

                          <div className="grid gap-3 text-sm text-white/60 md:grid-cols-2">
                            <p>
                              Confidence:{" "}
                              <span className="font-black text-[#5DBB63]">
                                {getConfidence(
                                  log
                                )}
                              </span>
                            </p>

                            <p>
                              Temperature:{" "}
                              {getTemperature(
                                log
                              )}
                            </p>

                            <p>
                              Weather:{" "}
                              {readText(
                                log,
                                [
                                  "weather_condition",
                                  "weather",
                                ],
                                "N/A"
                              )}
                            </p>

                            <p>
                              Location:{" "}
                              {readText(
                                log,
                                [
                                  "location",
                                ],
                                "N/A"
                              )}
                            </p>

                            <p className="md:col-span-2">
                              Date:{" "}
                              {getDate(
                                log
                              )}
                            </p>
                          </div>
                        </div>
                      </div>
                    </div>
                  );
                }
              )
            )}
          </div>
        </section>
      </div>
    </main>
  );
}

function WeatherMetric({
  label,
  value,
  capitalize = false,
}: {
  label: string;
  value: string;
  capitalize?: boolean;
}) {
  return (
    <div className="rounded-2xl border border-white/10 bg-black/15 p-4">
      <p className="text-[10px] font-black uppercase tracking-[2px] text-white/35">
        {label}
      </p>

      <p
        className={`mt-1 text-sm font-black text-white ${
          capitalize
            ? "capitalize"
            : ""
        }`}
      >
        {value}
      </p>
    </div>
  );
}