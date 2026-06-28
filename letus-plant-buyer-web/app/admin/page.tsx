"use client";

import { useCallback, useEffect, useMemo, useState } from "react";
import { supabase } from "@/lib/supabase";
import { useRouter } from "next/navigation";

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
  role: string;
  created_at?: string | null;
};

const ORDER_STATUSES = [
  "Pending",
  "Confirmed",
  "Preparing",
  "Shipped",
  "Delivered",
  "Cancelled",
];

const PAYMENT_STATUSES = ["Unpaid", "Pending Verification", "Paid"];
const USER_ROLES = ["admin", "farmer", "buyer"] as const;

async function readJsonResponse(response: Response) {
  const text = await response.text();

  try {
    return JSON.parse(text);
  } catch {
    throw new Error(text || `Request failed with status ${response.status}`);
  }
}

function GreenGuardIcon({ className = "h-10 w-10" }: { className?: string }) {
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

export default function AdminDashboardPage() {
  const router = useRouter();

  const [stats, setStats] = useState<AdminStats | null>(null);
  const [orders, setOrders] = useState<Order[]>([]);
  const [users, setUsers] = useState<UserItem[]>([]);
  const [loading, setLoading] = useState(true);

  const [search, setSearch] = useState("");
  const [updatingRole, setUpdatingRole] = useState<string | null>(null);
  const [deletingUser, setDeletingUser] = useState<string | null>(null);
  const [updatingOrder, setUpdatingOrder] = useState<string | null>(null);
  const [adminName, setAdminName] = useState("Admin");

  const isVisibleUser = (user: UserItem) => {
    const email = String(user.email || "").toLowerCase();
    const role = String(user.role || "").toLowerCase();

    return role !== "deleted" && !email.startsWith("deleted_");
  };

  const buildStats = (
    visibleUsers: UserItem[],
    currentOrders: Order[],
    totalProducts: number
  ): AdminStats => {
    return {
      totalUsers: visibleUsers.length,
      totalFarmers: visibleUsers.filter(
        (user) => String(user.role).toLowerCase() === "farmer"
      ).length,
      totalBuyers: visibleUsers.filter(
        (user) => String(user.role).toLowerCase() === "buyer"
      ).length,
      totalProducts,
      totalOrders: currentOrders.length,
      pendingOrders: currentOrders.filter(
        (order) => String(order.status).toLowerCase() === "pending"
      ).length,
    };
  };

  const loadUsers = async () => {
    try {
      const response = await fetch("/api/admin/users", {
        method: "GET",
      });

      const result = await readJsonResponse(response);

      if (!result.success) {
        throw new Error(result.message || "Failed to fetch users.");
      }

      return (result.users as UserItem[]) || [];
    } catch {
      const { data, error } = await supabase
        .from("users")
        .select("id, full_name, email, role, created_at")
        .order("created_at", { ascending: false });

      if (error) {
        throw new Error(error.message);
      }

      return (data as UserItem[]) || [];
    }
  };

  const loadOrders = async () => {
    try {
      const response = await fetch("/api/admin/orders", {
        method: "GET",
      });

      const result = await readJsonResponse(response);

      if (!result.success) {
        throw new Error(result.message || "Failed to fetch orders.");
      }

      return (result.orders as Order[]) || [];
    } catch {
      const { data, error } = await supabase
        .from("orders")
        .select("*")
        .order("created_at", { ascending: false });

      if (error) {
        throw new Error(error.message);
      }

      return (data as Order[]) || [];
    }
  };

  const fetchAdminData = useCallback(async () => {
    setLoading(true);

    try {
      const {
        data: { session },
      } = await supabase.auth.getSession();

      if (session?.user) {
        const { data: userData } = await supabase
          .from("users")
          .select("full_name")
          .eq("id", session.user.id)
          .maybeSingle();

        setAdminName(userData?.full_name || "Admin");
      }

      const [{ count: totalProducts }, loadedUsers, loadedOrders] =
        await Promise.all([
          supabase.from("products").select("*", {
            count: "exact",
            head: true,
          }),
          loadUsers(),
          loadOrders(),
        ]);

      const visibleUsers = loadedUsers.filter(isVisibleUser);

      setUsers(visibleUsers);
      setOrders(loadedOrders);
      setStats(buildStats(visibleUsers, loadedOrders, totalProducts || 0));
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

  const handleLogout = async () => {
    await supabase.auth.signOut();
    router.replace("/");
  };

  const handleRoleChange = async (
    userId: string,
    newRole: "admin" | "farmer" | "buyer"
  ) => {
    const targetUser = users.find((user) => user.id === userId);

    const confirmed = window.confirm(
      `Are you sure you want to make this user a ${newRole}?\n\n${
        targetUser?.email || userId
      }`
    );

    if (!confirmed) return;

    setUpdatingRole(userId);

    try {
      const response = await fetch("/api/admin/users", {
        method: "PATCH",
        headers: {
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          userId,
          role: newRole,
        }),
      });

      const result = await readJsonResponse(response);

      if (!result.success) {
        throw new Error(result.message || "Failed to update role.");
      }

      const updatedUser = result.user as UserItem | undefined;

      const updatedUsers = users.map((user) =>
        user.id === userId ? updatedUser || { ...user, role: newRole } : user
      );

      setUsers(updatedUsers);
      setStats((prev) => {
        if (!prev) return prev;

        return buildStats(updatedUsers, orders, prev.totalProducts);
      });

      alert(result.message || `Role changed to ${newRole}.`);
      await fetchAdminData();
    } catch (error) {
      alert(error instanceof Error ? error.message : "Role update failed.");
    } finally {
      setUpdatingRole(null);
    }
  };

  const handleDeleteUser = async (userId: string, email: string) => {
    const confirmed = window.confirm(
      `Are you sure you want to delete this user?\n\n${email}\n\nIf full delete is blocked, the user will be hidden.`
    );

    if (!confirmed) return;

    setDeletingUser(userId);

    try {
      const response = await fetch(`/api/admin/users?userId=${userId}`, {
        method: "DELETE",
      });

      const result = await readJsonResponse(response);

      if (!result.success) {
        throw new Error(result.message || "Delete failed.");
      }

      const remainingUsers = users.filter((user) => user.id !== userId);

      setUsers(remainingUsers);
      setStats((prev) => {
        if (!prev) return prev;

        return buildStats(remainingUsers, orders, prev.totalProducts);
      });

      alert(result.message || "User removed.");
      await fetchAdminData();
    } catch (error) {
      alert(error instanceof Error ? error.message : "Delete failed.");
    } finally {
      setDeletingUser(null);
    }
  };

  const handleOrderUpdate = async (
    orderId: string,
    field: "status" | "payment_status",
    value: string
  ) => {
    const label = field === "status" ? "order status" : "payment status";

    const confirmed = window.confirm(
      `Are you sure you want to update ${label} to "${value}"?`
    );

    if (!confirmed) return;

    const updateKey = `${orderId}-${field}`;
    setUpdatingOrder(updateKey);

    const previousOrders = orders;

    try {
      const optimisticOrders = orders.map((order) =>
        order.id === orderId ? { ...order, [field]: value } : order
      );

      setOrders(optimisticOrders);

      const response = await fetch("/api/admin/orders", {
        method: "PATCH",
        headers: {
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          orderId,
          [field]: value,
        }),
      });

      const result = await readJsonResponse(response);

      if (!result.success) {
        throw new Error(result.message || "Failed to update order.");
      }

      const updatedOrder = result.order as Order;

      const finalOrders = optimisticOrders.map((order) =>
        order.id === orderId ? { ...order, ...updatedOrder } : order
      );

      setOrders(finalOrders);
      setStats((prev) => {
        if (!prev) return prev;

        return buildStats(users, finalOrders, prev.totalProducts);
      });

      alert(result.message || "Order updated successfully.");
      await fetchAdminData();
    } catch (error) {
      setOrders(previousOrders);

      alert(error instanceof Error ? error.message : "Order update failed.");
    } finally {
      setUpdatingOrder(null);
    }
  };

  const filteredUsers = useMemo(() => {
    return users.filter((user) => {
      const query = search.toLowerCase();

      return (
        (user.full_name || "").toLowerCase().includes(query) ||
        user.email.toLowerCase().includes(query) ||
        user.role.toLowerCase().includes(query)
      );
    });
  }, [users, search]);

  const totalRevenue = orders.reduce(
    (sum, order) => sum + Number(order.total_amount || 0),
    0
  );

  const statCards = [
    {
      label: "Total Users",
      value: stats?.totalUsers || 0,
      icon: "👥",
      tone: "from-blue-500/20 to-blue-500/5 text-blue-300",
    },
    {
      label: "Farmers",
      value: stats?.totalFarmers || 0,
      icon: "🧑‍🌾",
      tone: "from-amber-500/20 to-amber-500/5 text-amber-300",
    },
    {
      label: "Buyers",
      value: stats?.totalBuyers || 0,
      icon: "🛒",
      tone: "from-indigo-500/20 to-indigo-500/5 text-indigo-300",
    },
    {
      label: "Products",
      value: stats?.totalProducts || 0,
      icon: "🥬",
      tone: "from-[#5DBB63]/25 to-[#5DBB63]/5 text-[#5DBB63]",
    },
    {
      label: "Orders",
      value: stats?.totalOrders || 0,
      icon: "📦",
      tone: "from-purple-500/20 to-purple-500/5 text-purple-300",
    },
    {
      label: "Pending",
      value: stats?.pendingOrders || 0,
      icon: "⏳",
      tone: "from-rose-500/20 to-rose-500/5 text-rose-300",
    },
  ];

  if (loading) {
    return (
      <main className="flex min-h-screen flex-col items-center justify-center gap-6 bg-[#07100B] text-white">
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
            Syncing users, products, and orders...
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
        <div className="absolute inset-0 bg-[linear-gradient(rgba(255,255,255,0.025)_1px,transparent_1px),linear-gradient(90deg,rgba(255,255,255,0.025)_1px,transparent_1px)] bg-[size:54px_54px]" />
      </div>

      <header className="sticky top-0 z-50 border-b border-white/10 bg-[#07100B]/75 px-6 py-5 shadow-2xl shadow-black/20 backdrop-blur-2xl">
        <div className="mx-auto flex max-w-[1400px] items-center justify-between">
          <div className="flex items-center gap-4">
            <div className="group relative flex h-12 w-12 items-center justify-center rounded-2xl bg-white shadow-[0_0_35px_rgba(93,187,99,0.35)] transition-all duration-500 hover:scale-110 hover:rotate-3">
              <GreenGuardIcon className="h-10 w-10" />
            </div>

            <div>
              <h1 className="text-2xl font-black tracking-tighter text-white">
                GreenGuard AI
              </h1>
              <p className="text-[10px] font-bold uppercase tracking-[3px] text-[#5DBB63]">
                Admin Command Center
              </p>
            </div>
          </div>

          <div className="flex items-center gap-4">
            <div className="hidden items-center gap-3 rounded-2xl border border-white/10 bg-white/[0.04] px-5 py-2 md:flex">
              <div className="flex h-9 w-9 items-center justify-center rounded-full bg-[#5DBB63]/15 text-sm font-black text-[#5DBB63]">
                {adminName[0] || "A"}
              </div>
              <div>
                <p className="text-sm font-bold text-white">{adminName}</p>
                <p className="-mt-0.5 text-[10px] text-white/40">
                  Administrator
                </p>
              </div>
            </div>

            <button
              onClick={handleLogout}
              className="rounded-2xl border border-red-500/30 bg-red-500/10 px-5 py-2.5 text-sm font-black text-red-300 shadow-lg shadow-red-950/20 transition-all duration-300 hover:-translate-y-0.5 hover:bg-red-500 hover:text-white active:scale-95"
            >
              Logout
            </button>
          </div>
        </div>
      </header>

      <div className="relative z-10 mx-auto w-full max-w-[1400px] px-6 pt-10">
        <section className="relative mb-10 overflow-hidden rounded-[2rem] border border-[#5DBB63]/20 bg-gradient-to-br from-[#132019]/95 via-[#0D1711]/95 to-[#07100B]/95 p-10 shadow-2xl shadow-black/30">
          <div className="absolute right-0 top-0 h-48 w-48 rounded-full bg-[#5DBB63]/10 blur-3xl" />

          <div className="relative z-10">
            <div className="mb-5 inline-flex rounded-full border border-[#5DBB63]/20 bg-[#5DBB63]/10 px-4 py-2 text-xs font-black uppercase tracking-[3px] text-[#5DBB63]">
              Live System Overview
            </div>

            <h2 className="max-w-3xl text-5xl font-black tracking-tighter text-white md:text-6xl">
              Welcome back, Admin
            </h2>

            <p className="mt-4 max-w-2xl text-lg text-white/55">
              Manage users, monitor orders, verify payments, and supervise
              marketplace activity.
            </p>

            <div className="mt-7 flex flex-wrap gap-3">
              <div className="rounded-2xl border border-white/10 bg-white/[0.04] px-5 py-3 text-sm text-white/70">
                Pending Orders:{" "}
                <span className="font-black text-[#5DBB63]">
                  {stats?.pendingOrders || 0}
                </span>
              </div>

              <div className="rounded-2xl border border-white/10 bg-white/[0.04] px-5 py-3 text-sm text-white/70">
                Revenue:{" "}
                <span className="font-black text-[#5DBB63]">
                  ₱{totalRevenue.toLocaleString()}
                </span>
              </div>
            </div>
          </div>
        </section>

        <section className="mb-12 grid grid-cols-2 gap-5 md:grid-cols-3 lg:grid-cols-6">
          {statCards.map((stat, index) => (
            <div
              key={stat.label}
              className="group rounded-[1.7rem] border border-white/10 bg-white/[0.035] p-5 shadow-xl shadow-black/10 backdrop-blur-xl transition-all duration-500 hover:-translate-y-2 hover:border-[#5DBB63]/40 hover:bg-white/[0.06] hover:shadow-[#5DBB63]/10"
              style={{ transitionDelay: `${index * 25}ms` }}
            >
              <div
                className={`mb-5 flex h-12 w-12 items-center justify-center rounded-2xl bg-gradient-to-br ${stat.tone}`}
              >
                <span className="text-xl">{stat.icon}</span>
              </div>

              <p className="text-4xl font-black tracking-tighter text-white">
                {stat.value}
              </p>

              <p className="mt-1 text-xs font-bold uppercase tracking-[2px] text-white/40">
                {stat.label}
              </p>
            </div>
          ))}
        </section>

        <section className="mb-10 overflow-hidden rounded-[2rem] border border-white/10 bg-white/[0.035] shadow-2xl shadow-black/20 backdrop-blur-xl">
          <div className="flex flex-col gap-4 border-b border-white/10 px-8 py-7 md:flex-row md:items-center md:justify-between">
            <div>
              <h3 className="text-2xl font-black tracking-tight text-white">
                Fulfillment Center
              </h3>
              <p className="mt-1 text-sm text-white/45">
                Update delivery status, payment status, and view proof images.
              </p>
            </div>

            <div className="rounded-full border border-white/10 bg-white/[0.04] px-4 py-2 text-xs font-mono text-white/60">
              {orders.length} orders
            </div>
          </div>

          <div className="overflow-x-auto">
            <table className="w-full min-w-[1000px]">
              <thead className="bg-black/20 text-xs uppercase tracking-[2px] text-white/35">
                <tr>
                  <th className="px-8 py-5 text-left">Customer</th>
                  <th className="px-8 py-5 text-left">Amount</th>
                  <th className="px-8 py-5 text-left">Payment</th>
                  <th className="px-8 py-5 text-left">Order Status</th>
                  <th className="px-8 py-5 text-left">Proof</th>
                  <th className="px-8 py-5 text-right">Quick Actions</th>
                </tr>
              </thead>

              <tbody className="divide-y divide-white/10">
                {orders.length === 0 ? (
                  <tr>
                    <td
                      colSpan={6}
                      className="py-20 text-center text-sm text-white/45"
                    >
                      No orders yet.
                    </td>
                  </tr>
                ) : (
                  orders.map((order) => {
                    const paymentUpdating =
                      updatingOrder === `${order.id}-payment_status`;
                    const statusUpdating =
                      updatingOrder === `${order.id}-status`;

                    return (
                      <tr
                        key={order.id}
                        className="transition-colors duration-300 hover:bg-white/[0.035]"
                      >
                        <td className="px-8 py-6">
                          <p className="font-bold text-white">
                            {order.shipping_name || "Unknown Customer"}
                          </p>
                          <p className="mt-1 text-xs text-white/35">
                            {new Date(order.created_at).toLocaleDateString()}
                          </p>
                          <p className="mt-1 text-xs text-white/25">
                            {order.order_code || order.id}
                          </p>
                        </td>

                        <td className="px-8 py-6">
                          <p className="font-mono text-xl font-black text-[#5DBB63]">
                            ₱{Number(order.total_amount || 0).toLocaleString()}
                          </p>
                        </td>

                        <td className="px-8 py-6">
                          <select
                            value={order.payment_status || "Unpaid"}
                            disabled={paymentUpdating}
                            onChange={(event) =>
                              handleOrderUpdate(
                                order.id,
                                "payment_status",
                                event.target.value
                              )
                            }
                            className="rounded-2xl border border-white/10 bg-[#07100B] px-4 py-2 text-sm font-bold text-white outline-none transition-all focus:border-[#5DBB63]/60 disabled:opacity-50"
                          >
                            {PAYMENT_STATUSES.map((status) => (
                              <option key={status} value={status}>
                                {status}
                              </option>
                            ))}
                          </select>
                        </td>

                        <td className="px-8 py-6">
                          <select
                            value={order.status || "Pending"}
                            disabled={statusUpdating}
                            onChange={(event) =>
                              handleOrderUpdate(
                                order.id,
                                "status",
                                event.target.value
                              )
                            }
                            className="rounded-2xl border border-[#5DBB63]/20 bg-[#07100B] px-4 py-2 text-sm font-bold text-[#5DBB63] outline-none transition-all focus:border-[#5DBB63]/60 disabled:opacity-50"
                          >
                            {ORDER_STATUSES.map((status) => (
                              <option key={status} value={status}>
                                {status}
                              </option>
                            ))}
                          </select>
                        </td>

                        <td className="px-8 py-6">
                          {order.proof_image_url ? (
                            <a
                              href={order.proof_image_url}
                              target="_blank"
                              rel="noreferrer"
                              className="rounded-2xl border border-[#5DBB63]/30 bg-[#5DBB63]/10 px-4 py-2 text-sm font-black text-[#5DBB63] transition hover:bg-[#5DBB63] hover:text-[#07100B]"
                            >
                              View Proof
                            </a>
                          ) : (
                            <span className="text-sm text-white/35">
                              No proof
                            </span>
                          )}
                        </td>

                        <td className="px-8 py-6">
                          <div className="flex justify-end gap-2">
                            <button
                              onClick={() =>
                                handleOrderUpdate(
                                  order.id,
                                  "payment_status",
                                  "Paid"
                                )
                              }
                              disabled={paymentUpdating}
                              className="rounded-2xl border border-[#5DBB63]/30 bg-[#5DBB63]/10 px-4 py-2 text-xs font-black text-[#5DBB63] transition hover:bg-[#5DBB63] hover:text-[#07100B] disabled:opacity-40"
                            >
                              Mark Paid
                            </button>

                            <button
                              onClick={() =>
                                handleOrderUpdate(
                                  order.id,
                                  "status",
                                  "Delivered"
                                )
                              }
                              disabled={statusUpdating}
                              className="rounded-2xl border border-blue-500/30 bg-blue-500/10 px-4 py-2 text-xs font-black text-blue-300 transition hover:bg-blue-500 hover:text-white disabled:opacity-40"
                            >
                              Delivered
                            </button>

                            <button
                              onClick={() =>
                                handleOrderUpdate(
                                  order.id,
                                  "status",
                                  "Cancelled"
                                )
                              }
                              disabled={statusUpdating}
                              className="rounded-2xl border border-red-500/30 bg-red-500/10 px-4 py-2 text-xs font-black text-red-300 transition hover:bg-red-500 hover:text-white disabled:opacity-40"
                            >
                              Cancel
                            </button>
                          </div>
                        </td>
                      </tr>
                    );
                  })
                )}
              </tbody>
            </table>
          </div>
        </section>

        <section className="overflow-hidden rounded-[2rem] border border-white/10 bg-white/[0.035] shadow-2xl shadow-black/20 backdrop-blur-xl">
          <div className="border-b border-white/10 px-8 py-7">
            <div className="flex flex-col gap-4 lg:flex-row lg:items-center lg:justify-between">
              <div>
                <h3 className="text-2xl font-black tracking-tight text-white">
                  User Management
                </h3>
                <p className="mt-1 text-sm text-white/45">
                  Change roles and remove test or invalid accounts.
                </p>
              </div>

              <input
                type="text"
                placeholder="Search users..."
                value={search}
                onChange={(event) => setSearch(event.target.value)}
                className="w-full rounded-2xl border border-white/10 bg-black/20 px-5 py-3 text-sm text-white outline-none transition-all duration-300 placeholder:text-white/30 focus:border-[#5DBB63]/50 focus:ring-4 focus:ring-[#5DBB63]/10 lg:w-[360px]"
              />
            </div>
          </div>

          <div className="max-h-[650px] overflow-y-auto px-6 py-6">
            {filteredUsers.length === 0 ? (
              <div className="flex min-h-[220px] items-center justify-center rounded-3xl border border-dashed border-white/10 bg-black/10 text-sm text-white/40">
                No users found.
              </div>
            ) : (
              <div className="grid gap-4">
                {filteredUsers.map((user) => {
                  const normalizedRole = String(
                    user.role || "buyer"
                  ).toLowerCase();

                  return (
                    <div
                      key={user.id}
                      className="group rounded-[1.5rem] border border-white/10 bg-black/10 p-5 transition-all duration-500 hover:-translate-y-1 hover:border-[#5DBB63]/30 hover:bg-white/[0.04]"
                    >
                      <div className="flex flex-col gap-5 xl:flex-row xl:items-center xl:justify-between">
                        <div className="flex items-center gap-4">
                          <div className="flex h-14 w-14 shrink-0 items-center justify-center rounded-2xl bg-gradient-to-br from-[#5DBB63]/20 to-[#2F6B3B]/10 text-lg font-black uppercase text-[#5DBB63]">
                            {(user.full_name || user.email || "U").charAt(0)}
                          </div>

                          <div>
                            <div className="flex flex-wrap items-center gap-3">
                              <h4 className="text-lg font-black text-white">
                                {user.full_name || "Unnamed User"}
                              </h4>

                              <span className="rounded-full border border-[#5DBB63]/20 bg-[#5DBB63]/10 px-3 py-1 text-[11px] font-black uppercase tracking-[2px] text-[#5DBB63]">
                                {normalizedRole}
                              </span>
                            </div>

                            <p className="mt-1 text-sm text-white/45">
                              {user.email}
                            </p>
                            <p className="mt-1 text-xs text-white/25">
                              ID: {user.id}
                            </p>
                          </div>
                        </div>

                        <div className="flex flex-wrap gap-2">
                          {USER_ROLES.map((role) => (
                            <button
                              key={role}
                              onClick={() => handleRoleChange(user.id, role)}
                              disabled={
                                updatingRole === user.id ||
                                normalizedRole === role
                              }
                              className="rounded-2xl border border-[#5DBB63]/30 bg-[#5DBB63]/10 px-4 py-2 text-sm font-black text-[#5DBB63] transition-all duration-300 hover:-translate-y-0.5 hover:bg-[#5DBB63] hover:text-[#07100B] disabled:cursor-not-allowed disabled:opacity-40"
                            >
                              {updatingRole === user.id
                                ? "Updating..."
                                : `Make ${role}`}
                            </button>
                          ))}

                          <button
                            onClick={() =>
                              handleDeleteUser(user.id, user.email)
                            }
                            disabled={deletingUser === user.id}
                            className="rounded-2xl border border-red-500/30 bg-red-500/10 px-4 py-2 text-sm font-black text-red-300 transition-all duration-300 hover:-translate-y-0.5 hover:bg-red-500 hover:text-white disabled:cursor-not-allowed disabled:opacity-40"
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
      </div>
    </main>
  );
}