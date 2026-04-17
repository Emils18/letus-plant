"use client";

import { useCallback, useEffect, useMemo, useState } from "react";
import { supabase } from "@/lib/supabase";
import { useRouter } from "next/navigation";
import Link from "next/link";

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
  order_code?: string | null;
};

type UserItem = {
  id: string;
  full_name: string | null;
  email: string;
  role: "buyer" | "farmer" | "admin" | string;
  created_at?: string | null;
};

const ORDER_STATUSES = ["Pending", "Confirmed", "Preparing", "Delivered"];
const PAYMENT_STATUSES = ["Unpaid", "Paid"];
const USER_ROLES = ["admin", "farmer", "buyer"] as const;

export default function AdminDashboardPage() {
  const [stats, setStats] = useState<AdminStats | null>(null);
  const [orders, setOrders] = useState<Order[]>([]);
  const [users, setUsers] = useState<UserItem[]>([]);
  const [loading, setLoading] = useState(true);

  const [search, setSearch] = useState("");
  const [updatingStatus, setUpdatingStatus] = useState<string | null>(null);
  const [updatingPayment, setUpdatingPayment] = useState<string | null>(null);
  const [updatingRole, setUpdatingRole] = useState<string | null>(null);

  const [adminName, setAdminName] = useState("Admin");

  const router = useRouter();

  const fetchAdminData = useCallback(async () => {
    setLoading(true);

    // Auth protection (enable in production)
    /*
    const {
      data: { session },
    } = await supabase.auth.getSession();

    if (!session?.user) {
      router.replace("/");
      return;
    }

    const { data: userData } = await supabase
      .from("users")
      .select("full_name, role")
      .eq("id", session.user.id)
      .single();

    if (!userData || userData.role !== "admin") {
      router.replace("/");
      return;
    }

    setAdminName(userData.full_name || "Admin");
    */

    const [
      { count: totalUsers },
      { count: totalFarmers },
      { count: totalBuyers },
      { count: totalProducts },
      { count: totalOrders },
      { count: pendingOrders },
      { data: allOrders, error: ordersError },
      { data: allUsers, error: usersError },
    ] = await Promise.all([
      supabase.from("users").select("*", { count: "exact", head: true }),
      supabase
        .from("users")
        .select("*", { count: "exact", head: true })
        .eq("role", "farmer"),
      supabase
        .from("users")
        .select("*", { count: "exact", head: true })
        .eq("role", "buyer"),
      supabase.from("products").select("*", { count: "exact", head: true }),
      supabase.from("orders").select("*", { count: "exact", head: true }),
      supabase
        .from("orders")
        .select("*", { count: "exact", head: true })
        .eq("status", "Pending"),
      supabase.from("orders").select("*").order("created_at", { ascending: false }),
      supabase
        .from("users")
        .select("id, full_name, email, role, created_at")
        .order("created_at", { ascending: false }),
    ]);

    if (ordersError) {
      console.error("Error fetching orders:", ordersError.message);
    }

    if (usersError) {
      console.error("Error fetching users:", usersError.message);
    }

    setStats({
      totalUsers: totalUsers || 0,
      totalFarmers: totalFarmers || 0,
      totalBuyers: totalBuyers || 0,
      totalProducts: totalProducts || 0,
      totalOrders: totalOrders || 0,
      pendingOrders: pendingOrders || 0,
    });

    setOrders((allOrders as Order[]) || []);
    setUsers((allUsers as UserItem[]) || []);
    setLoading(false);
  }, [router]);

  useEffect(() => {
    fetchAdminData();
  }, [fetchAdminData]);

  const handleStatusChange = async (orderId: string, newStatus: string) => {
    setUpdatingStatus(orderId);

    const previousOrder = orders.find((o) => o.id === orderId);

    const { error } = await supabase
      .from("orders")
      .update({ status: newStatus })
      .eq("id", orderId);

    if (error) {
      console.error("Error updating status:", error.message);
      setUpdatingStatus(null);
      return;
    }

    setOrders((prev) =>
      prev.map((order) =>
        order.id === orderId ? { ...order, status: newStatus } : order
      )
    );

    if (stats && previousOrder) {
      if (previousOrder.status === "Pending" && newStatus !== "Pending") {
        setStats({
          ...stats,
          pendingOrders: Math.max(0, stats.pendingOrders - 1),
        });
      } else if (
        previousOrder.status !== "Pending" &&
        newStatus === "Pending"
      ) {
        setStats({
          ...stats,
          pendingOrders: stats.pendingOrders + 1,
        });
      }
    }

    setUpdatingStatus(null);
  };

  const handlePaymentChange = async (
    orderId: string,
    newPaymentStatus: string
  ) => {
    setUpdatingPayment(orderId);

    const { error } = await supabase
      .from("orders")
      .update({ payment_status: newPaymentStatus })
      .eq("id", orderId);

    if (error) {
      console.error("Error updating payment:", error.message);
      setUpdatingPayment(null);
      return;
    }

    setOrders((prev) =>
      prev.map((order) =>
        order.id === orderId
          ? { ...order, payment_status: newPaymentStatus }
          : order
      )
    );

    setUpdatingPayment(null);
  };

  const handleRoleChange = async (
    userId: string,
    newRole: "admin" | "farmer" | "buyer"
  ) => {
    setUpdatingRole(userId);

    const { error } = await supabase
      .from("users")
      .update({ role: newRole })
      .eq("id", userId);

    if (error) {
      console.error("Error updating role:", error.message);
      setUpdatingRole(null);
      return;
    }

    // Refresh everything so stats + users stay accurate
    await fetchAdminData();
    setUpdatingRole(null);
  };

  const filteredUsers = useMemo(() => {
    return users.filter((user) => {
      const fullName = user.full_name?.toLowerCase() || "";
      const email = user.email?.toLowerCase() || "";
      const query = search.toLowerCase();

      return fullName.includes(query) || email.includes(query);
    });
  }, [users, search]);

  if (loading) {
    return (
      <div className="flex min-h-screen flex-col items-center justify-center gap-5 bg-[#0A110D]">
        <div className="h-12 w-12 animate-spin rounded-full border-4 border-[#5DBB63]/20 border-t-[#5DBB63]"></div>
        <p className="animate-pulse text-xs font-bold uppercase tracking-widest text-[#5DBB63]">
          Loading Command Center...
        </p>
      </div>
    );
  }

  const totalRevenue = orders.reduce(
    (sum, order) => sum + Number(order.total_amount || 0),
    0
  );

  return (
    <main className="flex min-h-screen flex-col bg-[#0A110D] pb-24 font-sans text-white">
      <header className="sticky top-0 z-50 border-b border-white/10 bg-[#0A110D]/90 px-6 py-5 backdrop-blur-2xl">
        <div className="mx-auto flex max-w-[1400px] items-center justify-between">
          <div className="flex items-center gap-4">
            <div className="flex h-11 w-11 items-center justify-center rounded-2xl bg-gradient-to-br from-[#2F6B3B] via-[#5DBB63] to-[#4CAF50] shadow-[0_0_30px_rgba(93,187,99,0.5)]">
              🌱
            </div>

            <div>
              <h1 className="text-2xl font-black tracking-tighter">
                LetUs Plant
              </h1>
              <p className="text-[10px] font-bold uppercase tracking-[2px] text-[#5DBB63]">
                Admin Command Center
              </p>
            </div>
          </div>

          <div className="flex items-center gap-6">
            <div className="flex items-center gap-2 text-xs">
              <div className="h-2 w-2 animate-ping rounded-full bg-[#5DBB63]"></div>
              <span className="font-medium text-[#5DBB63]">LIVE</span>
            </div>

            <div className="flex items-center gap-3 rounded-2xl border border-white/10 bg-white/5 px-5 py-2">
              <div className="flex h-8 w-8 items-center justify-center rounded-full bg-[#5DBB63]/20 font-bold text-[#5DBB63]">
                {adminName[0]}
              </div>
              <div>
                <p className="text-sm font-semibold">{adminName}</p>
                <p className="-mt-0.5 text-[10px] text-gray-400">
                  Administrator
                </p>
              </div>
            </div>

            <Link
              href="/"
              className="flex items-center gap-2 rounded-2xl bg-white px-6 py-2.5 text-sm font-bold text-[#0A110D] transition-all hover:bg-[#5DBB63] hover:text-white active:scale-95"
            >
              ← Back to Store
            </Link>
          </div>
        </div>
      </header>

      <div className="mx-auto w-full max-w-[1400px] px-6 pt-10">
        <div className="mb-10 rounded-3xl border border-[#5DBB63]/20 bg-gradient-to-br from-[#121D17] to-[#0A110D] p-10 shadow-2xl">
          <h2 className="text-5xl font-black tracking-tighter">
            Welcome back, Commander
          </h2>
          <p className="mt-3 text-xl text-gray-400">
            You have{" "}
            <span className="font-bold text-[#5DBB63]">
              {stats?.pendingOrders}
            </span>{" "}
            orders awaiting fulfillment.
          </p>
        </div>

        <div className="mb-12 grid grid-cols-2 gap-5 md:grid-cols-3 lg:grid-cols-6">
          {[
            { label: "Total Users", value: stats?.totalUsers, color: "text-blue-400" },
            { label: "Farmers", value: stats?.totalFarmers, color: "text-amber-400" },
            { label: "Buyers", value: stats?.totalBuyers, color: "text-indigo-400" },
            { label: "Products", value: stats?.totalProducts, color: "text-[#5DBB63]" },
            { label: "Total Orders", value: stats?.totalOrders, color: "text-purple-400" },
            { label: "Pending", value: stats?.pendingOrders, color: "text-rose-400" },
          ].map((stat, i) => (
            <div
              key={i}
              className="group rounded-3xl border border-white/10 bg-[#121D17] p-6 transition-all duration-300 hover:-translate-y-2 hover:border-[#5DBB63]/30 hover:shadow-2xl hover:shadow-[#5DBB63]/10"
            >
              <p className={`text-5xl font-black tracking-tighter ${stat.color}`}>
                {stat.value}
              </p>
              <p className="mt-2 text-sm font-medium uppercase tracking-widest text-gray-400">
                {stat.label}
              </p>
            </div>
          ))}
        </div>

        <div className="grid gap-8 lg:grid-cols-[1fr_360px]">
          <div className="overflow-hidden rounded-3xl border border-white/10 bg-[#121D17] shadow-2xl">
            <div className="flex items-center justify-between border-b border-white/10 px-8 py-7">
              <div>
                <h3 className="text-2xl font-bold">Fulfillment Center</h3>
                <p className="text-sm text-gray-400">
                  Real-time order management
                </p>
              </div>
              <div className="rounded-full bg-white/5 px-4 py-1.5 text-xs font-mono">
                {orders.length} orders
              </div>
            </div>

            <div className="overflow-x-auto">
              <table className="w-full">
                <thead className="bg-[#0A110D] text-xs uppercase tracking-widest text-gray-500">
                  <tr>
                    <th className="px-8 py-6 text-left">Customer</th>
                    <th className="px-8 py-6 text-left">Amount & Payment</th>
                    <th className="px-8 py-6 text-left">Proof</th>
                    <th className="px-8 py-6 text-right">Status</th>
                  </tr>
                </thead>

                <tbody className="divide-y divide-white/10">
                  {orders.length === 0 ? (
                    <tr>
                      <td colSpan={4} className="py-20 text-center text-gray-400">
                        No orders yet
                      </td>
                    </tr>
                  ) : (
                    orders.map((order, index) => (
                      <tr
                        key={order.id}
                        className="group animate-in fade-in transition-colors duration-200 hover:bg-white/5"
                        style={{ animationDelay: `${index * 30}ms` }}
                      >
                        <td className="px-8 py-7">
                          <div className="flex items-center gap-4">
                            <div className="flex h-11 w-11 items-center justify-center rounded-2xl bg-gradient-to-br from-[#2F6B3B] to-[#5DBB63] text-xl font-bold shadow-inner">
                              {order.shipping_name?.charAt(0).toUpperCase() || "U"}
                            </div>
                            <div>
                              <p className="font-semibold text-lg">
                                {order.shipping_name}
                              </p>
                              <p className="mt-0.5 text-xs text-gray-500">
                                {order.order_code ? `${order.order_code} • ` : ""}
                                {new Date(order.created_at).toLocaleDateString(
                                  undefined,
                                  {
                                    month: "short",
                                    day: "numeric",
                                  }
                                )}
                              </p>
                            </div>
                          </div>
                        </td>

                        <td className="px-8 py-7">
                          <div className="font-mono text-2xl font-bold text-[#5DBB63]">
                            ₱{Number(order.total_amount).toLocaleString()}
                          </div>

                          <div className="relative mt-4 w-40">
                            <select
                              value={order.payment_status || "Unpaid"}
                              onChange={(e) =>
                                handlePaymentChange(order.id, e.target.value)
                              }
                              disabled={updatingPayment === order.id}
                              className="w-full appearance-none rounded-2xl border border-white/10 bg-[#1A2520] px-5 py-3 text-sm font-medium transition-all focus:border-[#5DBB63] focus:outline-none disabled:opacity-60"
                            >
                              {PAYMENT_STATUSES.map((s) => (
                                <option key={s} value={s}>
                                  {s}
                                </option>
                              ))}
                            </select>

                            {updatingPayment === order.id && (
                              <div className="absolute right-4 top-4 h-4 w-4 animate-spin rounded-full border-2 border-[#5DBB63] border-t-transparent" />
                            )}
                          </div>
                        </td>

                        <td className="px-8 py-7">
                          {order.proof_image_url ? (
                            <a
                              href={order.proof_image_url}
                              target="_blank"
                              rel="noreferrer"
                              className="inline-flex items-center gap-2 text-sm font-medium text-blue-400 transition-colors hover:text-blue-300"
                            >
                              👁 View Proof
                            </a>
                          ) : (
                            <span className="text-xs text-gray-500">—</span>
                          )}
                        </td>

                        <td className="px-8 py-7 text-right">
                          <div className="relative inline-block w-44">
                            <select
                              value={order.status}
                              onChange={(e) =>
                                handleStatusChange(order.id, e.target.value)
                              }
                              disabled={updatingStatus === order.id}
                              className={`w-full appearance-none rounded-2xl border px-5 py-3 text-sm font-semibold transition-all focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-offset-[#121D17] disabled:opacity-60
                              ${
                                order.status === "Delivered"
                                  ? "border-emerald-500 bg-emerald-500/10 text-emerald-400"
                                  : order.status === "Pending"
                                  ? "border-rose-500 bg-rose-500/10 text-rose-400"
                                  : "border-[#5DBB63] bg-[#5DBB63]/10 text-[#5DBB63]"
                              }`}
                            >
                              {ORDER_STATUSES.map((s) => (
                                <option key={s} value={s}>
                                  {s}
                                </option>
                              ))}
                            </select>

                            {updatingStatus === order.id && (
                              <div className="absolute right-5 top-4 h-4 w-4 animate-spin rounded-full border-2 border-current border-t-transparent" />
                            )}
                          </div>
                        </td>
                      </tr>
                    ))
                  )}
                </tbody>
              </table>
            </div>
          </div>

          <div className="space-y-8">
            <div className="rounded-3xl border border-white/10 bg-[#121D17] p-8">
              <h4 className="mb-6 flex items-center gap-3 text-lg font-bold">
                <span>🌱</span> Quick Insights
              </h4>

              <div className="space-y-6 text-sm">
                <div className="flex justify-between border-b border-white/10 pb-4">
                  <span className="text-gray-400">Active Buyers</span>
                  <span className="font-semibold">{stats?.totalBuyers}</span>
                </div>

                <div className="flex justify-between border-b border-white/10 pb-4">
                  <span className="text-gray-400">Active Farmers</span>
                  <span className="font-semibold">{stats?.totalFarmers}</span>
                </div>

                <div className="flex justify-between border-b border-white/10 pb-4">
                  <span className="text-gray-400">Total Revenue</span>
                  <span className="font-semibold text-[#5DBB63]">
                    ₱{totalRevenue.toLocaleString()}
                  </span>
                </div>

                <div className="flex justify-between">
                  <span className="text-gray-400">Total Products</span>
                  <span className="font-semibold">{stats?.totalProducts}</span>
                </div>
              </div>
            </div>

            <div className="rounded-3xl border border-[#5DBB63]/30 bg-gradient-to-br from-[#1F2F24] to-[#0A110D] p-8 text-center">
              <div className="mx-auto mb-6 flex h-16 w-16 items-center justify-center rounded-2xl bg-[#5DBB63]/10 text-4xl">
                ✅
              </div>
              <h4 className="text-xl font-bold">System Healthy</h4>
              <p className="mt-3 text-sm text-gray-400">
                All connections stable. Ready for mobile sync.
              </p>
            </div>
          </div>
        </div>

        {/* USER MANAGEMENT */}
        <section className="mt-10 overflow-hidden rounded-3xl border border-white/10 bg-[#121D17] shadow-2xl">
          <div className="border-b border-white/10 px-8 py-7">
            <div className="flex flex-col gap-4 lg:flex-row lg:items-center lg:justify-between">
              <div>
                <h3 className="text-2xl font-bold">User Management</h3>
                <p className="text-sm text-gray-400">
                  View all users, search instantly, and control roles live
                </p>
              </div>

              <div className="w-full lg:w-[360px]">
                <input
                  type="text"
                  placeholder="Search by full name or email..."
                  value={search}
                  onChange={(e) => setSearch(e.target.value)}
                  className="w-full rounded-2xl border border-white/10 bg-[#0A110D] px-5 py-3 text-sm text-white placeholder:text-gray-500 outline-none transition-all focus:border-[#5DBB63] focus:ring-2 focus:ring-[#5DBB63]/20"
                />
              </div>
            </div>
          </div>

          <div className="max-h-[650px] overflow-y-auto px-6 py-6">
            {filteredUsers.length === 0 ? (
              <div className="flex min-h-[220px] items-center justify-center rounded-3xl border border-dashed border-white/10 bg-[#0A110D]/40 text-center text-gray-400">
                No users found for your search.
              </div>
            ) : (
              <div className="grid gap-4">
                {filteredUsers.map((user) => {
                  const normalizedRole = String(user.role || "buyer").toLowerCase();
                  const isAdmin = normalizedRole === "admin";
                  const isFarmer = normalizedRole === "farmer";

                  return (
                    <div
                      key={user.id}
                      className={`group rounded-3xl border p-5 transition-all duration-300 hover:-translate-y-1 hover:shadow-xl
                        ${
                          isAdmin
                            ? "border-[#5DBB63]/40 bg-gradient-to-r from-[#17301F] to-[#121D17] shadow-[0_0_20px_rgba(93,187,99,0.08)]"
                            : "border-white/10 bg-[#0F1813] hover:border-white/20"
                        }`}
                    >
                      <div className="flex flex-col gap-5 xl:flex-row xl:items-center xl:justify-between">
                        <div className="flex items-center gap-4">
                          <div
                            className={`flex h-14 w-14 items-center justify-center rounded-2xl text-lg font-black uppercase
                              ${
                                isAdmin
                                  ? "bg-[#5DBB63]/20 text-[#5DBB63]"
                                  : isFarmer
                                  ? "bg-amber-500/15 text-amber-400"
                                  : "bg-blue-500/15 text-blue-400"
                              }`}
                          >
                            {(user.full_name || user.email || "U").charAt(0)}
                          </div>

                          <div>
                            <div className="flex flex-wrap items-center gap-3">
                              <h4 className="text-lg font-bold text-white">
                                {user.full_name || "Unnamed User"}
                              </h4>

                              <span
                                className={`rounded-full px-3 py-1 text-[11px] font-bold uppercase tracking-wider
                                  ${
                                    isAdmin
                                      ? "bg-[#5DBB63]/15 text-[#5DBB63] ring-1 ring-[#5DBB63]/30"
                                      : isFarmer
                                      ? "bg-amber-500/15 text-amber-400 ring-1 ring-amber-500/30"
                                      : "bg-blue-500/15 text-blue-400 ring-1 ring-blue-500/30"
                                  }`}
                              >
                                {normalizedRole}
                              </span>
                            </div>

                            <p className="mt-1 text-sm text-gray-400">{user.email}</p>
                            <p className="mt-1 text-xs text-gray-500">
                              ID: {user.id}
                              {user.created_at
                                ? ` • Joined ${new Date(user.created_at).toLocaleDateString()}`
                                : ""}
                            </p>
                          </div>
                        </div>

                        <div className="flex flex-wrap gap-2">
                          <button
                            onClick={() => handleRoleChange(user.id, "admin")}
                            disabled={updatingRole === user.id || normalizedRole === "admin"}
                            className="rounded-2xl border border-[#5DBB63]/30 bg-[#5DBB63]/10 px-4 py-2 text-sm font-semibold text-[#5DBB63] transition-all hover:bg-[#5DBB63] hover:text-white disabled:cursor-not-allowed disabled:opacity-50"
                          >
                            {updatingRole === user.id ? "Updating..." : "Make Admin"}
                          </button>

                          <button
                            onClick={() => handleRoleChange(user.id, "farmer")}
                            disabled={updatingRole === user.id || normalizedRole === "farmer"}
                            className="rounded-2xl border border-amber-500/30 bg-amber-500/10 px-4 py-2 text-sm font-semibold text-amber-400 transition-all hover:bg-amber-500 hover:text-black disabled:cursor-not-allowed disabled:opacity-50"
                          >
                            {updatingRole === user.id ? "Updating..." : "Make Farmer"}
                          </button>

                          <button
                            onClick={() => handleRoleChange(user.id, "buyer")}
                            disabled={updatingRole === user.id || normalizedRole === "buyer"}
                            className="rounded-2xl border border-blue-500/30 bg-blue-500/10 px-4 py-2 text-sm font-semibold text-blue-400 transition-all hover:bg-blue-500 hover:text-white disabled:cursor-not-allowed disabled:opacity-50"
                          >
                            {updatingRole === user.id ? "Updating..." : "Make Buyer"}
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
      </div>
    </main>
  );
}