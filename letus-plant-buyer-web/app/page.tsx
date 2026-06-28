"use client";

import { useEffect, useMemo, useState } from "react";
import { useRouter } from "next/navigation";
import { supabase } from "@/lib/supabase";

// --- TYPES ---
type Product = {
  id: number;
  name: string;
  farmer: string;
  category: string;
  price: number;
  stock: number;
  badge: string;
  image: string;
  freshnessInfo: string;
  createdAt?: string;
};

type CartItem = Product & { quantity: number };

type OrderItem = {
  productId: number;
  productName: string;
  price: number;
  quantity: number;
  subtotal: number;
};

type Order = {
  id: string;
  date: string;
  fullName: string;
  email: string;
  phone: string;
  address: string;
  city: string;
  postalCode: string;
  paymentMethod: string;
  deliveryMethod: string;
  items: OrderItem[];
  total_amount: number;
  status: string;
};

type UserRole = "buyer" | "farmer";

type AccountUser = {
  id: string;
  name: string;
  email: string;
  role: UserRole;
};

type FarmerToolTab = "sell" | "listings" | "health" | "orders";

type FarmerProduct = {
  id: number | string;
  name?: string | null;
  category?: string | null;
  price?: number | string | null;
  stock?: number | string | null;
  farmer_id?: string | null;
  status?: string | null;
  image?: string | null;
  image_url?: string | null;
  description?: string | null;
  freshness_info?: string | null;
  created_at?: string | null;
};

type FarmerOrder = {
  id: string;
  order_code?: string | null;
  user_id?: string | null;
  farmer_id?: string | null;
  shipping_name?: string | null;
  email?: string | null;
  shipping_phone?: string | null;
  shipping_address?: string | null;
  status?: string | null;
  delivery_status?: string | null;
  payment_status?: string | null;
  total_amount?: number | string | null;
  proof_image_url?: string | null;
  delivery_proof_url?: string | null;
  created_at?: string | null;
};

type HealthLog = {
  id: string;
  user_id?: string | null;
  disease_name?: string | null;
  result?: string | null;
  confidence_score?: number | string | null;
  confidence?: number | string | null;
  temperature?: number | string | null;
  temp?: number | string | null;
  weather_condition?: string | null;
  weather?: string | null;
  location?: string | null;
  image_url?: string | null;
  captured_at?: string | null;
  created_at?: string | null;
};

const statusColors: Record<string, string> = {
  Pending: "bg-amber-100 text-amber-700",
  Confirmed: "bg-blue-100 text-blue-700",
  Preparing: "bg-orange-100 text-orange-700",
  Shipped: "bg-purple-100 text-purple-700",
  Delivered: "bg-green-100 text-green-700",
  Completed: "bg-green-100 text-green-700",
  Cancelled: "bg-red-100 text-red-700",
};

const defaultProductImage =
  "https://images.unsplash.com/photo-1540420773420-3366772f4999?q=80&w=1200&auto=format&fit=crop";

function formatMoney(value: number | string | null | undefined) {
  return Number(value || 0).toLocaleString();
}

function formatDate(value?: string | null) {
  if (!value) return "No date";

  const date = new Date(value);

  if (Number.isNaN(date.getTime())) return value;

  return date.toLocaleDateString();
}

function getDiseaseName(log: HealthLog) {
  return log.disease_name || log.result || "Unknown Result";
}

function getConfidence(log: HealthLog) {
  const raw = log.confidence_score ?? log.confidence;

  if (raw === null || raw === undefined) return "N/A";

  const value = Number(raw);

  if (Number.isNaN(value)) return String(raw);

  if (value <= 1) return `${(value * 100).toFixed(1)}%`;

  return `${value.toFixed(1)}%`;
}

function getTemperature(log: HealthLog) {
  const raw = log.temperature ?? log.temp;

  if (raw === null || raw === undefined) return "N/A";

  const value = Number(raw);

  if (Number.isNaN(value)) return String(raw);

  return `${value.toFixed(1)}°C`;
}

function statusTone(status?: string | null) {
  const value = String(status || "").toLowerCase();

  if (
    value.includes("completed") ||
    value.includes("delivered") ||
    value.includes("paid") ||
    value.includes("received") ||
    value.includes("available")
  ) {
    return "border-green-200 bg-green-50 text-green-700";
  }

  if (value.includes("cancel") || value.includes("rejected")) {
    return "border-red-200 bg-red-50 text-red-700";
  }

  if (
    value.includes("pending") ||
    value.includes("confirmed") ||
    value.includes("preparing") ||
    value.includes("shipped")
  ) {
    return "border-amber-200 bg-amber-50 text-amber-700";
  }

  return "border-gray-200 bg-gray-50 text-gray-600";
}

export default function HomePage() {
  const router = useRouter();

  const [currentView, setCurrentView] = useState<
    "home" | "shop" | "checkout" | "orders" | "about"
  >("home");

  const [products, setProducts] = useState<Product[]>([]);
  const [orders, setOrders] = useState<Order[]>([]);
  const [cart, setCart] = useState<CartItem[]>([]);
  const [selectedProduct, setSelectedProduct] = useState<Product | null>(null);

  const [search, setSearch] = useState("");
  const [category, setCategory] = useState("All Categories");
  const [sortBy, setSortBy] = useState("Default");

  const [authOpen, setAuthOpen] = useState(false);
  const [authMode, setAuthMode] = useState<"login" | "register" | "reset">(
    "login"
  );
  const [authLoading, setAuthLoading] = useState(false);
  const [account, setAccount] = useState<AccountUser | null>(null);

  const [checkoutForm, setCheckoutForm] = useState({
    fullName: "",
    email: "",
    phone: "",
    address: "",
    city: "",
    postalCode: "",
    paymentMethod: "Cash on Delivery",
    deliveryMethod: "Delivery",
  });

  const [authForm, setAuthForm] = useState({
    name: "",
    email: "",
    password: "",
  });

  const [message, setMessage] = useState("");
  const [loadingOrder, setLoadingOrder] = useState(false);

  // Farmer Tools
  const [farmerToolsOpen, setFarmerToolsOpen] = useState(false);
  const [farmerTab, setFarmerTab] = useState<FarmerToolTab>("sell");
  const [farmerProducts, setFarmerProducts] = useState<FarmerProduct[]>([]);
  const [farmerOrders, setFarmerOrders] = useState<FarmerOrder[]>([]);
  const [healthLogs, setHealthLogs] = useState<HealthLog[]>([]);
  const [farmerLoading, setFarmerLoading] = useState(false);
  const [savingProduct, setSavingProduct] = useState(false);

  const [sellForm, setSellForm] = useState({
    name: "",
    category: "Fresh Lettuce",
    price: "",
    stock: "",
    description: "",
    imageUrl: "",
    location: "",
  });

  const isFarmer = account?.role === "farmer";

  useEffect(() => {
    loadProducts();

    const savedCart = localStorage.getItem("letusplant-cart");
    if (savedCart) {
      setCart(JSON.parse(savedCart));
    }

    async function checkSession() {
      const {
        data: { session },
      } = await supabase.auth.getSession();

      if (!session?.user) {
        return;
      }

      const { data: profile, error: profileError } = await supabase
        .from("users")
        .select("full_name, email, role")
        .eq("id", session.user.id)
        .maybeSingle();

      if (profileError) {
        await supabase.auth.signOut();
        setAccount(null);
        showNotification("Unable to verify your account profile.");
        return;
      }

      const role = String(
        profile?.role || session.user.user_metadata?.role || "buyer"
      ).toLowerCase();

      if (role === "admin") {
        router.push("/admin");
        return;
      }

      if (role !== "buyer" && role !== "farmer") {
        await supabase.auth.signOut();
        setAccount(null);
        showNotification("Invalid account role.");
        return;
      }

      setAccount({
        id: session.user.id,
        name:
          profile?.full_name ||
          session.user.user_metadata?.full_name ||
          (role === "farmer" ? "Farmer" : "Buyer"),
        email: profile?.email || session.user.email || "",
        role: role as UserRole,
      });

      if (role === "farmer") {
        setFarmerToolsOpen(true);
      }
    }

    checkSession();
  }, [router]);

  useEffect(() => {
    localStorage.setItem("letusplant-cart", JSON.stringify(cart));
  }, [cart]);

  useEffect(() => {
    if (account) {
      setCheckoutForm((prev) => ({
        ...prev,
        fullName: prev.fullName || account.name,
        email: prev.email || account.email,
      }));

      loadOrders();

      if (account.role === "farmer") {
        loadFarmerToolsData(account.id);
      }
    } else {
      setOrders([]);
      setFarmerProducts([]);
      setFarmerOrders([]);
      setHealthLogs([]);
    }
  }, [account]);

  async function loadProducts() {
    try {
      const res = await fetch("/api?type=products");
      const json = await res.json();

      if (json.success) {
        setProducts(json.data);
      }
    } catch (e) {
      console.error("Failed to load products:", e);
    }
  }

  async function loadOrders() {
    if (!account?.id) {
      return;
    }

    try {
      const res = await fetch(`/api?type=orders&userId=${account.id}`);
      const json = await res.json();

      if (json.success) {
        setOrders(json.data);
      }
    } catch (e) {
      console.error("Failed to load orders:", e);
    }
  }

  async function loadFarmerToolsData(farmerId = account?.id) {
    if (!farmerId) return;

    setFarmerLoading(true);

    try {
      const [productsResult, ordersResult, logsResult] = await Promise.all([
        supabase
          .from("products")
          .select("*")
          .eq("farmer_id", farmerId)
          .order("created_at", { ascending: false }),

        supabase
          .from("orders")
          .select("*")
          .eq("farmer_id", farmerId)
          .order("created_at", { ascending: false }),

        supabase
          .from("diagnostic_logs")
          .select("*")
          .eq("user_id", farmerId)
          .order("created_at", { ascending: false }),
      ]);

      if (productsResult.error) throw new Error(productsResult.error.message);
      if (ordersResult.error) throw new Error(ordersResult.error.message);
      if (logsResult.error) throw new Error(logsResult.error.message);

      setFarmerProducts((productsResult.data as FarmerProduct[]) || []);
      setFarmerOrders((ordersResult.data as FarmerOrder[]) || []);
      setHealthLogs((logsResult.data as HealthLog[]) || []);
    } catch (error) {
      showNotification(
        error instanceof Error
          ? error.message
          : "Failed to load farmer tools data."
      );
    } finally {
      setFarmerLoading(false);
    }
  }

  const filteredProducts = useMemo(() => {
    let data = [...products];

    if (search.trim()) {
      data = data.filter((p) =>
        p.name.toLowerCase().includes(search.toLowerCase())
      );
    }

    if (category !== "All Categories") {
      data = data.filter((p) => p.category === category);
    }

    if (sortBy === "Price: Low to High") {
      data.sort((a, b) => a.price - b.price);
    } else if (sortBy === "Price: High to Low") {
      data.sort((a, b) => b.price - a.price);
    }

    return data;
  }, [products, search, category, sortBy]);

  const cartCount = cart.reduce((sum, item) => sum + item.quantity, 0);
  const subtotal = cart.reduce(
    (sum, item) => sum + item.price * item.quantity,
    0
  );
  const shipping =
    checkoutForm.deliveryMethod === "Delivery" && cart.length > 0 ? 50 : 0;
  const total = subtotal + shipping;

  const farmerRevenue = farmerOrders.reduce((sum, order) => {
    const status = String(order.status || "").toLowerCase();

    if (status.includes("cancel")) return sum;

    return sum + Number(order.total_amount || 0);
  }, 0);

  const farmerPendingOrders = farmerOrders.filter(
    (order) => String(order.status || "").toLowerCase() === "pending"
  ).length;

  const latestHealthLog = healthLogs[0];

  function addToCart(product: Product) {
    setCart((prev) => {
      const existing = prev.find((item) => item.id === product.id);

      if (existing) {
        return prev.map((item) =>
          item.id === product.id
            ? {
                ...item,
                quantity: Math.min(item.quantity + 1, product.stock),
              }
            : item
        );
      }

      return [...prev, { ...product, quantity: 1 }];
    });

    showNotification(`Added ${product.name} to cart`);
  }

  function updateQuantity(productId: number, delta: number) {
    setCart((prev) =>
      prev
        .map((item) => {
          if (item.id !== productId) {
            return item;
          }

          return {
            ...item,
            quantity: item.quantity + delta,
          };
        })
        .filter((item) => item.quantity > 0)
    );
  }

  function showNotification(msg: string) {
    setMessage(msg);
    setTimeout(() => setMessage(""), 3500);
  }

  function getFriendlyAuthMessage(messageValue: string) {
    const lower = messageValue.toLowerCase();

    if (lower.includes("invalid login credentials")) {
      return "Invalid email or password. Please check your credentials.";
    }

    if (
      lower.includes("already registered") ||
      lower.includes("user already registered") ||
      lower.includes("already exists") ||
      lower.includes("duplicate")
    ) {
      return "This email is already registered. Please log in instead.";
    }

    if (lower.includes("email not confirmed")) {
      return "Please confirm your email before logging in.";
    }

    return messageValue;
  }

  async function handleLogout() {
    await supabase.auth.signOut();
    setAccount(null);
    setFarmerToolsOpen(false);
    setFarmerProducts([]);
    setFarmerOrders([]);
    setHealthLogs([]);
    showNotification("Logged out successfully");
    setCurrentView("home");
  }

  async function handleResetRequest() {
    const email = authForm.email.trim();

    if (!email) {
      showNotification("Please enter your email first.");
      return;
    }

    setAuthLoading(true);

    const { error } = await supabase.auth.resetPasswordForEmail(email, {
      redirectTo: `${window.location.origin}/reset-password`,
    });

    if (error) {
      showNotification(getFriendlyAuthMessage(error.message));
    } else {
      showNotification("Password reset link sent! Check your inbox.");
      setAuthOpen(false);
      setAuthForm({ name: "", email: "", password: "" });
    }

    setAuthLoading(false);
  }

  async function handleAuthSubmit(e: React.FormEvent) {
    e.preventDefault();

    if (authMode === "reset") {
      await handleResetRequest();
      return;
    }

    const cleanName = authForm.name.trim();
    const cleanEmail = authForm.email.trim();
    const cleanPassword = authForm.password;

    if (!cleanEmail || !cleanPassword) {
      showNotification("Email and password required.");
      return;
    }

    if (authMode === "register" && !cleanName) {
      showNotification("Name is required.");
      return;
    }

    if (authMode === "register" && cleanPassword.length < 6) {
      showNotification("Password must be at least 6 characters.");
      return;
    }

    setAuthLoading(true);

    if (authMode === "register") {
      const { data: existingProfile } = await supabase
        .from("users")
        .select("id")
        .eq("email", cleanEmail)
        .maybeSingle();

      if (existingProfile) {
        showNotification(
          "This email is already registered. Please log in instead."
        );
        setAuthLoading(false);
        return;
      }

      const { data, error } = await supabase.auth.signUp({
        email: cleanEmail,
        password: cleanPassword,
        options: {
          data: {
            full_name: cleanName,
            role: "buyer",
          },
        },
      });

      if (error) {
        showNotification(getFriendlyAuthMessage(error.message));
        setAuthLoading(false);
        return;
      }

      if (!data.user) {
        showNotification("Registration failed. Please try again.");
        setAuthLoading(false);
        return;
      }

      const { error: profileError } = await supabase.from("users").insert([
        {
          id: data.user.id,
          full_name: cleanName,
          email: cleanEmail,
          role: "buyer",
        },
      ]);

      if (profileError) {
        showNotification(getFriendlyAuthMessage(profileError.message));
        setAuthLoading(false);
        return;
      }

      setAccount({
        id: data.user.id,
        name: cleanName,
        email: cleanEmail,
        role: "buyer",
      });

      setAuthOpen(false);
      setAuthForm({ name: "", email: "", password: "" });
      showNotification("Welcome to GreenGuard AI!");
      setAuthLoading(false);
      return;
    }

    const { data, error } = await supabase.auth.signInWithPassword({
      email: cleanEmail,
      password: cleanPassword,
    });

    if (error) {
      showNotification(getFriendlyAuthMessage(error.message));
      setAuthLoading(false);
      return;
    }

    if (!data.user) {
      showNotification("Login failed. Please try again.");
      setAuthLoading(false);
      return;
    }

    const { data: profile, error: profileError } = await supabase
      .from("users")
      .select("full_name, email, role")
      .eq("id", data.user.id)
      .maybeSingle();

    if (profileError) {
      await supabase.auth.signOut();
      showNotification("Unable to verify your account profile.");
      setAuthLoading(false);
      return;
    }

    const role = String(
      profile?.role || data.user.user_metadata?.role || "buyer"
    ).toLowerCase();

    if (role === "admin") {
      setAuthOpen(false);
      setAuthForm({ name: "", email: "", password: "" });
      setAuthLoading(false);
      router.push("/admin");
      return;
    }

    if (role !== "buyer" && role !== "farmer") {
      await supabase.auth.signOut();
      setAccount(null);
      showNotification("Invalid role for this website.");
      setAuthLoading(false);
      return;
    }

    setAccount({
      id: data.user.id,
      name:
        profile?.full_name ||
        data.user.user_metadata?.full_name ||
        (role === "farmer" ? "Farmer" : "Buyer"),
      email: profile?.email || data.user.email || cleanEmail,
      role: role as UserRole,
    });

    if (role === "farmer") {
      setFarmerToolsOpen(true);
      setCurrentView("shop");
      showNotification("Welcome back, Farmer. Farmer Tools enabled.");
    } else {
      showNotification("Welcome back!");
    }

    setAuthOpen(false);
    setAuthForm({ name: "", email: "", password: "" });
    setAuthLoading(false);
  }

  async function handlePublishProduct(e: React.FormEvent) {
    e.preventDefault();

    if (!account || account.role !== "farmer") {
      showNotification("Only farmer accounts can sell products.");
      return;
    }

    const name = sellForm.name.trim();
    const categoryValue = sellForm.category.trim() || "Fresh Lettuce";
    const price = Number(sellForm.price);
    const stock = Number(sellForm.stock);
    const description =
      sellForm.description.trim() || "Fresh lettuce crop from local farmer.";
    const imageValue = sellForm.imageUrl.trim() || defaultProductImage;

    if (!name) {
      showNotification("Product name is required.");
      return;
    }

    if (!price || price <= 0) {
      showNotification("Valid price is required.");
      return;
    }

    if (!stock || stock <= 0) {
      showNotification("Valid stock is required.");
      return;
    }

    setSavingProduct(true);

    try {
      const payload = {
        name,
        category: categoryValue,
        price,
        stock,
        farmer_id: account.id,
        farmer: account.name,
        farmer_name: account.name,
        badge: "Farmer Listed",
        description,
        freshness_info: description,
        image: imageValue,
        image_url: imageValue,
        location: sellForm.location.trim() || "Local Farm",
        status: "Available",
        updated_at: new Date().toISOString(),
      };

      const { error } = await supabase.from("products").insert([payload]);

      if (error) {
        throw new Error(error.message);
      }

      setSellForm({
        name: "",
        category: "Fresh Lettuce",
        price: "",
        stock: "",
        description: "",
        imageUrl: "",
        location: "",
      });

      await Promise.all([loadProducts(), loadFarmerToolsData(account.id)]);

      setFarmerTab("listings");
      showNotification("Product published successfully.");
    } catch (error) {
      showNotification(
        error instanceof Error ? error.message : "Failed to publish product."
      );
    } finally {
      setSavingProduct(false);
    }
  }

  async function handleCheckout() {
    if (!account) {
      showNotification("You must be logged in to place an order.");
      setAuthMode("login");
      setAuthOpen(true);
      return;
    }

    if (cart.length === 0) {
      showNotification("Your cart is empty");
      return;
    }

    if (!checkoutForm.fullName || !checkoutForm.phone || !checkoutForm.email) {
      showNotification("Please fill in your contact details.");
      return;
    }

    if (
      checkoutForm.deliveryMethod === "Delivery" &&
      (!checkoutForm.address || !checkoutForm.city || !checkoutForm.postalCode)
    ) {
      showNotification("Please provide your full delivery address.");
      return;
    }

    setLoadingOrder(true);

    const payload = {
      ...checkoutForm,
      userId: account.id,
      items: cart.map((item) => ({
        productId: item.id,
        productName: item.name,
        price: item.price,
        quantity: item.quantity,
      })),
    };

    try {
      const res = await fetch("/api?type=create-order", {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
        },
        body: JSON.stringify(payload),
      });

      const json = await res.json();

      if (json.success) {
        setCart([]);
        await loadOrders();

        if (account.role === "farmer") {
          await loadFarmerToolsData(account.id);
        }

        showNotification("Order placed successfully! 🎉");
        setCurrentView("orders");
        window.scrollTo({ top: 0, behavior: "smooth" });
      } else {
        showNotification(json.message || "Checkout failed. Check database.");
      }
    } catch (error) {
      showNotification("An error occurred during checkout");
    }

    setLoadingOrder(false);
  }

  // ==========================================
  // FARMER TOOLS
  // ==========================================

  const renderFarmerTools = () => {
    if (!isFarmer) return null;

    if (!farmerToolsOpen) {
      return (
        <div className="mx-auto mb-8 max-w-7xl px-4 sm:px-6 lg:px-8">
          <button
            onClick={() => setFarmerToolsOpen(true)}
            className="flex w-full items-center justify-between rounded-[28px] border border-green-200 bg-white px-6 py-4 text-left shadow-sm transition-all hover:-translate-y-1 hover:shadow-xl"
          >
            <div>
              <p className="text-xs font-black uppercase tracking-[3px] text-[#2F6B3B]">
                Farmer Account Detected
              </p>
              <h3 className="mt-1 text-xl font-black text-[#1E2A1F]">
                Open Farmer Tools
              </h3>
              <p className="mt-1 text-sm text-[#5C6B5D]">
                Sell crops, monitor health logs, and manage buyer orders.
              </p>
            </div>

            <div className="rounded-full bg-[#2F6B3B] px-5 py-2 text-sm font-black text-white">
              Open
            </div>
          </button>
        </div>
      );
    }

    return (
      <div className="mx-auto mb-10 max-w-7xl px-4 sm:px-6 lg:px-8">
        <section className="overflow-hidden rounded-[36px] border border-green-200 bg-white shadow-xl shadow-green-900/10">
          <div className="border-b border-green-100 bg-gradient-to-br from-[#EFFAF1] to-white p-6">
            <div className="flex flex-col gap-5 lg:flex-row lg:items-center lg:justify-between">
              <div>
                <p className="text-xs font-black uppercase tracking-[3px] text-[#2F6B3B]">
                  Farmer Tools
                </p>
                <h2 className="mt-2 text-3xl font-black tracking-tight text-[#1E2A1F]">
                  Sell crops and monitor your farm
                </h2>
                <p className="mt-2 max-w-2xl text-sm leading-6 text-[#5C6B5D]">
                  This panel is visible only to farmer accounts. You can
                  minimize it anytime and continue browsing the marketplace.
                </p>
              </div>

              <div className="flex flex-wrap gap-3">
                <button
                  onClick={() => loadFarmerToolsData()}
                  disabled={farmerLoading}
                  className="rounded-full border border-green-200 bg-white px-5 py-2.5 text-sm font-black text-[#2F6B3B] transition hover:bg-green-50 disabled:opacity-60"
                >
                  {farmerLoading ? "Refreshing..." : "Refresh"}
                </button>

                <button
                  onClick={() => setFarmerToolsOpen(false)}
                  className="rounded-full bg-[#1E2A1F] px-5 py-2.5 text-sm font-black text-white transition hover:bg-[#2F6B3B]"
                >
                  Minimize
                </button>
              </div>
            </div>

            <div className="mt-6 grid grid-cols-2 gap-4 md:grid-cols-4">
              <FarmerStat label="My Listings" value={farmerProducts.length} />
              <FarmerStat label="Health Logs" value={healthLogs.length} />
              <FarmerStat label="Buyer Orders" value={farmerOrders.length} />
              <FarmerStat
                label="Pending Orders"
                value={farmerPendingOrders}
              />
            </div>
          </div>

          <div className="flex flex-wrap gap-2 border-b border-green-100 p-4">
            {[
              { id: "sell", label: "Sell Product" },
              { id: "listings", label: "Manage Listings" },
              { id: "health", label: "Health Logs / Monitoring" },
              { id: "orders", label: "Farmer Orders" },
            ].map((tab) => (
              <button
                key={tab.id}
                onClick={() => setFarmerTab(tab.id as FarmerToolTab)}
                className={`rounded-full px-5 py-2.5 text-sm font-black transition ${
                  farmerTab === tab.id
                    ? "bg-[#2F6B3B] text-white shadow-lg shadow-green-900/20"
                    : "bg-[#F7FBF6] text-[#5C6B5D] hover:bg-green-100 hover:text-[#2F6B3B]"
                }`}
              >
                {tab.label}
              </button>
            ))}
          </div>

          <div className="p-6">
            {farmerTab === "sell" && renderFarmerSellForm()}
            {farmerTab === "listings" && renderFarmerListings()}
            {farmerTab === "health" && renderFarmerHealth()}
            {farmerTab === "orders" && renderFarmerOrders()}
          </div>
        </section>
      </div>
    );
  };

  const renderFarmerSellForm = () => (
    <div className="grid gap-8 lg:grid-cols-[1.1fr_0.9fr]">
      <form
        onSubmit={handlePublishProduct}
        className="rounded-[28px] border border-green-100 bg-[#F7FBF6] p-6"
      >
        <h3 className="text-2xl font-black text-[#1E2A1F]">Sell Product</h3>
        <p className="mt-2 text-sm text-[#5C6B5D]">
          Publish a lettuce product. It will appear in the marketplace after
          saving.
        </p>

        <div className="mt-6 grid gap-4 md:grid-cols-2">
          <div className="md:col-span-2">
            <label className="mb-1 block text-xs font-black uppercase tracking-wider text-[#5C6B5D]">
              Product Name
            </label>
            <input
              value={sellForm.name}
              onChange={(e) =>
                setSellForm({ ...sellForm, name: e.target.value })
              }
              placeholder="Example: Fresh Romaine Lettuce"
              className="w-full rounded-2xl border border-green-100 bg-white px-5 py-3.5 text-sm font-bold outline-none focus:border-[#2F6B3B]"
            />
          </div>

          <div>
            <label className="mb-1 block text-xs font-black uppercase tracking-wider text-[#5C6B5D]">
              Category
            </label>
            <select
              value={sellForm.category}
              onChange={(e) =>
                setSellForm({ ...sellForm, category: e.target.value })
              }
              className="w-full rounded-2xl border border-green-100 bg-white px-5 py-3.5 text-sm font-bold outline-none focus:border-[#2F6B3B]"
            >
              <option>Fresh Lettuce</option>
              <option>Premium Lettuce</option>
              <option>Seeds</option>
              <option>Bundles</option>
              <option>Bulk Orders</option>
            </select>
          </div>

          <div>
            <label className="mb-1 block text-xs font-black uppercase tracking-wider text-[#5C6B5D]">
              Location
            </label>
            <input
              value={sellForm.location}
              onChange={(e) =>
                setSellForm({ ...sellForm, location: e.target.value })
              }
              placeholder="Example: Lamac, Consolacion"
              className="w-full rounded-2xl border border-green-100 bg-white px-5 py-3.5 text-sm font-bold outline-none focus:border-[#2F6B3B]"
            />
          </div>

          <div>
            <label className="mb-1 block text-xs font-black uppercase tracking-wider text-[#5C6B5D]">
              Price
            </label>
            <input
              type="number"
              min="1"
              value={sellForm.price}
              onChange={(e) =>
                setSellForm({ ...sellForm, price: e.target.value })
              }
              placeholder="₱"
              className="w-full rounded-2xl border border-green-100 bg-white px-5 py-3.5 text-sm font-bold outline-none focus:border-[#2F6B3B]"
            />
          </div>

          <div>
            <label className="mb-1 block text-xs font-black uppercase tracking-wider text-[#5C6B5D]">
              Stock
            </label>
            <input
              type="number"
              min="1"
              value={sellForm.stock}
              onChange={(e) =>
                setSellForm({ ...sellForm, stock: e.target.value })
              }
              placeholder="Quantity"
              className="w-full rounded-2xl border border-green-100 bg-white px-5 py-3.5 text-sm font-bold outline-none focus:border-[#2F6B3B]"
            />
          </div>

          <div className="md:col-span-2">
            <label className="mb-1 block text-xs font-black uppercase tracking-wider text-[#5C6B5D]">
              Image URL
            </label>
            <input
              value={sellForm.imageUrl}
              onChange={(e) =>
                setSellForm({ ...sellForm, imageUrl: e.target.value })
              }
              placeholder="Paste image URL or leave blank for default lettuce image"
              className="w-full rounded-2xl border border-green-100 bg-white px-5 py-3.5 text-sm font-bold outline-none focus:border-[#2F6B3B]"
            />
          </div>

          <div className="md:col-span-2">
            <label className="mb-1 block text-xs font-black uppercase tracking-wider text-[#5C6B5D]">
              Description
            </label>
            <textarea
              value={sellForm.description}
              onChange={(e) =>
                setSellForm({ ...sellForm, description: e.target.value })
              }
              placeholder="Describe freshness, harvest quality, or lettuce type..."
              rows={4}
              className="w-full resize-none rounded-2xl border border-green-100 bg-white px-5 py-3.5 text-sm font-bold outline-none focus:border-[#2F6B3B]"
            />
          </div>
        </div>

        <button
          type="submit"
          disabled={savingProduct}
          className="mt-6 w-full rounded-full bg-[#2F6B3B] px-8 py-4 text-sm font-black text-white shadow-lg shadow-green-900/20 transition hover:-translate-y-1 hover:bg-[#1E2A1F] disabled:opacity-60"
        >
          {savingProduct ? "Publishing..." : "Publish Product"}
        </button>
      </form>

      <div className="rounded-[28px] border border-green-100 bg-white p-6">
        <h3 className="text-2xl font-black text-[#1E2A1F]">
          Product Preview
        </h3>

        <div className="mt-6 overflow-hidden rounded-[28px] border border-green-100 bg-white shadow-sm">
          <div
            className="h-56 bg-cover bg-center"
            style={{
              backgroundImage: `url(${
                sellForm.imageUrl.trim() || defaultProductImage
              })`,
            }}
          />

          <div className="p-5">
            <p className="text-xs font-black uppercase tracking-wider text-[#2F6B3B]">
              {sellForm.category || "Fresh Lettuce"}
            </p>

            <h4 className="mt-1 text-xl font-black text-[#1E2A1F]">
              {sellForm.name || "Product name"}
            </h4>

            <p className="mt-2 text-sm text-[#5C6B5D]">
              Farmer: {account?.name || "Farmer"}
            </p>

            <p className="mt-4 text-3xl font-black text-[#2F6B3B]">
              ₱{sellForm.price || "0"}
            </p>

            <p className="mt-2 text-sm font-bold text-[#5C6B5D]">
              Stock: {sellForm.stock || "0"}
            </p>

            <p className="mt-4 text-sm leading-6 text-[#5C6B5D]">
              {sellForm.description ||
                "Fresh lettuce crop from local farmer."}
            </p>
          </div>
        </div>
      </div>
    </div>
  );

  const renderFarmerListings = () => (
    <div>
      <div className="mb-5 flex flex-col gap-3 md:flex-row md:items-center md:justify-between">
        <div>
          <h3 className="text-2xl font-black text-[#1E2A1F]">
            Manage My Listings
          </h3>
          <p className="mt-1 text-sm text-[#5C6B5D]">
            Products owned by your farmer account.
          </p>
        </div>

        <button
          onClick={() => setFarmerTab("sell")}
          className="rounded-full bg-[#2F6B3B] px-5 py-2.5 text-sm font-black text-white"
        >
          Add Product
        </button>
      </div>

      <div className="overflow-hidden rounded-[24px] border border-green-100">
        <div className="overflow-x-auto">
          <table className="w-full min-w-[760px]">
            <thead className="bg-[#F7FBF6] text-xs uppercase tracking-[2px] text-[#5C6B5D]">
              <tr>
                <th className="px-6 py-4 text-left">Product</th>
                <th className="px-6 py-4 text-left">Category</th>
                <th className="px-6 py-4 text-left">Price</th>
                <th className="px-6 py-4 text-left">Stock</th>
                <th className="px-6 py-4 text-left">Status</th>
              </tr>
            </thead>

            <tbody className="divide-y divide-green-100 bg-white">
              {farmerProducts.length === 0 ? (
                <tr>
                  <td
                    colSpan={5}
                    className="px-6 py-14 text-center text-sm font-bold text-[#5C6B5D]"
                  >
                    No products listed yet.
                  </td>
                </tr>
              ) : (
                farmerProducts.map((product) => (
                  <tr key={product.id}>
                    <td className="px-6 py-4">
                      <div className="flex items-center gap-3">
                        <div
                          className="h-12 w-12 rounded-2xl bg-cover bg-center"
                          style={{
                            backgroundImage: `url(${
                              product.image_url ||
                              product.image ||
                              defaultProductImage
                            })`,
                          }}
                        />
                        <div>
                          <p className="font-black text-[#1E2A1F]">
                            {product.name || "Unnamed Product"}
                          </p>
                          <p className="text-xs text-[#5C6B5D]">
                            {formatDate(product.created_at)}
                          </p>
                        </div>
                      </div>
                    </td>
                    <td className="px-6 py-4 text-sm font-bold text-[#5C6B5D]">
                      {product.category || "N/A"}
                    </td>
                    <td className="px-6 py-4 text-sm font-black text-[#2F6B3B]">
                      ₱{formatMoney(product.price)}
                    </td>
                    <td className="px-6 py-4 text-sm font-bold text-[#1E2A1F]">
                      {product.stock || 0}
                    </td>
                    <td className="px-6 py-4">
                      <StatusPill text={product.status || "Available"} />
                    </td>
                  </tr>
                ))
              )}
            </tbody>
          </table>
        </div>
      </div>
    </div>
  );

  const renderFarmerHealth = () => (
    <div className="grid gap-6 lg:grid-cols-[0.9fr_1.1fr]">
      <div className="rounded-[28px] border border-green-100 bg-[#F7FBF6] p-6">
        <h3 className="text-2xl font-black text-[#1E2A1F]">
          Health Logs / Monitoring
        </h3>

        <p className="mt-2 text-sm leading-6 text-[#5C6B5D]">
          View scan logs from ESP32-CAM, disease result, confidence score,
          weather context, and monitoring history.
        </p>

        <div className="mt-6 grid gap-4">
          <div className="rounded-2xl bg-white p-5 shadow-sm">
            <p className="text-xs font-black uppercase tracking-[2px] text-[#5C6B5D]">
              Latest Result
            </p>
            <p className="mt-1 text-2xl font-black text-[#1E2A1F]">
              {latestHealthLog ? getDiseaseName(latestHealthLog) : "No scan yet"}
            </p>
          </div>

          <div className="rounded-2xl bg-white p-5 shadow-sm">
            <p className="text-xs font-black uppercase tracking-[2px] text-[#5C6B5D]">
              Confidence
            </p>
            <p className="mt-1 text-2xl font-black text-[#2F6B3B]">
              {latestHealthLog ? getConfidence(latestHealthLog) : "N/A"}
            </p>
          </div>

          <div className="rounded-2xl bg-white p-5 shadow-sm">
            <p className="text-xs font-black uppercase tracking-[2px] text-[#5C6B5D]">
              Temperature
            </p>
            <p className="mt-1 text-2xl font-black text-[#1E2A1F]">
              {latestHealthLog ? getTemperature(latestHealthLog) : "N/A"}
            </p>
          </div>
        </div>

        <button
          onClick={() => router.push("/health-logs")}
          className="mt-6 w-full rounded-full bg-[#2F6B3B] px-8 py-4 text-sm font-black text-white shadow-lg shadow-green-900/20 transition hover:-translate-y-1 hover:bg-[#1E2A1F]"
        >
          Open Full Health Logs Page
        </button>
      </div>

      <div className="rounded-[28px] border border-green-100 bg-white p-6">
        <h3 className="text-2xl font-black text-[#1E2A1F]">
          Recent Scan Records
        </h3>

        <div className="mt-5 grid gap-4">
          {healthLogs.length === 0 ? (
            <div className="flex min-h-[220px] items-center justify-center rounded-3xl border border-dashed border-green-200 bg-[#F7FBF6] text-sm font-bold text-[#5C6B5D]">
              No health logs yet.
            </div>
          ) : (
            healthLogs.slice(0, 4).map((log) => (
              <div
                key={log.id}
                className="rounded-[22px] border border-green-100 bg-[#F7FBF6] p-4"
              >
                <div className="flex flex-col gap-4 md:flex-row">
                  {log.image_url ? (
                    <img
                      src={log.image_url}
                      alt="Health log"
                      className="h-28 w-full rounded-2xl object-cover md:w-36"
                    />
                  ) : (
                    <div className="flex h-28 w-full items-center justify-center rounded-2xl bg-white text-xs font-bold text-[#5C6B5D] md:w-36">
                      No Image
                    </div>
                  )}

                  <div className="flex-1">
                    <p className="text-lg font-black text-[#1E2A1F]">
                      {getDiseaseName(log)}
                    </p>
                    <p className="mt-1 text-sm text-[#5C6B5D]">
                      Confidence:{" "}
                      <span className="font-black text-[#2F6B3B]">
                        {getConfidence(log)}
                      </span>
                    </p>
                    <p className="text-sm text-[#5C6B5D]">
                      Weather: {log.weather_condition || log.weather || "N/A"}
                    </p>
                    <p className="text-sm text-[#5C6B5D]">
                      Date: {formatDate(log.captured_at || log.created_at)}
                    </p>
                  </div>
                </div>
              </div>
            ))
          )}
        </div>
      </div>
    </div>
  );

  const renderFarmerOrders = () => (
    <div>
      <div className="mb-5">
        <h3 className="text-2xl font-black text-[#1E2A1F]">
          My Buyer Orders
        </h3>
        <p className="mt-1 text-sm text-[#5C6B5D]">
          Orders where your farmer account is assigned as seller.
        </p>
      </div>

      <div className="mb-5 grid gap-4 md:grid-cols-3">
        <FarmerSummaryCard
          label="Total Orders"
          value={String(farmerOrders.length)}
        />
        <FarmerSummaryCard
          label="Pending Orders"
          value={String(farmerPendingOrders)}
        />
        <FarmerSummaryCard
          label="Gross Sales"
          value={`₱${formatMoney(farmerRevenue)}`}
        />
      </div>

      <div className="grid gap-4">
        {farmerOrders.length === 0 ? (
          <div className="flex min-h-[220px] items-center justify-center rounded-3xl border border-dashed border-green-200 bg-[#F7FBF6] text-sm font-bold text-[#5C6B5D]">
            No buyer orders yet.
          </div>
        ) : (
          farmerOrders.map((order) => (
            <div
              key={order.id}
              className="rounded-[26px] border border-green-100 bg-[#F7FBF6] p-5"
            >
              <div className="flex flex-col gap-5 md:flex-row md:items-center md:justify-between">
                <div>
                  <p className="text-xs font-black uppercase tracking-[2px] text-[#5C6B5D]">
                    {order.order_code || order.id}
                  </p>

                  <h4 className="mt-1 text-xl font-black text-[#1E2A1F]">
                    {order.shipping_name || order.email || "Customer"}
                  </h4>

                  <p className="mt-1 text-sm text-[#5C6B5D]">
                    {formatDate(order.created_at)}
                  </p>

                  <p className="mt-1 text-sm text-[#5C6B5D]">
                    {order.shipping_address || "No address"}
                  </p>
                </div>

                <div className="text-left md:text-right">
                  <p className="text-3xl font-black text-[#2F6B3B]">
                    ₱{formatMoney(order.total_amount)}
                  </p>

                  <div className="mt-3 flex flex-wrap gap-2 md:justify-end">
                    <StatusPill text={order.status || "Pending"} />
                    <StatusPill text={order.payment_status || "Unpaid"} />
                    <StatusPill text={order.delivery_status || "Pending"} />
                  </div>

                  {(order.proof_image_url || order.delivery_proof_url) && (
                    <a
                      href={order.proof_image_url || order.delivery_proof_url || "#"}
                      target="_blank"
                      rel="noreferrer"
                      className="mt-4 inline-flex rounded-full bg-[#2F6B3B] px-5 py-2 text-sm font-black text-white"
                    >
                      View Proof
                    </a>
                  )}
                </div>
              </div>
            </div>
          ))
        )}
      </div>
    </div>
  );

  // ==========================================
  // MAIN RENDER FUNCTIONS
  // ==========================================

  const renderHome = () => (
    <div className="mx-auto grid min-h-[85vh] max-w-7xl items-center gap-16 px-4 py-16 sm:px-6 lg:grid-cols-2 lg:px-8">
      <div className="relative z-10 animate-in slide-in-from-left-8 duration-1000 fade-in">
        <div className="inline-flex items-center gap-2 rounded-full border border-green-200 bg-white/60 px-4 py-2 text-xs font-bold uppercase tracking-widest text-[#2F6B3B] backdrop-blur-sm shadow-sm">
          <span className="relative flex h-2 w-2">
            <span className="absolute inline-flex h-full w-full animate-ping rounded-full bg-green-400 opacity-75"></span>
            <span className="relative inline-flex h-2 w-2 rounded-full bg-[#2F6B3B]"></span>
          </span>
          Fresh. Verified. Delivered.
        </div>

        <h1 className="mt-8 text-5xl font-black leading-[1.1] tracking-tight md:text-6xl lg:text-[72px]">
          Premium lettuce, <br />
          <span className="bg-gradient-to-r from-[#2F6B3B] to-[#5DBB63] bg-clip-text text-transparent">
            trust verified.
          </span>
        </h1>

        <p className="mt-6 max-w-xl text-lg leading-relaxed text-[#5C6B5D]">
          Buy fresh lettuce, premium seeds, and bulk orders directly from
          verified local farmers. Experience a marketplace built for quality.
        </p>

        <div className="mt-10 flex flex-wrap items-center gap-5">
          <button
            onClick={() => setCurrentView("shop")}
            className="group flex items-center gap-2 rounded-full bg-[#2F6B3B] px-8 py-4 text-sm font-bold text-white shadow-[0_8px_20px_rgba(47,107,59,0.3)] transition-all duration-300 hover:-translate-y-1 hover:shadow-[0_12px_25px_rgba(47,107,59,0.4)] active:scale-95"
          >
            Enter Marketplace
            <svg
              className="h-4 w-4 transition-transform group-hover:translate-x-1"
              fill="none"
              viewBox="0 0 24 24"
              stroke="currentColor"
            >
              <path
                strokeLinecap="round"
                strokeLinejoin="round"
                strokeWidth={2.5}
                d="M14 5l7 7m0 0l-7 7m7-7H3"
              />
            </svg>
          </button>
        </div>
      </div>

      <div className="relative z-10 hidden lg:block animate-in slide-in-from-right-8 duration-1000 fade-in delay-150">
        <div className="group relative overflow-hidden rounded-[40px] border-[8px] border-white bg-white shadow-2xl shadow-green-900/10 transition-transform duration-700 hover:-translate-y-4">
          <div
            className="h-[650px] w-full bg-cover bg-center transition-transform duration-[2000ms] group-hover:scale-110"
            style={{
              backgroundImage:
                "url('https://images.unsplash.com/photo-1540420773420-3366772f4999?q=80&w=1600&auto=format&fit=crop')",
            }}
          />
          <div className="absolute inset-0 bg-gradient-to-t from-black/60 via-transparent to-transparent opacity-50 transition-opacity duration-700 group-hover:opacity-80"></div>

          <div className="absolute bottom-10 left-10 translate-y-4 rounded-3xl border border-white/20 bg-white/95 p-6 shadow-2xl backdrop-blur-xl transition-all duration-700 group-hover:translate-y-0">
            <div className="flex items-center gap-3">
              <div className="flex h-12 w-12 items-center justify-center rounded-full bg-green-100 shadow-inner">
                <svg
                  className="h-6 w-6 text-green-600"
                  fill="currentColor"
                  viewBox="0 0 20 20"
                >
                  <path
                    fillRule="evenodd"
                    d="M16.707 5.293a1 1 0 010 1.414l-8 8a1 1 0 01-1.414 0l-4-4a1 1 0 011.414-1.414L8 12.586l7.293-7.293a1 1 0 011.414 0z"
                    clipRule="evenodd"
                  />
                </svg>
              </div>
              <div>
                <p className="text-xs font-bold uppercase tracking-wider text-[#2F6B3B]">
                  AI Verified
                </p>
                <p className="text-lg font-black text-gray-900">
                  100% Healthy Crop
                </p>
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
  );

  const renderShop = () => (
    <div className="mx-auto max-w-7xl px-4 py-16 sm:px-6 lg:px-8">
      <div className="flex flex-col md:flex-row md:items-end md:justify-between animate-in slide-in-from-bottom-4 fade-in duration-500">
        <div>
          <p className="text-sm font-bold uppercase tracking-widest text-[#2F6B3B]">
            Marketplace
          </p>
          <h2 className="mt-2 text-4xl font-black tracking-tight md:text-5xl">
            Shop the harvest
          </h2>
        </div>
      </div>

      <div className="mt-10 flex flex-wrap gap-4 rounded-[28px] bg-white p-3 shadow-sm ring-1 ring-black/5 animate-in slide-in-from-bottom-6 fade-in duration-500 delay-75">
        <input
          className="min-w-[250px] flex-1 rounded-xl bg-[#F7FBF6] px-5 py-3.5 text-sm font-medium outline-none transition-all focus:bg-green-50 focus:ring-2 focus:ring-[#2F6B3B]/20"
          placeholder="Search fresh lettuce..."
          value={search}
          onChange={(e) => setSearch(e.target.value)}
        />

        <select
          className="cursor-pointer rounded-xl bg-[#F7FBF6] px-5 py-3.5 text-sm font-medium outline-none transition-colors hover:bg-green-50"
          value={category}
          onChange={(e) => setCategory(e.target.value)}
        >
          <option>All Categories</option>
          <option>Fresh Lettuce</option>
          <option>Premium Lettuce</option>
          <option>Seeds</option>
          <option>Bundles</option>
          <option>Bulk Orders</option>
        </select>

        <select
          className="cursor-pointer rounded-xl bg-[#F7FBF6] px-5 py-3.5 text-sm font-medium outline-none transition-colors hover:bg-green-50"
          value={sortBy}
          onChange={(e) => setSortBy(e.target.value)}
        >
          <option>Default</option>
          <option>Price: Low to High</option>
          <option>Price: High to Low</option>
          <option>Newest</option>
        </select>
      </div>

      <div className="mt-12 grid gap-8 md:grid-cols-2 xl:grid-cols-3">
        {filteredProducts.map((product, i) => (
          <div
            key={product.id}
            className="group flex flex-col rounded-[32px] bg-white p-3 shadow-sm ring-1 ring-black/5 transition-all duration-500 hover:-translate-y-3 hover:shadow-2xl hover:shadow-green-900/10 animate-in slide-in-from-bottom-8 fade-in fill-mode-both"
            style={{ animationDelay: `${i * 50}ms` }}
          >
            <div className="relative h-64 w-full overflow-hidden rounded-[24px]">
              <div
                className="absolute inset-0 bg-cover bg-center transition-transform duration-700 group-hover:scale-110"
                style={{ backgroundImage: `url(${product.image})` }}
              />
              <div className="absolute inset-0 bg-black/0 transition-colors duration-500 group-hover:bg-black/10"></div>

              <div className="absolute left-4 top-4 flex w-[calc(100%-2rem)] items-center justify-between">
                <span className="rounded-full bg-white/90 px-3 py-1.5 text-xs font-bold text-[#2F6B3B] shadow-sm backdrop-blur-md">
                  {product.badge}
                </span>
                <span className="rounded-full bg-black/50 px-3 py-1.5 text-xs font-bold text-white backdrop-blur-md">
                  Stock: {product.stock}
                </span>
              </div>
            </div>

            <div className="flex flex-1 flex-col p-5">
              <p className="text-sm font-bold text-[#5C6B5D]">
                {product.farmer}
              </p>

              <h3 className="mt-1 text-xl font-black text-gray-900">
                {product.name}
              </h3>

              <p className="mt-1 text-xs font-medium text-gray-500 uppercase tracking-wider">
                {product.category}
              </p>

              <div className="mt-auto flex items-center justify-between pt-6">
                <p className="text-3xl font-black text-[#2F6B3B]">
                  ₱{product.price}
                </p>

                <div className="flex gap-2">
                  <button
                    onClick={() => setSelectedProduct(product)}
                    className="flex h-12 w-12 items-center justify-center rounded-full bg-green-50 text-[#2F6B3B] hover:bg-green-100 transition-colors"
                  >
                    👁
                  </button>

                  <button
                    onClick={() => addToCart(product)}
                    disabled={product.stock === 0}
                    className="flex h-12 w-12 items-center justify-center rounded-full bg-[#2F6B3B] text-white shadow-[0_8px_16px_rgba(47,107,59,0.3)] transition-all duration-300 hover:scale-110 active:scale-95 disabled:opacity-50 disabled:hover:scale-100"
                  >
                    <svg
                      className="h-5 w-5"
                      fill="none"
                      viewBox="0 0 24 24"
                      stroke="currentColor"
                    >
                      <path
                        strokeLinecap="round"
                        strokeLinejoin="round"
                        strokeWidth={2.5}
                        d="M12 4v16m8-8H4"
                      />
                    </svg>
                  </button>
                </div>
              </div>
            </div>
          </div>
        ))}
      </div>
    </div>
  );

  const renderCheckout = () => (
    <div className="mx-auto max-w-7xl px-4 py-16 sm:px-6 lg:px-8">
      <div className="grid gap-12 lg:grid-cols-[1.5fr_1fr]">
        <div className="space-y-8 animate-in slide-in-from-left-8 fade-in duration-700">
          <div className="rounded-[32px] bg-white p-8 shadow-sm ring-1 ring-black/5">
            <div className="mb-6 flex items-center justify-between">
              <h2 className="text-2xl font-black tracking-tight text-gray-900">
                Your Cart
              </h2>
              <span className="rounded-full bg-green-50 px-3 py-1 text-xs font-bold text-[#2F6B3B]">
                {cartCount} Items
              </span>
            </div>

            {cart.length === 0 ? (
              <div className="flex flex-col items-center justify-center rounded-[24px] border-2 border-dashed border-gray-100 bg-gray-50 py-12 text-center">
                <p className="text-gray-500 font-medium">
                  Your cart is completely empty.
                </p>
                <button
                  onClick={() => setCurrentView("shop")}
                  className="mt-4 rounded-full bg-white px-6 py-2 text-sm font-bold text-[#2F6B3B] shadow-sm ring-1 ring-gray-200 hover:bg-gray-50"
                >
                  Browse Store
                </button>
              </div>
            ) : (
              <div className="space-y-4">
                {cart.map((item, i) => (
                  <div
                    key={item.id}
                    className="group flex items-center gap-4 rounded-[20px] border border-gray-100 bg-white p-4 transition-all hover:shadow-md animate-in slide-in-from-bottom-4 fade-in fill-mode-both"
                    style={{ animationDelay: `${i * 100}ms` }}
                  >
                    <div className="h-20 w-20 shrink-0 overflow-hidden rounded-[14px]">
                      <div
                        className="h-full w-full bg-cover bg-center transition-transform duration-500 group-hover:scale-110"
                        style={{ backgroundImage: `url(${item.image})` }}
                      />
                    </div>

                    <div className="flex flex-1 flex-col">
                      <h3 className="text-base font-bold text-gray-900">
                        {item.name}
                      </h3>
                      <p className="text-xs font-medium text-gray-500">
                        {item.farmer}
                      </p>
                      <p className="mt-1 text-lg font-black text-[#2F6B3B]">
                        ₱{item.price}
                      </p>
                    </div>

                    <div className="flex flex-col items-center gap-2 rounded-xl bg-gray-50 p-1 sm:flex-row sm:gap-4 sm:px-2 sm:py-1">
                      <button
                        onClick={() => updateQuantity(item.id, -1)}
                        className="flex h-7 w-7 items-center justify-center rounded-lg bg-white font-bold text-gray-600 shadow-sm ring-1 ring-black/5 hover:bg-gray-100 hover:text-gray-900 active:scale-95 transition-all"
                      >
                        -
                      </button>
                      <span className="w-4 text-center text-sm font-bold text-gray-900">
                        {item.quantity}
                      </span>
                      <button
                        onClick={() => updateQuantity(item.id, 1)}
                        className="flex h-7 w-7 items-center justify-center rounded-lg bg-white font-bold text-gray-600 shadow-sm ring-1 ring-black/5 hover:bg-gray-100 hover:text-gray-900 active:scale-95 transition-all"
                      >
                        +
                      </button>
                    </div>
                  </div>
                ))}
              </div>
            )}
          </div>

          <div
            className={`rounded-[32px] bg-white p-8 shadow-sm ring-1 ring-black/5 transition-opacity ${
              cart.length === 0 ? "opacity-50 pointer-events-none" : "opacity-100"
            }`}
          >
            <h3 className="text-lg font-black tracking-tight text-gray-900 mb-5">
              1. Delivery Method
            </h3>

            <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
              {[
                {
                  id: "Delivery",
                  desc: "Ships in 1-2 days (₱50)",
                },
                {
                  id: "Pickup",
                  desc: "Pick up from farm (Free)",
                },
              ].map((method) => (
                <button
                  key={method.id}
                  onClick={() =>
                    setCheckoutForm({
                      ...checkoutForm,
                      deliveryMethod: method.id,
                    })
                  }
                  className={`relative flex items-start gap-4 rounded-[20px] p-5 text-left border-2 transition-all duration-200 ${
                    checkoutForm.deliveryMethod === method.id
                      ? "border-[#2F6B3B] bg-[#F7FBF6] shadow-[0_4px_12px_rgba(47,107,59,0.1)]"
                      : "border-gray-100 bg-white hover:border-gray-300"
                  }`}
                >
                  <div>
                    <p
                      className={`font-bold ${
                        checkoutForm.deliveryMethod === method.id
                          ? "text-[#2F6B3B]"
                          : "text-gray-900"
                      }`}
                    >
                      {method.id}
                    </p>
                    <p className="text-xs font-medium text-gray-500 mt-1">
                      {method.desc}
                    </p>
                  </div>
                </button>
              ))}
            </div>
          </div>

          <div
            className={`rounded-[32px] bg-white p-8 shadow-sm ring-1 ring-black/5 transition-opacity ${
              cart.length === 0 ? "opacity-50 pointer-events-none" : "opacity-100"
            }`}
          >
            <h3 className="text-lg font-black tracking-tight text-gray-900 mb-5">
              2. Contact Details
            </h3>

            <div className="grid gap-4 md:grid-cols-2 mb-8">
              <div>
                <label className="mb-1.5 block text-[11px] font-bold uppercase tracking-wider text-gray-500">
                  Full Name
                </label>
                <input
                  className="w-full rounded-xl border border-gray-200 bg-gray-50 px-4 py-3.5 text-sm font-bold text-gray-900 outline-none transition-all focus:border-[#2F6B3B] focus:bg-white focus:ring-4 focus:ring-[#2F6B3B]/10"
                  placeholder="John Doe"
                  value={checkoutForm.fullName}
                  onChange={(e) =>
                    setCheckoutForm({
                      ...checkoutForm,
                      fullName: e.target.value,
                    })
                  }
                />
              </div>

              <div>
                <label className="mb-1.5 block text-[11px] font-bold uppercase tracking-wider text-gray-500">
                  Phone Number
                </label>
                <input
                  className="w-full rounded-xl border border-gray-200 bg-gray-50 px-4 py-3.5 text-sm font-bold text-gray-900 outline-none transition-all focus:border-[#2F6B3B] focus:bg-white focus:ring-4 focus:ring-[#2F6B3B]/10"
                  placeholder="09XX XXX XXXX"
                  value={checkoutForm.phone}
                  onChange={(e) =>
                    setCheckoutForm({
                      ...checkoutForm,
                      phone: e.target.value,
                    })
                  }
                />
              </div>
            </div>

            {checkoutForm.deliveryMethod === "Delivery" && (
              <div>
                <h3 className="text-lg font-black tracking-tight text-gray-900 mb-5 border-t border-gray-100 pt-8">
                  3. Shipping Address
                </h3>

                <div className="grid gap-4 md:grid-cols-2">
                  <div className="md:col-span-2">
                    <label className="mb-1.5 block text-[11px] font-bold uppercase tracking-wider text-gray-500">
                      Street Address
                    </label>
                    <input
                      className="w-full rounded-xl border border-gray-200 bg-gray-50 px-4 py-3.5 text-sm font-bold text-gray-900 outline-none transition-all focus:border-[#2F6B3B] focus:bg-white focus:ring-4 focus:ring-[#2F6B3B]/10"
                      placeholder="House No., Street Name, Barangay"
                      value={checkoutForm.address}
                      onChange={(e) =>
                        setCheckoutForm({
                          ...checkoutForm,
                          address: e.target.value,
                        })
                      }
                    />
                  </div>

                  <div>
                    <label className="mb-1.5 block text-[11px] font-bold uppercase tracking-wider text-gray-500">
                      City / Municipality
                    </label>
                    <input
                      className="w-full rounded-xl border border-gray-200 bg-gray-50 px-4 py-3.5 text-sm font-bold text-gray-900 outline-none transition-all focus:border-[#2F6B3B] focus:bg-white focus:ring-4 focus:ring-[#2F6B3B]/10"
                      placeholder="e.g. Cebu City"
                      value={checkoutForm.city}
                      onChange={(e) =>
                        setCheckoutForm({
                          ...checkoutForm,
                          city: e.target.value,
                        })
                      }
                    />
                  </div>

                  <div>
                    <label className="mb-1.5 block text-[11px] font-bold uppercase tracking-wider text-gray-500">
                      Postal Code
                    </label>
                    <input
                      className="w-full rounded-xl border border-gray-200 bg-gray-50 px-4 py-3.5 text-sm font-bold text-gray-900 outline-none transition-all focus:border-[#2F6B3B] focus:bg-white focus:ring-4 focus:ring-[#2F6B3B]/10"
                      placeholder="e.g. 6000"
                      value={checkoutForm.postalCode}
                      onChange={(e) =>
                        setCheckoutForm({
                          ...checkoutForm,
                          postalCode: e.target.value,
                        })
                      }
                    />
                  </div>
                </div>
              </div>
            )}
          </div>

          <div
            className={`rounded-[32px] bg-white p-8 shadow-sm ring-1 ring-black/5 transition-opacity ${
              cart.length === 0 ? "opacity-50 pointer-events-none" : "opacity-100"
            }`}
          >
            <h3 className="text-lg font-black tracking-tight text-gray-900 mb-5">
              {checkoutForm.deliveryMethod === "Delivery"
                ? "4. Payment Method"
                : "3. Payment Method"}
            </h3>

            <div className="grid grid-cols-1 sm:grid-cols-3 gap-4">
              {["Cash on Delivery", "GCash", "Card"].map((method) => (
                <button
                  key={method}
                  onClick={() =>
                    setCheckoutForm({
                      ...checkoutForm,
                      paymentMethod: method,
                    })
                  }
                  className={`rounded-[20px] p-5 border-2 transition-all duration-200 ${
                    checkoutForm.paymentMethod === method
                      ? "border-[#2F6B3B] bg-[#F7FBF6] shadow-[0_4px_12px_rgba(47,107,59,0.1)]"
                      : "border-gray-100 bg-white hover:border-gray-300"
                  }`}
                >
                  <p
                    className={`text-sm font-bold text-center ${
                      checkoutForm.paymentMethod === method
                        ? "text-[#2F6B3B]"
                        : "text-gray-600"
                    }`}
                  >
                    {method}
                  </p>
                </button>
              ))}
            </div>
          </div>
        </div>

        <div className="sticky top-28 h-fit rounded-[40px] bg-[#1E2A1F] p-8 text-white shadow-2xl animate-in slide-in-from-right-8 fade-in duration-700 border border-gray-800">
          <h3 className="text-2xl font-black text-white">Order Summary</h3>

          <div className="mt-8 space-y-5 text-sm font-medium text-gray-400">
            <div className="flex justify-between items-center">
              <p>Items ({cartCount})</p>
              <p className="font-bold text-white">₱{subtotal}</p>
            </div>

            <div className="flex justify-between items-center">
              <p>
                {checkoutForm.deliveryMethod === "Delivery"
                  ? "Delivery Fee"
                  : "Farm Pickup"}
              </p>
              <p className="font-bold text-white">₱{shipping}</p>
            </div>

            <div className="my-6 h-px w-full bg-white/10"></div>

            <div className="flex items-end justify-between">
              <p className="text-lg text-white font-bold">Total</p>
              <p className="text-4xl font-black text-[#5DBB63]">₱{total}</p>
            </div>
          </div>

          <button
            onClick={handleCheckout}
            disabled={loadingOrder || cart.length === 0}
            className="mt-6 w-full rounded-full bg-[#5DBB63] py-4 text-lg font-black text-[#1E2A1F] shadow-[0_8px_20px_rgba(93,187,99,0.2)] transition-all hover:-translate-y-1 hover:shadow-[0_12px_25px_rgba(93,187,99,0.3)] active:scale-95 disabled:opacity-50 disabled:hover:translate-y-0 disabled:cursor-not-allowed"
          >
            {loadingOrder ? "Processing..." : "Place Order"}
          </button>
        </div>
      </div>
    </div>
  );

  const renderOrders = () => (
    <div className="mx-auto max-w-7xl px-4 py-16 sm:px-6 lg:px-8">
      <div className="mb-12 text-center animate-in slide-in-from-top-4 fade-in duration-500">
        <h2 className="text-4xl font-black tracking-tight">
          Track your freshness
        </h2>
        <p className="mt-4 text-[#5C6B5D]">
          Real-time updates from the farm to your door.
        </p>
      </div>

      <div className="mx-auto max-w-4xl space-y-4">
        {orders.length === 0 ? (
          <div className="rounded-[32px] bg-white p-10 text-center shadow-sm border border-gray-100">
            <p className="text-lg font-bold text-gray-800">
              You have no active orders yet.
            </p>
            <button
              onClick={() => setCurrentView("shop")}
              className="mt-4 rounded-full bg-[#2F6B3B] px-6 py-2 text-white font-bold hover:bg-[#1e4a27] transition-colors"
            >
              Start Shopping
            </button>
          </div>
        ) : (
          orders.map((order, i) => (
            <div
              key={order.id}
              className="group flex items-center justify-between rounded-[24px] bg-white p-6 shadow-sm ring-1 ring-black/5 transition-all duration-300 hover:-translate-y-1 hover:shadow-xl animate-in slide-in-from-bottom-4 fade-in fill-mode-both"
              style={{ animationDelay: `${i * 100}ms` }}
            >
              <div>
                <p className="text-xs font-bold tracking-widest text-gray-400 uppercase">
                  {order.id.slice(0, 8)} •{" "}
                  {new Date(order.date || Date.now()).toLocaleDateString()}
                </p>
                <h3 className="text-lg font-black mt-1 text-gray-900">
                  ₱{order.total_amount} •{" "}
                  {order.items?.[0]?.productName || "Lettuce Order"}
                </h3>
                <p className="text-xs font-medium text-gray-500 mt-1">
                  {order.deliveryMethod} • {order.paymentMethod}
                </p>
              </div>

              <span
                className={`rounded-full px-4 py-2 text-sm font-bold ${
                  statusColors[order.status] || "bg-gray-100 text-gray-700"
                }`}
              >
                {order.status}
              </span>
            </div>
          ))
        )}
      </div>
    </div>
  );

  const renderAbout = () => (
    <div className="mx-auto max-w-7xl px-4 py-16 sm:px-6 lg:px-8">
      <div className="grid gap-6 md:grid-cols-3">
        <div className="rounded-[30px] border border-green-100 bg-white p-8 shadow-sm transition-transform hover:-translate-y-2 hover:shadow-xl animate-in slide-in-from-bottom-8 fade-in duration-500 delay-75">
          <h3 className="text-xl font-bold text-gray-900">Verified Farmers</h3>
          <p className="mt-3 leading-7 text-[#5C6B5D]">
            Buyers browse products from trusted, AI-verified lettuce growers
            only. Quality is guaranteed.
          </p>
        </div>

        <div className="rounded-[30px] border border-green-100 bg-white p-8 shadow-sm transition-transform hover:-translate-y-2 hover:shadow-xl animate-in slide-in-from-bottom-8 fade-in duration-500 delay-150">
          <h3 className="text-xl font-bold text-gray-900">Freshness First</h3>
          <p className="mt-3 leading-7 text-[#5C6B5D]">
            Listings focus on source clarity, IoT-monitored freshness, and total
            buyer confidence.
          </p>
        </div>

        <div className="rounded-[30px] border border-green-100 bg-white p-8 shadow-sm transition-transform hover:-translate-y-2 hover:shadow-xl animate-in slide-in-from-bottom-8 fade-in duration-500 delay-200">
          <h3 className="text-xl font-bold text-gray-900">Premium Tech</h3>
          <p className="mt-3 leading-7 text-[#5C6B5D]">
            Built with Next.js, Tailwind, and Supabase to provide a seamless,
            presentation-ready shopping flow.
          </p>
        </div>
      </div>
    </div>
  );

  return (
    <main className="min-h-screen bg-[#F7FBF6] text-[#1E2A1F] selection:bg-[#2F6B3B] selection:text-white">
      <header className="fixed top-0 z-50 w-full border-b border-white/20 bg-[#F7FBF6]/80 backdrop-blur-xl transition-all duration-300">
        <div className="mx-auto flex max-w-7xl items-center justify-between px-4 py-3 sm:px-6 lg:px-8">
          <button
            onClick={() => setCurrentView("home")}
            className="group flex items-center gap-3"
          >
            <img
              src="/Logo.png"
              alt="GreenGuard AI Logo"
              className="h-12 w-auto transition-transform duration-300 group-hover:scale-105"
            />

            <div className="text-left border-l border-black/10 pl-3">
              <p className="text-xl font-extrabold tracking-tight text-[#2F6B3B]">
                GreenGuard AI
              </p>
              <p className="text-[11px] font-bold uppercase tracking-widest text-[#5C6B5D]">
                Marketplace
              </p>
            </div>
          </button>

          <nav className="hidden items-center gap-8 md:flex">
            {["Home", "Shop", "Checkout", "Orders", "About"].map((item) => {
              const viewName = item.toLowerCase() as any;

              return (
                <button
                  key={item}
                  onClick={() => setCurrentView(viewName)}
                  className={`group relative text-sm font-bold transition-colors hover:text-[#2F6B3B] ${
                    currentView === viewName
                      ? "text-[#2F6B3B]"
                      : "text-[#5C6B5D]"
                  }`}
                >
                  {item}
                  <span
                    className={`absolute -bottom-1.5 left-0 h-[3px] rounded-full bg-[#2F6B3B] transition-all duration-300 ${
                      currentView === viewName
                        ? "w-full"
                        : "w-0 group-hover:w-full"
                    }`}
                  ></span>
                </button>
              );
            })}
          </nav>

          <div className="flex items-center gap-3">
            {isFarmer && (
              <button
                onClick={() => setFarmerToolsOpen((prev) => !prev)}
                className="hidden rounded-full bg-[#2F6B3B] px-5 py-2.5 text-sm font-black text-white shadow-sm transition hover:bg-[#1E2A1F] md:block"
              >
                Farmer Tools
              </button>
            )}

            {account ? (
              <div className="hidden items-center gap-2 sm:flex">
                <div className="flex items-center gap-2 rounded-full border border-green-200 bg-white/60 py-1.5 pl-1.5 pr-4 shadow-sm backdrop-blur-md">
                  <div className="flex h-7 w-7 items-center justify-center rounded-full bg-gradient-to-br from-[#2F6B3B] to-[#5DBB63] text-xs font-bold text-white shadow-inner">
                    {account.name.charAt(0).toUpperCase()}
                  </div>
                  <span className="text-sm font-bold text-[#1E2A1F]">
                    {account.name.split(" ")[0]}
                  </span>
                </div>

                <button
                  onClick={handleLogout}
                  title="Logout"
                  className="group flex h-10 w-10 items-center justify-center rounded-full bg-white border border-gray-200 shadow-sm transition-all hover:bg-red-50 hover:border-red-200 active:scale-95"
                >
                  <svg
                    className="h-4 w-4 text-gray-400 transition-colors group-hover:text-red-500"
                    fill="none"
                    viewBox="0 0 24 24"
                    stroke="currentColor"
                  >
                    <path
                      strokeLinecap="round"
                      strokeLinejoin="round"
                      strokeWidth={2.5}
                      d="M17 16l4-4m0 0l-4-4m4 4H7m6 4v1a3 3 0 01-3 3H6a3 3 0 01-3-3V7a3 3 0 013-3h4a3 3 0 013 3v1"
                    />
                  </svg>
                </button>
              </div>
            ) : (
              <button
                onClick={() => {
                  setAuthMode("login");
                  setAuthOpen(true);
                }}
                className="hidden rounded-full px-5 py-2.5 text-sm font-bold text-[#5C6B5D] transition-all hover:bg-green-50 hover:text-[#2F6B3B] sm:block"
              >
                Sign In
              </button>
            )}

            <button
              onClick={() => setCurrentView("checkout")}
              className="group relative flex items-center gap-2 overflow-hidden rounded-full bg-[#1E2A1F] px-5 py-2.5 text-sm font-bold text-white shadow-[0_8px_20px_rgba(30,42,31,0.2)] transition-all duration-300 hover:-translate-y-0.5 hover:shadow-[0_12px_24px_rgba(30,42,31,0.3)] active:scale-95"
            >
              <span>Cart</span>

              {cartCount > 0 && (
                <span className="flex h-5 w-5 items-center justify-center rounded-full bg-[#5DBB63] text-xs font-black text-[#1E2A1F] transition-transform group-hover:scale-110">
                  {cartCount}
                </span>
              )}
            </button>
          </div>
        </div>
      </header>

      {message && (
        <div className="fixed bottom-8 left-1/2 z-[100] flex -translate-x-1/2 items-center gap-3 rounded-full border border-gray-100 bg-white py-3 pl-3 pr-6 shadow-[0_20px_40px_-10px_rgba(0,0,0,0.15)] animate-in slide-in-from-bottom-8 fade-in zoom-in-95 duration-300">
          <div className="flex h-8 w-8 items-center justify-center rounded-full bg-green-100 text-green-600">
            ✓
          </div>
          <p className="text-sm font-bold text-gray-800">{message}</p>
        </div>
      )}

      {authOpen && (
        <div className="fixed inset-0 z-[70] flex items-center justify-center bg-black/30 p-4 backdrop-blur-md animate-in fade-in duration-200">
          <div className="relative w-full max-w-md overflow-hidden rounded-[36px] bg-white shadow-[0_0_50px_-12px_rgba(47,107,59,0.4)] animate-in zoom-in-95 slide-in-from-bottom-4 duration-300">
            <div className="relative p-8">
              <div className="mb-8 flex items-center justify-between">
                <div>
                  <h3 className="text-3xl font-black tracking-tight text-gray-900">
                    {authMode === "login"
                      ? "Welcome back"
                      : authMode === "register"
                      ? "Create Account"
                      : "Reset Password"}
                  </h3>
                </div>

                <button
                  onClick={() => setAuthOpen(false)}
                  className="flex h-8 w-8 items-center justify-center rounded-full bg-gray-100 text-gray-500 hover:bg-gray-200 hover:text-gray-900 active:scale-95"
                >
                  ✕
                </button>
              </div>

              <form onSubmit={handleAuthSubmit} className="space-y-4">
                {authMode === "register" && (
                  <input
                    required
                    className="w-full rounded-2xl border border-gray-200 bg-gray-50/50 px-5 py-4 text-sm font-medium outline-none transition-all focus:border-[#2F6B3B] focus:bg-white focus:ring-4 focus:ring-[#2F6B3B]/10"
                    placeholder="Full Name"
                    value={authForm.name}
                    onChange={(e) =>
                      setAuthForm({
                        ...authForm,
                        name: e.target.value,
                      })
                    }
                  />
                )}

                <input
                  required
                  type="email"
                  className="w-full rounded-2xl border border-gray-200 bg-gray-50/50 px-5 py-4 text-sm font-medium outline-none transition-all focus:border-[#2F6B3B] focus:bg-white focus:ring-4 focus:ring-[#2F6B3B]/10"
                  placeholder="Email Address"
                  value={authForm.email}
                  onChange={(e) =>
                    setAuthForm({
                      ...authForm,
                      email: e.target.value,
                    })
                  }
                />

                {authMode !== "reset" && (
                  <div>
                    <input
                      required
                      type="password"
                      className="w-full rounded-2xl border border-gray-200 bg-gray-50/50 px-5 py-4 text-sm font-medium outline-none transition-all focus:border-[#2F6B3B] focus:bg-white focus:ring-4 focus:ring-[#2F6B3B]/10"
                      placeholder="Password (min. 6 chars)"
                      value={authForm.password}
                      onChange={(e) =>
                        setAuthForm({
                          ...authForm,
                          password: e.target.value,
                        })
                      }
                    />

                    {authMode === "login" && (
                      <button
                        type="button"
                        onClick={() => setAuthMode("reset")}
                        className="mt-2 text-xs font-bold text-gray-500 hover:text-[#2F6B3B]"
                      >
                        Forgot your password?
                      </button>
                    )}
                  </div>
                )}

                <div className="pt-4">
                  <button
                    type="submit"
                    disabled={authLoading}
                    className="relative w-full overflow-hidden rounded-full bg-[#2F6B3B] py-4 text-sm font-bold text-white shadow-[0_8px_20px_rgba(47,107,59,0.3)] transition-all hover:-translate-y-0.5 hover:shadow-[0_12px_25px_rgba(47,107,59,0.4)] active:scale-[0.98] disabled:opacity-70"
                  >
                    {authLoading
                      ? "Processing..."
                      : authMode === "login"
                      ? "Sign In Securely"
                      : authMode === "register"
                      ? "Create Buyer Account"
                      : "Send Reset Link"}
                  </button>

                  <button
                    type="button"
                    onClick={() =>
                      setAuthMode(authMode === "login" ? "register" : "login")
                    }
                    className="mt-4 w-full py-2 text-sm font-bold text-gray-500 transition-colors hover:text-[#2F6B3B]"
                  >
                    {authMode === "login"
                      ? "Don't have an account? Sign up"
                      : authMode === "register"
                      ? "Already have an account? Log in"
                      : "Back to Login"}
                  </button>
                </div>
              </form>
            </div>
          </div>
        </div>
      )}

      {selectedProduct && (
        <div className="fixed inset-0 z-[65] flex items-center justify-center bg-black/40 p-4 backdrop-blur-sm animate-in fade-in duration-200">
          <div className="w-full max-w-4xl rounded-[36px] bg-white p-6 shadow-2xl animate-in zoom-in-95 duration-300">
            <div className="mb-4 flex items-center justify-between">
              <h3 className="text-2xl font-black">{selectedProduct.name}</h3>
              <button
                onClick={() => setSelectedProduct(null)}
                className="rounded-full bg-gray-100 px-4 py-2 text-sm font-bold text-gray-500 hover:bg-gray-200 active:scale-95"
              >
                Close
              </button>
            </div>

            <div className="grid gap-8 md:grid-cols-2">
              <div
                className="h-[380px] rounded-[28px] bg-cover bg-center shadow-inner"
                style={{ backgroundImage: `url(${selectedProduct.image})` }}
              />

              <div>
                <p className="rounded-full bg-[#E8F3EA] px-3 py-1 text-xs font-bold text-[#2F6B3B] inline-block">
                  {selectedProduct.badge}
                </p>

                <p className="mt-4 text-sm font-medium text-[#5C6B5D]">
                  Farmer:{" "}
                  <span className="font-bold text-gray-900">
                    {selectedProduct.farmer}
                  </span>
                </p>

                <p className="mt-2 text-sm font-medium text-[#5C6B5D]">
                  Category:{" "}
                  <span className="font-bold text-gray-900">
                    {selectedProduct.category}
                  </span>
                </p>

                <p className="mt-2 text-sm font-medium text-[#5C6B5D]">
                  Stock:{" "}
                  <span className="font-bold text-gray-900">
                    {selectedProduct.stock}
                  </span>
                </p>

                <p className="mt-6 text-4xl font-black text-[#2F6B3B]">
                  ₱{selectedProduct.price}
                </p>

                <div className="mt-8 flex gap-3">
                  <button
                    onClick={() => {
                      addToCart(selectedProduct);
                      setSelectedProduct(null);
                    }}
                    className="rounded-full bg-[#2F6B3B] px-8 py-3.5 text-sm font-bold text-white shadow-[0_8px_20px_rgba(47,107,59,0.3)] transition-all hover:-translate-y-1 hover:shadow-[0_12px_25px_rgba(47,107,59,0.4)] active:scale-95"
                  >
                    Add to Cart
                  </button>

                  <button
                    onClick={() => {
                      addToCart(selectedProduct);
                      setSelectedProduct(null);
                      setCurrentView("checkout");
                    }}
                    className="rounded-full border-2 border-[#2F6B3B] px-8 py-3.5 text-sm font-bold text-[#2F6B3B] transition-all hover:bg-green-50 active:scale-95"
                  >
                    Buy Now
                  </button>
                </div>
              </div>
            </div>
          </div>
        </div>
      )}

      <div key={currentView} className="pt-24 pb-20 animate-in fade-in duration-300">
        {renderFarmerTools()}

        {currentView === "home" && renderHome()}
        {currentView === "shop" && renderShop()}
        {currentView === "checkout" && renderCheckout()}
        {currentView === "orders" && renderOrders()}
        {currentView === "about" && renderAbout()}
      </div>

      <footer className="border-t border-black/5 bg-white pb-8 pt-16">
        <div className="mx-auto grid max-w-7xl gap-10 px-4 sm:px-6 md:grid-cols-4 lg:px-8">
          <div className="col-span-1 md:col-span-2 lg:col-span-1">
            <h3 className="text-2xl font-black text-[#2F6B3B]">
              GreenGuard AI
            </h3>
            <p className="mt-4 text-sm leading-relaxed text-[#5C6B5D]">
              A premium marketplace connecting buyers directly with verified
              local farmers.
            </p>
          </div>
        </div>

        <div className="mx-auto mt-16 max-w-7xl px-4 text-center text-sm text-[#5C6B5D] sm:px-6 lg:px-8">
          © 2026 GreenGuard AI Capstone Project. All rights reserved.
        </div>
      </footer>
    </main>
  );
}

function FarmerStat({ label, value }: { label: string; value: number }) {
  return (
    <div className="rounded-2xl border border-green-100 bg-white p-4 shadow-sm">
      <p className="text-3xl font-black text-[#2F6B3B]">{value}</p>
      <p className="mt-1 text-xs font-black uppercase tracking-[2px] text-[#5C6B5D]">
        {label}
      </p>
    </div>
  );
}

function FarmerSummaryCard({ label, value }: { label: string; value: string }) {
  return (
    <div className="rounded-[24px] border border-green-100 bg-[#F7FBF6] p-5">
      <p className="text-2xl font-black text-[#2F6B3B]">{value}</p>
      <p className="mt-1 text-xs font-black uppercase tracking-[2px] text-[#5C6B5D]">
        {label}
      </p>
    </div>
  );
}

function StatusPill({ text }: { text: string }) {
  return (
    <span
      className={`rounded-full border px-3 py-1 text-[11px] font-black uppercase tracking-[1px] ${statusTone(
        text
      )}`}
    >
      {text}
    </span>
  );
}