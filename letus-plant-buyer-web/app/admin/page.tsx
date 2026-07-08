"use client";

import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { useRouter } from "next/navigation";
import { supabase } from "@/lib/supabase";

// ============================================================
// TYPES
// ============================================================

type AdminStats = {
  totalUsers: number;
  totalFarmers: number;
  totalBuyers: number;
  totalProducts: number;
  totalOrders: number;
  pendingOrders: number;
};

type Order = {
  id: string;
  user_id: string;
  farmer_id: string | null;
  shipping_name: string;
  status: string;
  payment_status: string;
  total_amount: number;
  created_at: string;
  proof_image_url?: string | null;
  delivery_proof_url?: string | null;
  order_code?: string | null;
};

type DiagnosticLog = {
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

type UserItem = {
  id: string;
  full_name: string | null;
  email: string;
  role: string;
  created_at?: string | null;
};

const USER_ROLES = ["admin", "farmer", "buyer"] as const;

// ============================================================
// HELPERS
// ============================================================

async function readJsonResponse(response: Response) {
  const text = await response.text();

  try {
    return JSON.parse(text);
  } catch {
    throw new Error(
      text || `Request failed with status ${response.status}`
    );
  }
}

function formatMoney(
  value: number | string | null | undefined
) {
  return Number(value || 0).toLocaleString("en-PH", {
    minimumFractionDigits: 2,
    maximumFractionDigits: 2,
  });
}

function formatDate(value?: string | null) {
  if (!value) return "No date";

  const date = new Date(value);

  if (Number.isNaN(date.getTime())) {
    return value;
  }

  return date.toLocaleDateString();
}

function formatDateTime(value?: string | null) {
  if (!value) return "No date";

  const date = new Date(value);

  if (Number.isNaN(date.getTime())) {
    return value;
  }

  return date.toLocaleString();
}

function getDiagnosticResult(log: DiagnosticLog) {
  return (
    log.disease_name ||
    log.result ||
    "Unknown Result"
  );
}

function getConfidence(log: DiagnosticLog) {
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

function getTemperature(log: DiagnosticLog) {
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

function statusStyle(status?: string | null) {
  const value = String(status || "").toLowerCase();

  if (
    value.includes("delivered") ||
    value.includes("completed") ||
    value.includes("paid") ||
    value.includes("received")
  ) {
    return "border-[#5DBB63]/30 bg-[#5DBB63]/10 text-[#7ED884]";
  }

  if (value.includes("cancel")) {
    return "border-red-500/30 bg-red-500/10 text-red-300";
  }

  if (
    value.includes("pending") ||
    value.includes("confirmed") ||
    value.includes("preparing") ||
    value.includes("shipped")
  ) {
    return "border-amber-500/30 bg-amber-500/10 text-amber-300";
  }

  return "border-white/10 bg-white/[0.04] text-white/70";
}

// ============================================================
// LOGO
// ============================================================

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

// ============================================================
// PAGE
// ============================================================

export default function AdminDashboardPage() {
  const router = useRouter();

  const diagnosticsSectionRef =
    useRef<HTMLElement | null>(null);

  const [stats, setStats] =
    useState<AdminStats | null>(null);

  const [orders, setOrders] =
    useState<Order[]>([]);

  const [users, setUsers] =
    useState<UserItem[]>([]);

  const [
    diagnosticLogs,
    setDiagnosticLogs,
  ] = useState<DiagnosticLog[]>([]);

  const [loading, setLoading] =
    useState(true);

  const [search, setSearch] =
    useState("");

  const [
    updatingRole,
    setUpdatingRole,
  ] = useState<string | null>(null);

  const [
    deletingUser,
    setDeletingUser,
  ] = useState<string | null>(null);

  const [adminName, setAdminName] =
    useState("Admin");

  const [
    showAllDiagnostics,
    setShowAllDiagnostics,
  ] = useState(false);

  // ============================================================
  // USER HELPERS
  // ============================================================

  const isVisibleUser = (user: UserItem) => {
    const email =
      String(user.email || "").toLowerCase();

    const role =
      String(user.role || "").toLowerCase();

    return (
      role !== "deleted" &&
      !email.startsWith("deleted_")
    );
  };

  const buildStats = (
    visibleUsers: UserItem[],
    currentOrders: Order[],
    totalProducts: number
  ): AdminStats => {
    return {
      totalUsers: visibleUsers.length,

      totalFarmers: visibleUsers.filter(
        (user) =>
          String(user.role).toLowerCase() ===
          "farmer"
      ).length,

      totalBuyers: visibleUsers.filter(
        (user) =>
          String(user.role).toLowerCase() ===
          "buyer"
      ).length,

      totalProducts,

      totalOrders: currentOrders.length,

      pendingOrders: currentOrders.filter(
        (order) =>
          String(order.status).toLowerCase() ===
          "pending"
      ).length,
    };
  };

  // ============================================================
  // DATA LOADERS
  // ============================================================

  const loadUsers = async () => {
    try {
      const response = await fetch(
        "/api/admin/users",
        {
          method: "GET",
        }
      );

      const result =
        await readJsonResponse(response);

      if (!result.success) {
        throw new Error(
          result.message ||
            "Failed to fetch users."
        );
      }

      return (
        (result.users as UserItem[]) || []
      );
    } catch {
      const { data, error } = await supabase
        .from("users")
        .select(
          "id, full_name, email, role, created_at"
        )
        .order("created_at", {
          ascending: false,
        });

      if (error) {
        throw new Error(error.message);
      }

      return (data as UserItem[]) || [];
    }
  };

  const loadOrders = async () => {
    try {
      const response = await fetch(
        "/api/admin/orders",
        {
          method: "GET",
        }
      );

      const result =
        await readJsonResponse(response);

      if (!result.success) {
        throw new Error(
          result.message ||
            "Failed to fetch orders."
        );
      }

      return (
        (result.orders as Order[]) || []
      );
    } catch {
      const { data, error } = await supabase
        .from("orders")
        .select("*")
        .order("created_at", {
          ascending: false,
        });

      if (error) {
        throw new Error(error.message);
      }

      return (data as Order[]) || [];
    }
  };

  const loadDiagnosticLogs = async () => {
    const { data, error } = await supabase
      .from("diagnostic_logs")
      .select("*")
      .order("created_at", {
        ascending: false,
      });

    if (error) {
      throw new Error(error.message);
    }

    return (
      (data as DiagnosticLog[]) || []
    );
  };

  const fetchAdminData =
    useCallback(async () => {
      setLoading(true);

      try {
        const {
          data: { session },
        } =
          await supabase.auth.getSession();

        if (session?.user) {
          const { data: userData } =
            await supabase
              .from("users")
              .select("full_name")
              .eq(
                "id",
                session.user.id
              )
              .maybeSingle();

          setAdminName(
            userData?.full_name || "Admin"
          );
        }

        const [
          { count: totalProducts },
          loadedUsers,
          loadedOrders,
          loadedDiagnosticLogs,
        ] = await Promise.all([
          supabase
            .from("products")
            .select("*", {
              count: "exact",
              head: true,
            }),

          loadUsers(),

          loadOrders(),

          loadDiagnosticLogs(),
        ]);

        const visibleUsers =
          loadedUsers.filter(isVisibleUser);

        setUsers(visibleUsers);

        setOrders(loadedOrders);

        setDiagnosticLogs(
          loadedDiagnosticLogs
        );

        setStats(
          buildStats(
            visibleUsers,
            loadedOrders,
            totalProducts || 0
          )
        );
      } catch (error) {
        alert(
          error instanceof Error
            ? error.message
            : "Failed to load admin dashboard."
        );
      } finally {
        setLoading(false);
      }
    }, []);

  useEffect(() => {
    fetchAdminData();
  }, [fetchAdminData]);

  // ============================================================
  // AUTH
  // ============================================================

  const handleLogout = async () => {
    await supabase.auth.signOut();

    router.replace("/");
  };

  // ============================================================
  // USER MANAGEMENT
  // ============================================================

  const handleRoleChange = async (
    userId: string,
    newRole:
      | "admin"
      | "farmer"
      | "buyer"
  ) => {
    const targetUser = users.find(
      (user) => user.id === userId
    );

    const confirmed = window.confirm(
      `Are you sure you want to make this user a ${newRole}?\n\n${
        targetUser?.email || userId
      }`
    );

    if (!confirmed) return;

    setUpdatingRole(userId);

    try {
      const response = await fetch(
        "/api/admin/users",
        {
          method: "PATCH",

          headers: {
            "Content-Type":
              "application/json",
          },

          body: JSON.stringify({
            userId,
            role: newRole,
          }),
        }
      );

      const result =
        await readJsonResponse(response);

      if (!result.success) {
        throw new Error(
          result.message ||
            "Failed to update role."
        );
      }

      const updatedUser =
        result.user as
          | UserItem
          | undefined;

      const updatedUsers = users.map(
        (user) =>
          user.id === userId
            ? updatedUser || {
                ...user,
                role: newRole,
              }
            : user
      );

      setUsers(updatedUsers);

      setStats((previous) => {
        if (!previous) return previous;

        return buildStats(
          updatedUsers,
          orders,
          previous.totalProducts
        );
      });

      alert(
        result.message ||
          `Role changed to ${newRole}.`
      );

      await fetchAdminData();
    } catch (error) {
      alert(
        error instanceof Error
          ? error.message
          : "Role update failed."
      );
    } finally {
      setUpdatingRole(null);
    }
  };

  const handleDeleteUser = async (
    userId: string,
    email: string
  ) => {
    const confirmed = window.confirm(
      `Are you sure you want to delete this user?\n\n${email}\n\nIf full delete is blocked, the user will be hidden.`
    );

    if (!confirmed) return;

    setDeletingUser(userId);

    try {
      const response = await fetch(
        `/api/admin/users?userId=${userId}`,
        {
          method: "DELETE",
        }
      );

      const result =
        await readJsonResponse(response);

      if (!result.success) {
        throw new Error(
          result.message ||
            "Delete failed."
        );
      }

      const remainingUsers =
        users.filter(
          (user) =>
            user.id !== userId
        );

      setUsers(remainingUsers);

      setStats((previous) => {
        if (!previous) return previous;

        return buildStats(
          remainingUsers,
          orders,
          previous.totalProducts
        );
      });

      alert(
        result.message ||
          "User removed."
      );

      await fetchAdminData();
    } catch (error) {
      alert(
        error instanceof Error
          ? error.message
          : "Delete failed."
      );
    } finally {
      setDeletingUser(null);
    }
  };

  // ============================================================
  // DIAGNOSTICS
  // ============================================================

  const visibleDiagnosticLogs =
    useMemo(() => {
      return showAllDiagnostics
        ? diagnosticLogs
        : diagnosticLogs.slice(0, 4);
    }, [
      diagnosticLogs,
      showAllDiagnostics,
    ]);

  const handleToggleDiagnostics = () => {
    if (showAllDiagnostics) {
      setShowAllDiagnostics(false);

      window.setTimeout(() => {
        diagnosticsSectionRef.current?.scrollIntoView(
          {
            behavior: "smooth",
            block: "start",
          }
        );
      }, 50);

      return;
    }

    setShowAllDiagnostics(true);
  };

  // ============================================================
  // FILTERS / STATS
  // ============================================================

  const filteredUsers = useMemo(() => {
    const query =
      search.toLowerCase().trim();

    return users.filter((user) => {
      return (
        (user.full_name || "")
          .toLowerCase()
          .includes(query) ||
        user.email
          .toLowerCase()
          .includes(query) ||
        user.role
          .toLowerCase()
          .includes(query)
      );
    });
  }, [users, search]);

  const totalRevenue = orders.reduce(
    (sum, order) =>
      sum +
      Number(order.total_amount || 0),
    0
  );

  const statCards = [
    {
      label: "Total Users",
      value: stats?.totalUsers || 0,
      icon: "👥",
      tone:
        "from-blue-500/20 to-blue-500/5 text-blue-300",
    },
    {
      label: "Farmers",
      value: stats?.totalFarmers || 0,
      icon: "🧑‍🌾",
      tone:
        "from-amber-500/20 to-amber-500/5 text-amber-300",
    },
    {
      label: "Buyers",
      value: stats?.totalBuyers || 0,
      icon: "🛒",
      tone:
        "from-indigo-500/20 to-indigo-500/5 text-indigo-300",
    },
    {
      label: "Products",
      value: stats?.totalProducts || 0,
      icon: "🥬",
      tone:
        "from-[#5DBB63]/25 to-[#5DBB63]/5 text-[#5DBB63]",
    },
    {
      label: "Orders",
      value: stats?.totalOrders || 0,
      icon: "📦",
      tone:
        "from-purple-500/20 to-purple-500/5 text-purple-300",
    },
    {
      label: "Pending",
      value: stats?.pendingOrders || 0,
      icon: "⏳",
      tone:
        "from-rose-500/20 to-rose-500/5 text-rose-300",
    },
  ];

  // ============================================================
  // LOADING
  // ============================================================

  if (loading) {
    return (
      <main className="flex min-h-screen flex-col items-center justify-center gap-6 bg-[#07100B] px-6 text-white">
        <div className="relative">
          <div className="h-20 w-20 animate-spin rounded-full border-4 border-[#5DBB63]/20 border-t-[#5DBB63]" />

          <div className="absolute inset-0 flex items-center justify-center">
            <GreenGuardIcon className="h-12 w-12" />
          </div>
        </div>

        <div className="text-center">
          <p className="text-sm font-black uppercase tracking-[4px] text-[#5DBB63]">
            Loading Admin Dashboard
          </p>

          <p className="mt-2 text-sm text-white/50">
            Syncing users, diagnostics,
            products, and orders...
          </p>
        </div>
      </main>
    );
  }

  // ============================================================
  // UI
  // ============================================================

  return (
    <main className="min-h-screen bg-[#07100B] pb-24 text-white">
      {/* BACKGROUND */}

      <div className="pointer-events-none fixed inset-0 overflow-hidden">
        <div className="absolute -left-[18%] top-[-18%] h-[720px] w-[720px] rounded-full bg-[#5DBB63]/15 blur-[140px]" />

        <div className="absolute -right-[18%] bottom-[-22%] h-[820px] w-[820px] rounded-full bg-[#2F6B3B]/20 blur-[170px]" />

        <div className="absolute inset-0 bg-[linear-gradient(rgba(255,255,255,0.025)_1px,transparent_1px),linear-gradient(90deg,rgba(255,255,255,0.025)_1px,transparent_1px)] bg-[size:54px_54px]" />
      </div>

      {/* ====================================================== */}
      {/* HEADER */}
      {/* ====================================================== */}

      <header className="sticky top-0 z-50 border-b border-white/10 bg-[#07100B]/80 px-4 py-4 shadow-2xl shadow-black/20 backdrop-blur-2xl sm:px-6 sm:py-5">
        <div className="mx-auto flex max-w-[1400px] items-center justify-between gap-4">
          <div className="flex min-w-0 items-center gap-3 sm:gap-4">
            <div className="flex h-11 w-11 shrink-0 items-center justify-center rounded-2xl bg-white shadow-[0_0_35px_rgba(93,187,99,0.35)] sm:h-12 sm:w-12">
              <GreenGuardIcon className="h-9 w-9 sm:h-10 sm:w-10" />
            </div>

            <div className="min-w-0">
              <h1 className="truncate text-xl font-black tracking-tighter text-white sm:text-2xl">
                GreenGuard AI
              </h1>

              <p className="truncate text-[9px] font-bold uppercase tracking-[2px] text-[#5DBB63] sm:text-[10px] sm:tracking-[3px]">
                Admin Command Center
              </p>
            </div>
          </div>

          <div className="flex shrink-0 items-center gap-2 sm:gap-4">
            <div className="hidden items-center gap-3 rounded-2xl border border-white/10 bg-white/[0.04] px-5 py-2 md:flex">
              <div className="flex h-9 w-9 items-center justify-center rounded-full bg-[#5DBB63]/15 text-sm font-black text-[#5DBB63]">
                {adminName[0] || "A"}
              </div>

              <div>
                <p className="text-sm font-bold text-white">
                  {adminName}
                </p>

                <p className="-mt-0.5 text-[10px] text-white/40">
                  Administrator
                </p>
              </div>
            </div>

            <button
              onClick={handleLogout}
              className="rounded-xl border border-red-500/30 bg-red-500/10 px-3 py-2 text-xs font-black text-red-300 transition hover:bg-red-500 hover:text-white sm:rounded-2xl sm:px-5 sm:py-2.5 sm:text-sm"
            >
              Logout
            </button>
          </div>
        </div>
      </header>

      <div className="relative z-10 mx-auto w-full max-w-[1400px] px-4 pt-6 sm:px-6 sm:pt-10">
        {/* ==================================================== */}
        {/* COMMAND CENTER */}
        {/* ==================================================== */}

        <section className="relative mb-8 overflow-hidden rounded-[1.7rem] border border-[#5DBB63]/20 bg-gradient-to-br from-[#132019]/95 via-[#0D1711]/95 to-[#07100B]/95 p-6 shadow-2xl shadow-black/30 sm:mb-10 sm:rounded-[2rem] sm:p-10">
          <div className="absolute right-0 top-0 h-48 w-48 rounded-full bg-[#5DBB63]/10 blur-3xl" />

          <div className="relative z-10">
            <div className="mb-5 inline-flex rounded-full border border-[#5DBB63]/20 bg-[#5DBB63]/10 px-4 py-2 text-[10px] font-black uppercase tracking-[2px] text-[#5DBB63] sm:text-xs sm:tracking-[3px]">
              Admin Command Center
            </div>

            <h2 className="max-w-3xl text-4xl font-black tracking-tighter text-white sm:text-5xl md:text-6xl">
              Welcome back, Admin
            </h2>

            <p className="mt-4 max-w-3xl text-base leading-7 text-white/55 sm:text-lg">
              Manage users, review diagnostics,
              moderate system activity, and monitor
              buyer–farmer transactions.
            </p>

            <div className="mt-7 flex flex-wrap gap-3">
              <div className="rounded-2xl border border-white/10 bg-white/[0.04] px-4 py-3 text-sm text-white/70 sm:px-5">
                Pending Orders:{" "}
                <span className="font-black text-[#5DBB63]">
                  {stats?.pendingOrders || 0}
                </span>
              </div>

              <div className="rounded-2xl border border-white/10 bg-white/[0.04] px-4 py-3 text-sm text-white/70 sm:px-5">
                Monitored Revenue:{" "}
                <span className="font-black text-[#5DBB63]">
                  ₱{formatMoney(totalRevenue)}
                </span>
              </div>

              <div className="rounded-2xl border border-white/10 bg-white/[0.04] px-4 py-3 text-sm text-white/70 sm:px-5">
                Diagnostic Logs:{" "}
                <span className="font-black text-[#5DBB63]">
                  {diagnosticLogs.length}
                </span>
              </div>
            </div>
          </div>
        </section>

        {/* ==================================================== */}
        {/* STATS */}
        {/* ==================================================== */}

        <section className="mb-10 grid grid-cols-2 gap-3 sm:gap-5 md:grid-cols-3 lg:mb-12 lg:grid-cols-6">
          {statCards.map((stat) => (
            <div
              key={stat.label}
              className="rounded-[1.4rem] border border-white/10 bg-white/[0.035] p-4 shadow-xl shadow-black/10 backdrop-blur-xl transition duration-300 hover:-translate-y-1 hover:border-[#5DBB63]/40 hover:bg-white/[0.06] sm:rounded-[1.7rem] sm:p-5"
            >
              <div
                className={`mb-4 flex h-11 w-11 items-center justify-center rounded-2xl bg-gradient-to-br sm:mb-5 sm:h-12 sm:w-12 ${stat.tone}`}
              >
                <span className="text-xl">
                  {stat.icon}
                </span>
              </div>

              <p className="text-3xl font-black tracking-tighter text-white sm:text-4xl">
                {stat.value}
              </p>

              <p className="mt-1 text-[10px] font-bold uppercase tracking-[1.5px] text-white/40 sm:text-xs sm:tracking-[2px]">
                {stat.label}
              </p>
            </div>
          ))}
        </section>

        {/* ==================================================== */}
        {/* MANAGE USERS */}
        {/* ==================================================== */}

        <section className="mb-10 overflow-hidden rounded-[1.7rem] border border-white/10 bg-white/[0.035] shadow-2xl shadow-black/20 backdrop-blur-xl sm:rounded-[2rem]">
          <div className="border-b border-white/10 px-5 py-6 sm:px-8 sm:py-7">
            <div className="flex flex-col gap-5 lg:flex-row lg:items-center lg:justify-between">
              <div>
                <p className="text-[10px] font-black uppercase tracking-[3px] text-[#5DBB63] sm:text-xs">
                  Manage Users
                </p>

                <h3 className="mt-2 text-2xl font-black tracking-tight text-white">
                  Roles & Accounts
                </h3>

                <p className="mt-1 text-sm text-white/45">
                  Manage roles and remove test or
                  invalid accounts.
                </p>
              </div>

              <input
                type="text"
                placeholder="Search users..."
                value={search}
                onChange={(event) =>
                  setSearch(event.target.value)
                }
                className="w-full rounded-2xl border border-white/10 bg-black/20 px-5 py-3 text-sm text-white outline-none placeholder:text-white/30 focus:border-[#5DBB63]/50 focus:ring-4 focus:ring-[#5DBB63]/10 lg:w-[360px]"
              />
            </div>
          </div>

          <div className="max-h-[650px] overflow-y-auto p-4 sm:p-6">
            {filteredUsers.length === 0 ? (
              <div className="flex min-h-[220px] items-center justify-center rounded-3xl border border-dashed border-white/10 bg-black/10 text-sm text-white/40">
                No users found.
              </div>
            ) : (
              <div className="grid gap-4">
                {filteredUsers.map((user) => {
                  const normalizedRole =
                    String(
                      user.role || "buyer"
                    ).toLowerCase();

                  return (
                    <div
                      key={user.id}
                      className="rounded-[1.4rem] border border-white/10 bg-black/10 p-4 transition hover:border-[#5DBB63]/30 hover:bg-white/[0.04] sm:rounded-[1.5rem] sm:p-5"
                    >
                      <div className="flex flex-col gap-5 xl:flex-row xl:items-center xl:justify-between">
                        <div className="flex min-w-0 items-center gap-4">
                          <div className="flex h-12 w-12 shrink-0 items-center justify-center rounded-2xl bg-gradient-to-br from-[#5DBB63]/20 to-[#2F6B3B]/10 text-lg font-black uppercase text-[#5DBB63] sm:h-14 sm:w-14">
                            {(
                              user.full_name ||
                              user.email ||
                              "U"
                            ).charAt(0)}
                          </div>

                          <div className="min-w-0">
                            <div className="flex flex-wrap items-center gap-3">
                              <h4 className="truncate text-base font-black text-white sm:text-lg">
                                {user.full_name ||
                                  "Unnamed User"}
                              </h4>

                              <span className="rounded-full border border-[#5DBB63]/20 bg-[#5DBB63]/10 px-3 py-1 text-[10px] font-black uppercase tracking-[2px] text-[#5DBB63] sm:text-[11px]">
                                {normalizedRole}
                              </span>
                            </div>

                            <p className="mt-1 break-all text-sm text-white/45">
                              {user.email}
                            </p>

                            <p className="mt-1 break-all text-xs text-white/25">
                              ID: {user.id}
                            </p>
                          </div>
                        </div>

                        <div className="flex flex-wrap gap-2">
                          {USER_ROLES.map(
                            (role) => (
                              <button
                                key={role}
                                onClick={() =>
                                  handleRoleChange(
                                    user.id,
                                    role
                                  )
                                }
                                disabled={
                                  updatingRole ===
                                    user.id ||
                                  normalizedRole ===
                                    role
                                }
                                className="rounded-xl border border-[#5DBB63]/30 bg-[#5DBB63]/10 px-3 py-2 text-xs font-black text-[#5DBB63] transition hover:bg-[#5DBB63] hover:text-[#07100B] disabled:cursor-not-allowed disabled:opacity-40 sm:rounded-2xl sm:px-4 sm:text-sm"
                              >
                                {updatingRole ===
                                user.id
                                  ? "Updating..."
                                  : `Make ${role}`}
                              </button>
                            )
                          )}

                          <button
                            onClick={() =>
                              handleDeleteUser(
                                user.id,
                                user.email
                              )
                            }
                            disabled={
                              deletingUser === user.id
                            }
                            className="rounded-xl border border-red-500/30 bg-red-500/10 px-3 py-2 text-xs font-black text-red-300 transition hover:bg-red-500 hover:text-white disabled:opacity-40 sm:rounded-2xl sm:px-4 sm:text-sm"
                          >
                            {deletingUser === user.id
                              ? "Deleting..."
                              : "Delete"}
                          </button>
                        </div>
                      </div>
                    </div>
                  );
                })}
              </div>
            )}
          </div>
        </section>

        {/* ==================================================== */}
        {/* VIEW DIAGNOSTICS */}
        {/* ==================================================== */}

        <section
          ref={diagnosticsSectionRef}
          className="mb-10 scroll-mt-28 overflow-hidden rounded-[1.7rem] border border-white/10 bg-white/[0.035] shadow-2xl shadow-black/20 backdrop-blur-xl sm:rounded-[2rem]"
        >
          <div className="flex flex-col gap-4 border-b border-white/10 px-5 py-6 sm:px-8 sm:py-7 md:flex-row md:items-center md:justify-between">
            <div>
              <p className="text-[10px] font-black uppercase tracking-[3px] text-[#5DBB63] sm:text-xs">
                View Diagnostics
              </p>

              <h3 className="mt-2 text-2xl font-black tracking-tight text-white">
                Scan Logs & Analytics
              </h3>

              <p className="mt-1 max-w-2xl text-sm leading-6 text-white/45">
                Review crop scan results,
                confidence scores, locations,
                weather conditions, and captured
                images.
              </p>
            </div>

            <div className="flex flex-wrap items-center gap-2">
              <div className="rounded-full border border-white/10 bg-white/[0.04] px-4 py-2 text-xs font-mono text-white/60">
                {diagnosticLogs.length} total
              </div>

              {!showAllDiagnostics &&
                diagnosticLogs.length > 4 && (
                  <div className="rounded-full border border-[#5DBB63]/20 bg-[#5DBB63]/10 px-4 py-2 text-xs font-bold text-[#5DBB63]">
                    Showing latest 4
                  </div>
                )}
            </div>
          </div>

          <div className="grid gap-4 p-4 sm:p-6">
            {diagnosticLogs.length === 0 ? (
              <div className="flex min-h-[220px] items-center justify-center rounded-3xl border border-dashed border-white/10 bg-black/10 text-center text-sm text-white/40">
                No diagnostic logs yet.
              </div>
            ) : (
              visibleDiagnosticLogs.map(
                (log, index) => (
                  <div
                    key={log.id}
                    className="group rounded-[1.5rem] border border-white/10 bg-black/10 p-4 transition-all duration-300 hover:-translate-y-0.5 hover:border-[#5DBB63]/25 hover:bg-white/[0.025] sm:p-5"
                  >
                    <div className="flex flex-col gap-5 md:flex-row">
                      {log.image_url ? (
                        <div className="relative h-52 w-full shrink-0 overflow-hidden rounded-2xl md:h-40 md:w-52">
                          <img
                            src={log.image_url}
                            alt="Diagnostic scan"
                            className="h-full w-full object-cover transition-transform duration-500 group-hover:scale-105"
                          />

                          <div className="absolute left-3 top-3 rounded-full bg-black/60 px-3 py-1 text-[10px] font-black text-white backdrop-blur">
                            Scan {index + 1}
                          </div>
                        </div>
                      ) : (
                        <div className="flex h-52 w-full shrink-0 items-center justify-center rounded-2xl border border-white/5 bg-white/[0.04] text-sm text-white/30 md:h-40 md:w-52">
                          No Image
                        </div>
                      )}

                      <div className="min-w-0 flex-1">
                        <div className="flex flex-col gap-3 sm:flex-row sm:items-start sm:justify-between">
                          <div>
                            <p className="text-[10px] font-black uppercase tracking-[2px] text-[#5DBB63] sm:text-xs">
                              Diagnostic Result
                            </p>

                            <h4 className="mt-1 break-words text-xl font-black text-white sm:text-2xl">
                              {getDiagnosticResult(
                                log
                              )}
                            </h4>
                          </div>

                          <span className="w-fit shrink-0 rounded-full border border-[#5DBB63]/20 bg-[#5DBB63]/10 px-4 py-2 text-sm font-black text-[#5DBB63]">
                            {getConfidence(log)}
                          </span>
                        </div>

                        <div className="mt-5 grid grid-cols-2 gap-4 lg:grid-cols-4">
                          <div>
                            <p className="text-[10px] uppercase tracking-wider text-white/35">
                              Temperature
                            </p>

                            <p className="mt-1 font-bold text-white">
                              {getTemperature(log)}
                            </p>
                          </div>

                          <div>
                            <p className="text-[10px] uppercase tracking-wider text-white/35">
                              Location
                            </p>

                            <p className="mt-1 break-words font-bold text-white">
                              {log.location ||
                                "N/A"}
                            </p>
                          </div>

                          <div>
                            <p className="text-[10px] uppercase tracking-wider text-white/35">
                              Weather
                            </p>

                            <p className="mt-1 break-words font-bold text-white">
                              {log.weather_condition ||
                                log.weather ||
                                "N/A"}
                            </p>
                          </div>

                          <div>
                            <p className="text-[10px] uppercase tracking-wider text-white/35">
                              Date
                            </p>

                            <p className="mt-1 text-sm font-bold text-white">
                              {formatDateTime(
                                log.captured_at ||
                                  log.created_at
                              )}
                            </p>
                          </div>
                        </div>

                        <div className="mt-4 rounded-xl border border-white/5 bg-white/[0.03] px-4 py-3">
                          <p className="text-[10px] uppercase tracking-wider text-white/30">
                            User ID
                          </p>

                          <p className="mt-1 break-all font-mono text-xs text-white/55">
                            {log.user_id ||
                              "N/A"}
                          </p>
                        </div>
                      </div>
                    </div>
                  </div>
                )
              )
            )}
          </div>

          {diagnosticLogs.length > 4 && (
            <div className="border-t border-white/10 bg-black/10 px-4 py-5 text-center sm:px-6 sm:py-6">
              <button
                type="button"
                onClick={
                  handleToggleDiagnostics
                }
                className="group inline-flex min-w-[190px] items-center justify-center gap-3 rounded-2xl border border-[#5DBB63]/30 bg-[#5DBB63]/10 px-6 py-3.5 text-sm font-black text-[#5DBB63] shadow-lg shadow-black/10 transition-all duration-300 hover:-translate-y-0.5 hover:bg-[#5DBB63] hover:text-[#07100B] active:scale-[0.98]"
              >
                <span>
                  {showAllDiagnostics
                    ? "Show Less"
                    : `Show All ${diagnosticLogs.length} Logs`}
                </span>

                <svg
                  className={`h-4 w-4 transition-transform duration-300 ${
                    showAllDiagnostics
                      ? "rotate-180"
                      : ""
                  }`}
                  fill="none"
                  viewBox="0 0 24 24"
                  stroke="currentColor"
                >
                  <path
                    strokeLinecap="round"
                    strokeLinejoin="round"
                    strokeWidth={2.5}
                    d="M19 9l-7 7-7-7"
                  />
                </svg>
              </button>

              <p className="mt-3 text-xs text-white/30">
                {showAllDiagnostics
                  ? `Viewing all ${diagnosticLogs.length} diagnostic records`
                  : `Showing 4 of ${diagnosticLogs.length} diagnostic records`}
              </p>
            </div>
          )}
        </section>

        {/* ==================================================== */}
        {/* MONITOR ORDERS */}
        {/* ==================================================== */}

        <section className="overflow-hidden rounded-[1.7rem] border border-white/10 bg-white/[0.035] shadow-2xl shadow-black/20 backdrop-blur-xl sm:rounded-[2rem]">
          <div className="flex flex-col gap-4 border-b border-white/10 px-5 py-6 sm:px-8 sm:py-7 md:flex-row md:items-center md:justify-between">
            <div>
              <p className="text-[10px] font-black uppercase tracking-[3px] text-[#5DBB63] sm:text-xs">
                Monitor Orders
              </p>

              <h3 className="mt-2 text-2xl font-black tracking-tight text-white">
                Buyer–Farmer Transactions
              </h3>

              <p className="mt-1 text-sm text-white/45">
                Read-only monitoring of
                transaction progress and proof
                images.
              </p>
            </div>

            <div className="w-fit rounded-full border border-white/10 bg-white/[0.04] px-4 py-2 text-xs font-mono text-white/60">
              {orders.length} orders
            </div>
          </div>

          {/* DESKTOP TABLE */}

          <div className="hidden overflow-x-auto md:block">
            <table className="w-full min-w-[900px]">
              <thead className="bg-black/20 text-xs uppercase tracking-[2px] text-white/35">
                <tr>
                  <th className="px-8 py-5 text-left">
                    Customer
                  </th>

                  <th className="px-8 py-5 text-left">
                    Amount
                  </th>

                  <th className="px-8 py-5 text-left">
                    Payment
                  </th>

                  <th className="px-8 py-5 text-left">
                    Order Status
                  </th>

                  <th className="px-8 py-5 text-left">
                    Proof
                  </th>
                </tr>
              </thead>

              <tbody className="divide-y divide-white/10">
                {orders.length === 0 ? (
                  <tr>
                    <td
                      colSpan={5}
                      className="py-20 text-center text-sm text-white/45"
                    >
                      No orders yet.
                    </td>
                  </tr>
                ) : (
                  orders.map((order) => {
                    const proofUrl =
                      order.proof_image_url ||
                      order.delivery_proof_url;

                    return (
                      <tr
                        key={order.id}
                        className="transition hover:bg-white/[0.035]"
                      >
                        <td className="px-8 py-6">
                          <p className="font-bold text-white">
                            {order.shipping_name ||
                              "Unknown Customer"}
                          </p>

                          <p className="mt-1 text-xs text-white/35">
                            {formatDate(
                              order.created_at
                            )}
                          </p>

                          <p className="mt-1 max-w-[200px] truncate text-xs text-white/25">
                            {order.order_code ||
                              order.id}
                          </p>
                        </td>

                        <td className="px-8 py-6">
                          <p className="font-mono text-xl font-black text-[#5DBB63]">
                            ₱
                            {formatMoney(
                              order.total_amount
                            )}
                          </p>
                        </td>

                        <td className="px-8 py-6">
                          <span
                            className={`inline-flex rounded-full border px-4 py-2 text-sm font-bold ${statusStyle(
                              order.payment_status
                            )}`}
                          >
                            {order.payment_status ||
                              "Unpaid"}
                          </span>
                        </td>

                        <td className="px-8 py-6">
                          <span
                            className={`inline-flex rounded-full border px-4 py-2 text-sm font-bold ${statusStyle(
                              order.status
                            )}`}
                          >
                            {order.status ||
                              "Pending"}
                          </span>
                        </td>

                        <td className="px-8 py-6">
                          {proofUrl ? (
                            <a
                              href={proofUrl}
                              target="_blank"
                              rel="noreferrer"
                              className="inline-flex rounded-2xl border border-[#5DBB63]/30 bg-[#5DBB63]/10 px-4 py-2 text-sm font-black text-[#5DBB63] transition hover:bg-[#5DBB63] hover:text-[#07100B]"
                            >
                              View Proof
                            </a>
                          ) : (
                            <span className="text-sm text-white/35">
                              No proof
                            </span>
                          )}
                        </td>
                      </tr>
                    );
                  })
                )}
              </tbody>
            </table>
          </div>

          {/* MOBILE CARDS */}

          <div className="grid gap-4 p-4 md:hidden">
            {orders.length === 0 ? (
              <div className="py-16 text-center text-sm text-white/45">
                No orders yet.
              </div>
            ) : (
              orders.map((order) => {
                const proofUrl =
                  order.proof_image_url ||
                  order.delivery_proof_url;

                return (
                  <div
                    key={order.id}
                    className="rounded-2xl border border-white/10 bg-black/10 p-5"
                  >
                    <div className="flex items-start justify-between gap-4">
                      <div className="min-w-0">
                        <p className="truncate font-black text-white">
                          {order.shipping_name ||
                            "Unknown Customer"}
                        </p>

                        <p className="mt-1 text-xs text-white/35">
                          {formatDate(
                            order.created_at
                          )}
                        </p>
                      </div>

                      <p className="shrink-0 text-xl font-black text-[#5DBB63]">
                        ₱
                        {formatMoney(
                          order.total_amount
                        )}
                      </p>
                    </div>

                    <div className="mt-4 flex flex-wrap gap-2">
                      <span
                        className={`rounded-full border px-3 py-1.5 text-xs font-bold ${statusStyle(
                          order.payment_status
                        )}`}
                      >
                        {order.payment_status ||
                          "Unpaid"}
                      </span>

                      <span
                        className={`rounded-full border px-3 py-1.5 text-xs font-bold ${statusStyle(
                          order.status
                        )}`}
                      >
                        {order.status ||
                          "Pending"}
                      </span>
                    </div>

                    <p className="mt-4 break-all text-xs text-white/25">
                      {order.order_code ||
                        order.id}
                    </p>

                    {proofUrl && (
                      <a
                        href={proofUrl}
                        target="_blank"
                        rel="noreferrer"
                        className="mt-4 inline-flex w-full items-center justify-center rounded-2xl bg-[#5DBB63] px-4 py-3 text-sm font-black text-[#07100B]"
                      >
                        View Proof
                      </a>
                    )}
                  </div>
                );
              })
            )}
          </div>
        </section>
      </div>
    </main>
  );
}