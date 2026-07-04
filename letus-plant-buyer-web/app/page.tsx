"use client";

import { useEffect, useMemo, useState } from "react";
import { useRouter } from "next/navigation";
import { supabase } from "@/lib/supabase";

// ==================== TYPES ====================
type Product = {
  id: number;
  name: string;
  farmer: string;
  farmerId?: string | null;
  location?: string | null;
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
  location?: string | null;
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

function isUsefulLocation(value?: string | null) {
  const location = String(value || "").trim();
  const normalized = location.toLowerCase();
  if (!location) return false;
  return !["n/a", "unknown", "local farm", "farm pickup", "no location"].includes(normalized);
}

function formatWeatherTime(value?: string | null) {
  if (!value) return "Not updated yet";
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return value;
  return date.toLocaleString();
}

function statusTone(status?: string | null) {
  const value = String(status || "").toLowerCase();
  if (value.includes("completed") || value.includes("delivered") || value.includes("paid") || value.includes("received") || value.includes("available")) {
    return "border-green-200 bg-green-50 text-green-700";
  }
  if (value.includes("cancel") || value.includes("rejected")) {
    return "border-red-200 bg-red-50 text-red-700";
  }
  if (value.includes("pending") || value.includes("confirmed") || value.includes("preparing") || value.includes("shipped")) {
    return "border-amber-200 bg-amber-50 text-amber-700";
  }
  return "border-gray-200 bg-gray-50 text-gray-600";
}

export default function HomePage() {
  const router = useRouter();

  const [currentView, setCurrentView] = useState<"home" | "shop" | "checkout" | "orders" | "about">("home");
  const [products, setProducts] = useState<Product[]>([]);
  const [orders, setOrders] = useState<Order[]>([]);
  const [cart, setCart] = useState<CartItem[]>([]);
  const [selectedProduct, setSelectedProduct] = useState<Product | null>(null);
  const [search, setSearch] = useState("");
  const [category, setCategory] = useState("All Categories");
  const [sortBy, setSortBy] = useState("Default");
  const [authOpen, setAuthOpen] = useState(false);
  const [authMode, setAuthMode] = useState<"login" | "register" | "reset">("login");
  const [authLoading, setAuthLoading] = useState(false);
  const [account, setAccount] = useState<AccountUser | null>(null);
  const [checkoutForm, setCheckoutForm] = useState({
    fullName: "", email: "", phone: "", address: "", city: "", postalCode: "", paymentMethod: "Cash on Delivery", deliveryMethod: "Delivery",
  });
  const [authForm, setAuthForm] = useState({ name: "", email: "", password: "" });
  const [message, setMessage] = useState("");
  const [loadingOrder, setLoadingOrder] = useState(false);

  const [farmerToolsOpen, setFarmerToolsOpen] = useState(false);
  const [farmerTab, setFarmerTab] = useState<FarmerToolTab>("sell");
  const [farmerProducts, setFarmerProducts] = useState<FarmerProduct[]>([]);
  const [farmerOrders, setFarmerOrders] = useState<FarmerOrder[]>([]);
  const [healthLogs, setHealthLogs] = useState<HealthLog[]>([]);
  const [farmerLoading, setFarmerLoading] = useState(false);
  const [savingProduct, setSavingProduct] = useState(false);
  const [weather, setWeather] = useState<WeatherData | null>(null);
  const [weatherLoading, setWeatherLoading] = useState(false);
  const [weatherError, setWeatherError] = useState("");
  const [sellForm, setSellForm] = useState({
    name: "", category: "Fresh Lettuce", price: "", stock: "", description: "", imageUrl: "", location: "",
  });

  const isFarmer = account?.role === "farmer";

  // ==================== IMPROVED FARMER WEATHER LOCATION ====================
  const farmerWeatherLocation = useMemo(() => {
    // Priority 1: Health Logs
    const logLocation = healthLogs.find((log) => isUsefulLocation(log.location))?.location;

    // Priority 2: Farmer Products
    const productLocation = farmerProducts.find((product) => isUsefulLocation(product.location))?.location;

    // Final fallback
    const finalLocation = logLocation || productLocation || "Lapu-Lapu City, Cebu, PH";

    return finalLocation.trim();
  }, [healthLogs, farmerProducts]);

  // ==================== EFFECTS ====================
  useEffect(() => {
    loadProducts();
    const savedCart = localStorage.getItem("letusplant-cart");
    if (savedCart) setCart(JSON.parse(savedCart));

    async function checkSession() {
      const { data: { session } } = await supabase.auth.getSession();
      if (!session?.user) return;

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

      const role = String(profile?.role || session.user.user_metadata?.role || "buyer").toLowerCase();

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
        name: profile?.full_name || session.user.user_metadata?.full_name || (role === "farmer" ? "Farmer" : "Buyer"),
        email: profile?.email || session.user.email || "",
        role: role as UserRole,
      });

      if (role === "farmer") {
        setFarmerToolsOpen(true);
        setCart([]);
        localStorage.removeItem("letusplant-cart");
      }
    }
    checkSession();
  }, [router]);

  useEffect(() => {
    if (isFarmer) {
      localStorage.removeItem("letusplant-cart");
      return;
    }
    localStorage.setItem("letusplant-cart", JSON.stringify(cart));
  }, [cart, isFarmer]);

  useEffect(() => {
    if (account) {
      setCheckoutForm((prev) => ({
        ...prev,
        fullName: prev.fullName || account.name,
        email: prev.email || account.email,
      }));
      if (account.role === "buyer") {
        loadOrders();
      } else {
        setOrders([]);
        setCart([]);
        localStorage.removeItem("letusplant-cart");
        loadFarmerToolsData(account.id);
      }
    } else {
      setOrders([]);
      setFarmerProducts([]);
      setFarmerOrders([]);
      setHealthLogs([]);
    }
  }, [account]);

  useEffect(() => {
    if (isFarmer && (currentView === "checkout" || currentView === "orders")) {
      setCurrentView("shop");
    }
  }, [currentView, isFarmer]);

  // ==================== IMPROVED WEATHER LOADING ====================
  useEffect(() => {
    if (!isFarmer || !account?.id) {
      setWeather(null);
      setWeatherError("");
      return;
    }

    // Load immediately
    loadFarmerWeather(farmerWeatherLocation);

    // Auto refresh every 5 minutes
    const intervalId = window.setInterval(() => {
      loadFarmerWeather(farmerWeatherLocation, false);
    }, 5 * 60 * 1000);

    return () => window.clearInterval(intervalId);
  }, [account?.id, farmerWeatherLocation, isFarmer]);

  // ==================== FUNCTIONS ====================
  async function loadProducts() {
    try {
      const res = await fetch("/api?type=products");
      const json = await res.json();
      if (json.success) setProducts(json.data);
    } catch (e) {
      console.error("Failed to load products:", e);
    }
  }

  async function loadOrders() {
    if (!account?.id) return;
    try {
      const res = await fetch(`/api?type=orders&userId=${account.id}`);
      const json = await res.json();
      if (json.success) setOrders(json.data);
    } catch (e) {
      console.error("Failed to load orders:", e);
    }
  }

  async function loadFarmerWeather(location = farmerWeatherLocation, showError = true) {
    if (!isFarmer) return;
    setWeatherLoading(true);
    setWeatherError("");

    try {
      const response = await fetch(`/api/weather?location=${encodeURIComponent(location)}`, { 
        cache: "no-store" 
      });
      
      const result = await response.json();

      if (!response.ok || !result.success) {
        throw new Error(result.message || "Unable to load live weather.");
      }

      setWeather(result.data as WeatherData);
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : "Unable to load live weather.";
      setWeatherError(errorMessage);
      if (showError) showNotification(errorMessage);
    } finally {
      setWeatherLoading(false);
    }
  }

  async function loadFarmerToolsData(farmerId = account?.id) {
    if (!farmerId) return;
    setFarmerLoading(true);
    try {
      const [productsResult, ordersResult, logsResult] = await Promise.all([
        supabase.from("products").select("*").eq("farmer_id", farmerId).order("created_at", { ascending: false }),
        supabase.from("orders").select("*").eq("farmer_id", farmerId).order("created_at", { ascending: false }),
        supabase.from("diagnostic_logs").select("*").eq("user_id", farmerId).order("created_at", { ascending: false }),
      ]);
      if (productsResult.error) throw new Error(productsResult.error.message);
      if (ordersResult.error) throw new Error(ordersResult.error.message);
      if (logsResult.error) throw new Error(logsResult.error.message);
      setFarmerProducts((productsResult.data as FarmerProduct[]) || []);
      setFarmerOrders((ordersResult.data as FarmerOrder[]) || []);
      setHealthLogs((logsResult.data as HealthLog[]) || []);
    } catch (error) {
      showNotification(error instanceof Error ? error.message : "Failed to load farmer tools data.");
    } finally {
      setFarmerLoading(false);
    }
  }

  const filteredProducts = useMemo(() => {
    let data = [...products];
    if (search.trim()) data = data.filter((p) => p.name.toLowerCase().includes(search.toLowerCase()));
    if (category !== "All Categories") data = data.filter((p) => p.category === category);
    if (sortBy === "Price: Low to High") data.sort((a, b) => a.price - b.price);
    else if (sortBy === "Price: High to Low") data.sort((a, b) => b.price - a.price);
    return data;
  }, [products, search, category, sortBy]);

  const cartCount = cart.reduce((sum, item) => sum + item.quantity, 0);
  const subtotal = cart.reduce((sum, item) => sum + item.price * item.quantity, 0);
  const shipping = checkoutForm.deliveryMethod === "Delivery" && cart.length > 0 ? 50 : 0;
  const total = subtotal + shipping;

  const farmerRevenue = farmerOrders.reduce((sum, order) => {
    const status = String(order.status || "").toLowerCase();
    if (status.includes("cancel")) return sum;
    return sum + Number(order.total_amount || 0);
  }, 0);
  const farmerPendingOrders = farmerOrders.filter((order) => String(order.status || "").toLowerCase() === "pending").length;
  const latestHealthLog = healthLogs[0];

  const paymentMethods = checkoutForm.deliveryMethod === "Pickup" ? ["Cash", "GCash", "Card"] : ["Cash on Delivery", "GCash", "Card"];

  const farmerNotices = useMemo<FarmerNotice[]>(() => {
    const notices: FarmerNotice[] = [];
    if (!weather) {
      notices.push({
        id: "weather-unavailable",
        title: "Weather Advisory",
        message: weatherLoading ? "Loading live weather data..." : weatherError || "Live weather data is not available yet.",
        tone: "info",
      });
      return notices;
    }
    const weatherText = `${weather.condition} ${weather.description}`.toLowerCase();
    if (weather.humidity >= 75) notices.push({ id: "humidity", title: "High Humidity", message: "High humidity detected. Monitor lettuce leaves for fungal disease symptoms.", tone: "warning" });
    if (weatherText.includes("rain")) notices.push({ id: "rain", title: "Rain Advisory", message: "Rain is detected. Avoid unnecessary watering and check farm drainage.", tone: "info" });
    if (weatherText.includes("cloud")) notices.push({ id: "cloudy", title: "Cloudy Conditions", message: "Cloudy conditions today. Inspect leaves for prolonged moisture.", tone: "info" });
    if (weather.temperature >= 30) notices.push({ id: "heat", title: "High Temperature", message: "High temperature detected. Water during cooler hours and monitor heat stress.", tone: "warning" });
    if (notices.length === 0) notices.push({ id: "stable", title: "Weather Conditions Stable", message: "Current weather conditions are stable. Continue normal crop monitoring.", tone: "success" });
    return notices;
  }, [weather, weatherError, weatherLoading]);

  function addToCart(product: Product) {
    if (isFarmer) {
      showNotification("Farmer accounts can view products but cannot buy.");
      return;
    }
    const currentFarmerIds = new Set(cart.map((item) => item.farmerId).filter(Boolean));
    if (product.farmerId && currentFarmerIds.size > 0 && !currentFarmerIds.has(product.farmerId)) {
      showNotification("Please checkout products from one farmer at a time.");
      return;
    }
    setCart((prev) => {
      const existing = prev.find((item) => item.id === product.id);
      if (existing) {
        return prev.map((item) => item.id === product.id ? { ...item, quantity: Math.min(item.quantity + 1, product.stock) } : item);
      }
      return [...prev, { ...product, quantity: 1 }];
    });
    showNotification(`Added ${product.name} to cart`);
  }

  function updateQuantity(productId: number, delta: number) {
    setCart((prev) => prev.map((item) => item.id === productId ? { ...item, quantity: item.quantity + delta } : item).filter((item) => item.quantity > 0));
  }

  function showNotification(msg: string) {
    setMessage(msg);
    setTimeout(() => setMessage(""), 4200);
  }

  function getFriendlyAuthMessage(messageValue: string) {
    const lower = messageValue.toLowerCase();
    if (lower.includes("invalid login credentials")) return "Invalid email or password. Please check your credentials.";
    if (lower.includes("already registered") || lower.includes("user already registered") || lower.includes("already exists") || lower.includes("duplicate")) return "This email is already registered. Please log in instead.";
    if (lower.includes("email not confirmed")) return "Please confirm your email before logging in.";
    return messageValue;
  }

  async function handleLogout() {
    await supabase.auth.signOut();
    setAccount(null);
    setFarmerToolsOpen(false);
    setFarmerProducts([]);
    setFarmerOrders([]);
    setHealthLogs([]);
    setWeather(null);
    setWeatherError("");
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
      const { data: existingProfile } = await supabase.from("users").select("id").eq("email", cleanEmail).maybeSingle();
      if (existingProfile) {
        showNotification("This email is already registered. Please log in instead.");
        setAuthLoading(false);
        return;
      }
      const { data, error } = await supabase.auth.signUp({
        email: cleanEmail,
        password: cleanPassword,
        options: { data: { full_name: cleanName, role: "buyer" } },
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
      const { error: profileError } = await supabase.from("users").insert([{ id: data.user.id, full_name: cleanName, email: cleanEmail, role: "buyer" }]);
      if (profileError) {
        showNotification(getFriendlyAuthMessage(profileError.message));
        setAuthLoading(false);
        return;
      }
      setAccount({ id: data.user.id, name: cleanName, email: cleanEmail, role: "buyer" });
      setAuthOpen(false);
      setAuthForm({ name: "", email: "", password: "" });
      showNotification("Welcome to GreenGuard AI!");
      setAuthLoading(false);
      return;
    }

    const { data, error } = await supabase.auth.signInWithPassword({ email: cleanEmail, password: cleanPassword });
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
    const { data: profile, error: profileError } = await supabase.from("users").select("full_name, email, role").eq("id", data.user.id).maybeSingle();
    if (profileError) {
      await supabase.auth.signOut();
      showNotification("Unable to verify your account profile.");
      setAuthLoading(false);
      return;
    }
    const role = String(profile?.role || data.user.user_metadata?.role || "buyer").toLowerCase();
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
      name: profile?.full_name || data.user.user_metadata?.full_name || (role === "farmer" ? "Farmer" : "Buyer"),
      email: profile?.email || data.user.email || cleanEmail,
      role: role as UserRole,
    });
    if (role === "farmer") {
      setFarmerToolsOpen(true);
      setCart([]);
      localStorage.removeItem("letusplant-cart");
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
    const description = sellForm.description.trim() || "Fresh lettuce crop from local farmer.";
    const imageValue = sellForm.imageUrl.trim() || defaultProductImage;

    if (!name) { showNotification("Product name is required."); return; }
    if (!price || price <= 0) { showNotification("Valid price is required."); return; }
    if (!stock || stock <= 0) { showNotification("Valid stock is required."); return; }

    setSavingProduct(true);
    try {
      const payload = {
        name, category: categoryValue, price, stock, farmer_id: account.id, farmer: account.name,
        farmer_name: account.name, badge: "Farmer Listed", description, freshness_info: description,
        image: imageValue, image_url: imageValue, location: sellForm.location.trim() || "Local Farm",
        status: "Available", updated_at: new Date().toISOString(),
      };
      const { error } = await supabase.from("products").insert([payload]);
      if (error) throw new Error(error.message);

      setSellForm({ name: "", category: "Fresh Lettuce", price: "", stock: "", description: "", imageUrl: "", location: "" });
      await Promise.all([loadProducts(), loadFarmerToolsData(account.id)]);
      setFarmerTab("listings");
      showNotification("Product published successfully.");
    } catch (error) {
      showNotification(error instanceof Error ? error.message : "Failed to publish product.");
    } finally {
      setSavingProduct(false);
    }
  }

  function handleDeliveryMethodChange(method: "Delivery" | "Pickup") {
    setCheckoutForm((previous) => ({
      ...previous,
      deliveryMethod: method,
      paymentMethod: method === "Pickup" && previous.paymentMethod === "Cash on Delivery" ? "Cash" : method === "Delivery" && previous.paymentMethod === "Cash" ? "Cash on Delivery" : previous.paymentMethod,
    }));
  }

  async function handleCheckout() {
    if (account?.role === "farmer") {
      showNotification("Farmer accounts cannot place marketplace orders.");
      setCurrentView("shop");
      return;
    }
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
    const checkoutFarmerIds = new Set(cart.map((item) => item.farmerId).filter(Boolean));
    if (checkoutFarmerIds.size > 1) {
      showNotification("Please checkout products from one farmer at a time.");
      return;
    }
    if (!checkoutForm.fullName || !checkoutForm.phone || !checkoutForm.email) {
      showNotification("Please fill in your contact details.");
      return;
    }
    if (checkoutForm.deliveryMethod === "Delivery" && (!checkoutForm.address || !checkoutForm.city || !checkoutForm.postalCode)) {
      showNotification("Please provide your full delivery address.");
      return;
    }

    setLoadingOrder(true);
    const payload = {
      ...checkoutForm,
      items: cart.map((item) => ({
        productId: item.id, productName: item.name, price: item.price, quantity: item.quantity,
      })),
    };

    try {
      const { data: { session } } = await supabase.auth.getSession();
      if (!session?.access_token) {
        showNotification("Your session expired. Please log in again.");
        setLoadingOrder(false);
        return;
      }
      const res = await fetch("/api?type=create-order", {
        method: "POST",
        headers: { "Content-Type": "application/json", Authorization: `Bearer ${session.access_token}` },
        body: JSON.stringify(payload),
      });
      const json = await res.json();
      if (json.success) {
        setCart([]);
        await loadOrders();
        showNotification("Order placed successfully! 🎉");
        setCurrentView("orders");
        window.scrollTo({ top: 0, behavior: "smooth" });
      } else {
        showNotification(json.message || "Checkout failed. Check database.");
      }
    } catch {
      showNotification("An error occurred during checkout");
    }
    setLoadingOrder(false);
  }

  // ==================== RENDER FUNCTIONS ====================
  const renderFarmerTools = () => {
    if (!isFarmer) return null;

    if (!farmerToolsOpen) {
      return (
        <div className="mx-auto mb-8 max-w-7xl px-4 sm:px-6 lg:px-8">
          <button onClick={() => setFarmerToolsOpen(true)} className="flex w-full items-center justify-between rounded-[28px] border border-green-200 bg-white px-6 py-4 text-left shadow-sm transition-all hover:-translate-y-1 hover:shadow-xl">
            <div>
              <p className="text-xs font-black uppercase tracking-[3px] text-[#2F6B3B]">Farmer Account Detected</p>
              <h3 className="mt-1 text-xl font-black text-[#1E2A1F]">Open Farmer Tools</h3>
              <p className="mt-1 text-sm text-[#5C6B5D]">Sell crops, monitor health logs, and manage buyer orders.</p>
            </div>
            <div className="rounded-full bg-[#2F6B3B] px-5 py-2 text-sm font-black text-white">Open</div>
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
                <p className="text-xs font-black uppercase tracking-[3px] text-[#2F6B3B]">Farmer Tools</p>
                <h2 className="mt-2 text-3xl font-black tracking-tight text-[#1E2A1F]">Sell crops and monitor your farm</h2>
                <p className="mt-2 max-w-2xl text-sm leading-6 text-[#5C6B5D]">This panel is visible only to farmer accounts.</p>
              </div>
              <div className="flex flex-wrap gap-3">
                <button onClick={() => { loadFarmerToolsData(); loadFarmerWeather(farmerWeatherLocation); }} disabled={farmerLoading || weatherLoading} className="rounded-full border border-green-200 bg-white px-5 py-2.5 text-sm font-black text-[#2F6B3B] transition hover:bg-green-50 disabled:opacity-60">
                  {farmerLoading || weatherLoading ? "Refreshing..." : "Refresh"}
                </button>
                <button onClick={() => setFarmerToolsOpen(false)} className="rounded-full bg-[#1E2A1F] px-5 py-2.5 text-sm font-black text-white transition hover:bg-[#2F6B3B]">Minimize</button>
              </div>
            </div>

            <div className="mt-6 grid grid-cols-2 gap-4 md:grid-cols-4">
              <FarmerStat label="My Listings" value={farmerProducts.length} />
              <FarmerStat label="Health Logs" value={healthLogs.length} />
              <FarmerStat label="Buyer Orders" value={farmerOrders.length} />
              <FarmerStat label="Pending Orders" value={farmerPendingOrders} />
            </div>
          </div>

          <div className="flex flex-wrap gap-2 border-b border-green-100 p-4">
            {[
              { id: "sell", label: "Sell Product" },
              { id: "listings", label: "Manage Listings" },
              { id: "health", label: "Health Logs / Monitoring" },
              { id: "orders", label: "Farmer Orders" },
            ].map((tab) => (
              <button key={tab.id} onClick={() => setFarmerTab(tab.id as FarmerToolTab)} className={`rounded-full px-5 py-2.5 text-sm font-black transition ${farmerTab === tab.id ? "bg-[#2F6B3B] text-white shadow-lg shadow-green-900/20" : "bg-[#F7FBF6] text-[#5C6B5D] hover:bg-green-100 hover:text-[#2F6B3B]"}`}>
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
      <form onSubmit={handlePublishProduct} className="rounded-[28px] border border-green-100 bg-[#F7FBF6] p-6">
        <h3 className="text-2xl font-black text-[#1E2A1F]">Sell Product</h3>
        <p className="mt-2 text-sm text-[#5C6B5D]">Publish a lettuce product.</p>

        <div className="mt-6 grid gap-4 md:grid-cols-2">
          <div className="md:col-span-2">
            <label className="mb-1 block text-xs font-black uppercase tracking-wider text-[#5C6B5D]">Product Name</label>
            <input value={sellForm.name} onChange={(e) => setSellForm({ ...sellForm, name: e.target.value })} placeholder="Example: Fresh Romaine Lettuce" className="w-full rounded-2xl border border-green-100 bg-white px-5 py-3.5 text-sm font-bold outline-none focus:border-[#2F6B3B]" />
          </div>
          <div>
            <label className="mb-1 block text-xs font-black uppercase tracking-wider text-[#5C6B5D]">Category</label>
            <select value={sellForm.category} onChange={(e) => setSellForm({ ...sellForm, category: e.target.value })} className="w-full rounded-2xl border border-green-100 bg-white px-5 py-3.5 text-sm font-bold outline-none focus:border-[#2F6B3B]">
              <option>Fresh Lettuce</option><option>Premium Lettuce</option><option>Seeds</option><option>Bundles</option><option>Bulk Orders</option>
            </select>
          </div>
          <div>
            <label className="mb-1 block text-xs font-black uppercase tracking-wider text-[#5C6B5D]">Location</label>
            <input value={sellForm.location} onChange={(e) => setSellForm({ ...sellForm, location: e.target.value })} placeholder="Example: Lamac, Consolacion" className="w-full rounded-2xl border border-green-100 bg-white px-5 py-3.5 text-sm font-bold outline-none focus:border-[#2F6B3B]" />
          </div>
          <div>
            <label className="mb-1 block text-xs font-black uppercase tracking-wider text-[#5C6B5D]">Price</label>
            <input type="number" min="1" value={sellForm.price} onChange={(e) => setSellForm({ ...sellForm, price: e.target.value })} placeholder="₱" className="w-full rounded-2xl border border-green-100 bg-white px-5 py-3.5 text-sm font-bold outline-none focus:border-[#2F6B3B]" />
          </div>
          <div>
            <label className="mb-1 block text-xs font-black uppercase tracking-wider text-[#5C6B5D]">Stock</label>
            <input type="number" min="1" value={sellForm.stock} onChange={(e) => setSellForm({ ...sellForm, stock: e.target.value })} placeholder="Quantity" className="w-full rounded-2xl border border-green-100 bg-white px-5 py-3.5 text-sm font-bold outline-none focus:border-[#2F6B3B]" />
          </div>
          <div className="md:col-span-2">
            <label className="mb-1 block text-xs font-black uppercase tracking-wider text-[#5C6B5D]">Image URL</label>
            <input value={sellForm.imageUrl} onChange={(e) => setSellForm({ ...sellForm, imageUrl: e.target.value })} placeholder="Paste image URL" className="w-full rounded-2xl border border-green-100 bg-white px-5 py-3.5 text-sm font-bold outline-none focus:border-[#2F6B3B]" />
          </div>
          <div className="md:col-span-2">
            <label className="mb-1 block text-xs font-black uppercase tracking-wider text-[#5C6B5D]">Description</label>
            <textarea value={sellForm.description} onChange={(e) => setSellForm({ ...sellForm, description: e.target.value })} placeholder="Describe freshness..." rows={4} className="w-full resize-none rounded-2xl border border-green-100 bg-white px-5 py-3.5 text-sm font-bold outline-none focus:border-[#2F6B3B]" />
          </div>
        </div>

        <button type="submit" disabled={savingProduct} className="mt-6 w-full rounded-full bg-[#2F6B3B] px-8 py-4 text-sm font-black text-white shadow-lg shadow-green-900/20 transition hover:-translate-y-1 hover:bg-[#1E2A1F] disabled:opacity-60">
          {savingProduct ? "Publishing..." : "Publish Product"}
        </button>
      </form>

      <div className="rounded-[28px] border border-green-100 bg-white p-6">
        <h3 className="text-2xl font-black text-[#1E2A1F]">Product Preview</h3>
        <div className="mt-6 overflow-hidden rounded-[28px] border border-green-100 bg-white shadow-sm">
          <div className="h-56 bg-cover bg-center" style={{ backgroundImage: `url(${sellForm.imageUrl.trim() || defaultProductImage})` }} />
          <div className="p-5">
            <p className="text-xs font-black uppercase tracking-wider text-[#2F6B3B]">{sellForm.category || "Fresh Lettuce"}</p>
            <h4 className="mt-1 text-xl font-black text-[#1E2A1F]">{sellForm.name || "Product name"}</h4>
            <p className="mt-2 text-sm text-[#5C6B5D]">Farmer: {account?.name || "Farmer"}</p>
            <p className="mt-4 text-3xl font-black text-[#2F6B3B]">₱{sellForm.price || "0"}</p>
            <p className="mt-2 text-sm font-bold text-[#5C6B5D]">Stock: {sellForm.stock || "0"}</p>
            <p className="mt-4 text-sm leading-6 text-[#5C6B5D]">{sellForm.description || "Fresh lettuce crop from local farmer."}</p>
          </div>
        </div>
      </div>
    </div>
  );

  const renderFarmerListings = () => (
    <div>
      <div className="mb-5 flex flex-col gap-3 md:flex-row md:items-center md:justify-between">
        <div>
          <h3 className="text-2xl font-black text-[#1E2A1F]">Manage My Listings</h3>
          <p className="mt-1 text-sm text-[#5C6B5D]">Products owned by your farmer account.</p>
        </div>
        <button onClick={() => setFarmerTab("sell")} className="rounded-full bg-[#2F6B3B] px-5 py-2.5 text-sm font-black text-white">Add Product</button>
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
                <tr><td colSpan={5} className="px-6 py-14 text-center text-sm font-bold text-[#5C6B5D]">No products listed yet.</td></tr>
              ) : (
                farmerProducts.map((product) => (
                  <tr key={product.id}>
                    <td className="px-6 py-4">
                      <div className="flex items-center gap-3">
                        <div className="h-12 w-12 rounded-2xl bg-cover bg-center" style={{ backgroundImage: `url(${product.image_url || product.image || defaultProductImage})` }} />
                        <div>
                          <p className="font-black text-[#1E2A1F]">{product.name || "Unnamed Product"}</p>
                          <p className="text-xs text-[#5C6B5D]">{formatDate(product.created_at)}</p>
                        </div>
                      </div>
                    </td>
                    <td className="px-6 py-4 text-sm font-bold text-[#5C6B5D]">{product.category || "N/A"}</td>
                    <td className="px-6 py-4 text-sm font-black text-[#2F6B3B]">₱{formatMoney(product.price)}</td>
                    <td className="px-6 py-4 text-sm font-bold text-[#1E2A1F]">{product.stock || 0}</td>
                    <td className="px-6 py-4"><StatusPill text={product.status || "Available"} /></td>
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
    <div className="space-y-6">
      <div className="grid gap-6 lg:grid-cols-[0.9fr_1.1fr]">
        <div className="rounded-[28px] border border-green-100 bg-[#F7FBF6] p-6">
          <h3 className="text-2xl font-black text-[#1E2A1F]">Health Logs / Monitoring</h3>
          <p className="mt-2 text-sm leading-6 text-[#5C6B5D]">View prototype/demo scan records and live weather.</p>

          <div className="mt-6 grid gap-4">
            <div className="rounded-2xl bg-white p-5 shadow-sm">
              <p className="text-xs font-black uppercase tracking-[2px] text-[#5C6B5D]">Latest Result</p>
              <p className="mt-1 text-2xl font-black text-[#1E2A1F]">{latestHealthLog ? getDiseaseName(latestHealthLog) : "No scan yet"}</p>
            </div>
            <div className="rounded-2xl bg-white p-5 shadow-sm">
              <p className="text-xs font-black uppercase tracking-[2px] text-[#5C6B5D]">Confidence</p>
              <p className="mt-1 text-2xl font-black text-[#2F6B3B]">{latestHealthLog ? getConfidence(latestHealthLog) : "N/A"}</p>
            </div>
            <div className="rounded-2xl bg-white p-5 shadow-sm">
              <p className="text-xs font-black uppercase tracking-[2px] text-[#5C6B5D]">Temperature</p>
              <p className="mt-1 text-2xl font-black text-[#1E2A1F]">{latestHealthLog ? getTemperature(latestHealthLog) : "N/A"}</p>
            </div>
          </div>

          <button onClick={() => router.push("/health-logs")} className="mt-6 w-full rounded-full bg-[#2F6B3B] px-8 py-4 text-sm font-black text-white shadow-lg shadow-green-900/20 transition hover:-translate-y-1 hover:bg-[#1E2A1F]">Open Full Health Logs Page</button>
        </div>

        <div className="rounded-[28px] border border-green-100 bg-white p-6">
          <h3 className="text-2xl font-black text-[#1E2A1F]">Recent Scan Records</h3>
          <div className="mt-5 grid gap-4">
            {healthLogs.length === 0 ? (
              <div className="flex min-h-[220px] items-center justify-center rounded-3xl border border-dashed border-green-200 bg-[#F7FBF6] text-sm font-bold text-[#5C6B5D]">No health logs yet.</div>
            ) : (
              healthLogs.slice(0, 4).map((log) => (
                <div key={log.id} className="rounded-[22px] border border-green-100 bg-[#F7FBF6] p-4">
                  <div className="flex flex-col gap-4 md:flex-row">
                    {log.image_url ? <img src={log.image_url} alt="Health log" className="h-28 w-full rounded-2xl object-cover md:w-36" /> : <div className="flex h-28 w-full items-center justify-center rounded-2xl bg-white text-xs font-bold text-[#5C6B5D] md:w-36">No Image</div>}
                    <div className="flex-1">
                      <p className="text-lg font-black text-[#1E2A1F]">{getDiseaseName(log)}</p>
                      <p className="mt-1 text-sm text-[#5C6B5D]">Confidence: <span className="font-black text-[#2F6B3B]">{getConfidence(log)}</span></p>
                      <p className="text-sm text-[#5C6B5D]">Weather: {log.weather_condition || log.weather || "N/A"}</p>
                      <p className="text-sm text-[#5C6B5D]">Date: {formatDate(log.captured_at || log.created_at)}</p>
                    </div>
                  </div>
                </div>
              ))
            )}
          </div>
        </div>
      </div>

      <div className="rounded-[28px] border border-green-100 bg-white p-6 shadow-sm">
        <div className="flex flex-col gap-4 md:flex-row md:items-start md:justify-between">
          <div>
            <p className="text-xs font-black uppercase tracking-[3px] text-[#2F6B3B]">Live Weather & Weather Advisory</p>
            <h3 className="mt-2 text-2xl font-black text-[#1E2A1F]">{weather?.location || farmerWeatherLocation}</h3>
          </div>
          <button onClick={() => loadFarmerWeather(farmerWeatherLocation)} disabled={weatherLoading} className="rounded-full border border-green-200 bg-white px-5 py-2.5 text-sm font-black text-[#2F6B3B] transition hover:bg-green-50 disabled:opacity-60">
            {weatherLoading ? "Refreshing..." : "Refresh"}
          </button>
        </div>

        {weather ? (
          <>
            <div className="mt-6 grid grid-cols-2 gap-4 md:grid-cols-3">
              <WeatherMetric label="Temperature" value={`${weather.temperature.toFixed(1)}°C`} />
              <WeatherMetric label="Condition" value={weather.condition} />
              <WeatherMetric label="Humidity" value={`${weather.humidity}%`} />
              <WeatherMetric label="Wind Speed" value={`${weather.windSpeed.toFixed(1)} m/s`} />
              <WeatherMetric label="Description" value={weather.description} />
              <WeatherMetric label="Updated" value={formatWeatherTime(weather.updatedAt)} />
            </div>

            <div className="mt-6 border-t border-green-100 pt-6">
              <p className="text-xs font-black uppercase tracking-[3px] text-[#2F6B3B]">Weather Advisory</p>
              <div className="mt-4 grid gap-3">
                {farmerNotices.map((notice) => (
                  <div key={notice.id} className={`rounded-2xl border p-4 ${notice.tone === "warning" ? "border-amber-200 bg-amber-50 text-amber-800" : notice.tone === "success" ? "border-green-200 bg-green-50 text-green-700" : "border-blue-200 bg-blue-50 text-blue-700"}`}>
                    <p className="text-xs font-black uppercase tracking-[2px]">{notice.title}</p>
                    <p className="mt-1 text-sm font-bold leading-6">{notice.message}</p>
                  </div>
                ))}
              </div>
            </div>
          </>
        ) : (
          <div className="mt-6 rounded-2xl bg-[#F7FBF6] p-5 text-sm font-bold text-[#5C6B5D]">{weatherLoading ? "Loading live weather..." : weatherError || "Live weather is not available yet."}</div>
        )}
      </div>
    </div>
  );

  const renderFarmerOrders = () => (
    <div>
      <div className="mb-5">
        <h3 className="text-2xl font-black text-[#1E2A1F]">My Buyer Orders</h3>
        <p className="mt-1 text-sm text-[#5C6B5D]">Orders where your farmer account is assigned as seller.</p>
      </div>

      <div className="mb-5 grid gap-4 md:grid-cols-3">
        <FarmerSummaryCard label="Total Orders" value={String(farmerOrders.length)} />
        <FarmerSummaryCard label="Pending Orders" value={String(farmerPendingOrders)} />
        <FarmerSummaryCard label="Gross Sales" value={`₱${formatMoney(farmerRevenue)}`} />
      </div>

      <div className="grid gap-4">
        {farmerOrders.length === 0 ? (
          <div className="flex min-h-[220px] items-center justify-center rounded-3xl border border-dashed border-green-200 bg-[#F7FBF6] text-sm font-bold text-[#5C6B5D]">No buyer orders yet.</div>
        ) : (
          farmerOrders.map((order) => (
            <div key={order.id} className="rounded-[26px] border border-green-100 bg-[#F7FBF6] p-5">
              <div className="flex flex-col gap-5 md:flex-row md:items-center md:justify-between">
                <div>
                  <p className="text-xs font-black uppercase tracking-[2px] text-[#5C6B5D]">{order.order_code || order.id}</p>
                  <h4 className="mt-1 text-xl font-black text-[#1E2A1F]">{order.shipping_name || order.email || "Customer"}</h4>
                  <p className="mt-1 text-sm text-[#5C6B5D]">{formatDate(order.created_at)}</p>
                  <p className="mt-1 text-sm text-[#5C6B5D]">{order.shipping_address || "No address"}</p>
                </div>
                <div className="text-left md:text-right">
                  <p className="text-3xl font-black text-[#2F6B3B]">₱{formatMoney(order.total_amount)}</p>
                  <div className="mt-3 flex flex-wrap gap-2 md:justify-end">
                    <StatusPill text={order.status || "Pending"} />
                    <StatusPill text={order.payment_status || "Unpaid"} />
                    <StatusPill text={order.delivery_status || "Pending"} />
                  </div>
                  {(order.proof_image_url || order.delivery_proof_url) && (
                    <a href={order.proof_image_url || order.delivery_proof_url || "#"} target="_blank" rel="noreferrer" className="mt-4 inline-flex rounded-full bg-[#2F6B3B] px-5 py-2 text-sm font-black text-white">View Proof</a>
                  )}
                </div>
              </div>
            </div>
          ))
        )}
      </div>
    </div>
  );

  const renderHome = () => (
    <div className="relative mx-auto grid min-h-[85vh] max-w-7xl items-center gap-16 overflow-hidden px-4 py-16 sm:px-6 lg:grid-cols-2 lg:px-8">
      <div className="pointer-events-none absolute -left-28 top-12 h-72 w-72 rounded-full bg-green-200/35 blur-3xl" />
      <div className="pointer-events-none absolute -right-24 bottom-10 h-80 w-80 rounded-full bg-[#5DBB63]/15 blur-3xl" />

      <div className="relative z-10 animate-in slide-in-from-left-8 duration-1000 fade-in">
        <div className="inline-flex items-center gap-2 rounded-full border border-green-200 bg-white/75 px-4 py-2 text-xs font-bold uppercase tracking-widest text-[#2F6B3B] shadow-sm backdrop-blur-sm">
          <span className="relative flex h-2 w-2"><span className="absolute inline-flex h-full w-full animate-ping rounded-full bg-green-400 opacity-75" /><span className="relative inline-flex h-2 w-2 rounded-full bg-[#2F6B3B]" /></span>
          Fresh. Verified. Delivered.
        </div>

        <h1 className="mt-8 text-5xl font-black leading-[1.1] tracking-tight md:text-6xl lg:text-[72px]">
          Premium lettuce, <br />
          <span className="bg-gradient-to-r from-[#2F6B3B] to-[#5DBB63] bg-clip-text text-transparent">trust verified.</span>
        </h1>

        <p className="mt-6 max-w-xl text-lg leading-relaxed text-[#5C6B5D]">
          Buy fresh lettuce, premium seeds, and bulk orders directly from verified local farmers.
        </p>

        <div className="mt-10 flex flex-wrap items-center gap-5">
          <button onClick={() => setCurrentView("shop")} className="group flex items-center gap-2 rounded-full bg-[#2F6B3B] px-8 py-4 text-sm font-bold text-white shadow-[0_8px_20px_rgba(47,107,59,0.3)] ring-4 ring-[#2F6B3B]/10 transition-all duration-300 hover:-translate-y-1 hover:shadow-[0_12px_25px_rgba(47,107,59,0.4)] active:scale-95">
            Enter Marketplace
            <svg className="h-4 w-4 transition-transform group-hover:translate-x-1" fill="none" viewBox="0 0 24 24" stroke="currentColor"><path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2.5} d="M14 5l7 7m0 0l-7 7m7-7H3" /></svg>
          </button>
        </div>
      </div>

      <div className="relative z-10 hidden lg:block animate-in slide-in-from-right-8 duration-1000 fade-in delay-150">
        <div className="group relative overflow-hidden rounded-[40px] border-[8px] border-white bg-white shadow-2xl shadow-green-900/10 transition-transform duration-700 hover:-translate-y-4">
          <div className="h-[650px] w-full bg-cover bg-center transition-transform duration-[2000ms] group-hover:scale-110" style={{ backgroundImage: "url('https://images.unsplash.com/photo-1540420773420-3366772f4999?q=80&w=1600&auto=format&fit=crop')" }} />
          <div className="absolute inset-0 bg-gradient-to-t from-black/60 via-transparent to-transparent opacity-50 transition-opacity duration-700 group-hover:opacity-80" />
          <div className="absolute bottom-10 left-10 translate-y-4 rounded-3xl border border-white/20 bg-white/95 p-6 shadow-2xl backdrop-blur-xl transition-all duration-700 group-hover:translate-y-0">
            <div className="flex items-center gap-3">
              <div className="flex h-12 w-12 items-center justify-center rounded-full bg-green-100 shadow-inner">
                <svg className="h-6 w-6 text-green-600" fill="currentColor" viewBox="0 0 20 20"><path fillRule="evenodd" d="M16.707 5.293a1 1 0 010 1.414l-8 8a1 1 0 01-1.414 0l-4-4a1 1 0 011.414-1.414L8 12.586l7.293-7.293a1 1 0 011.414 0z" clipRule="evenodd" /></svg>
              </div>
              <div>
                <p className="text-xs font-bold uppercase tracking-wider text-[#2F6B3B]">AI Verified</p>
                <p className="text-lg font-black text-gray-900">100% Healthy Crop</p>
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
          <p className="text-sm font-bold uppercase tracking-widest text-[#2F6B3B]">Marketplace</p>
          <h2 className="mt-2 text-4xl font-black tracking-tight md:text-5xl">Shop the harvest</h2>
        </div>
      </div>

      <div className="mt-10 flex flex-wrap gap-4 rounded-[28px] bg-white p-3 shadow-sm ring-1 ring-black/5 animate-in slide-in-from-bottom-6 fade-in duration-500 delay-75">
        <input className="min-w-[250px] flex-1 rounded-xl bg-[#F7FBF6] px-5 py-3.5 text-sm font-medium outline-none transition-all focus:bg-green-50 focus:ring-2 focus:ring-[#2F6B3B]/20" placeholder="Search fresh lettuce..." value={search} onChange={(e) => setSearch(e.target.value)} />
        <select className="cursor-pointer rounded-xl bg-[#F7FBF6] px-5 py-3.5 text-sm font-medium outline-none transition-colors hover:bg-green-50" value={category} onChange={(e) => setCategory(e.target.value)}>
          <option>All Categories</option><option>Fresh Lettuce</option><option>Premium Lettuce</option><option>Seeds</option><option>Bundles</option><option>Bulk Orders</option>
        </select>
        <select className="cursor-pointer rounded-xl bg-[#F7FBF6] px-5 py-3.5 text-sm font-medium outline-none transition-colors hover:bg-green-50" value={sortBy} onChange={(e) => setSortBy(e.target.value)}>
          <option>Default</option><option>Price: Low to High</option><option>Price: High to Low</option><option>Newest</option>
        </select>
      </div>

      <div className="mt-12 grid gap-8 md:grid-cols-2 xl:grid-cols-3">
        {filteredProducts.map((product, i) => (
          <div key={product.id} className="group flex flex-col rounded-[32px] bg-white p-3 shadow-sm ring-1 ring-black/5 transition-all duration-500 hover:-translate-y-3 hover:shadow-2xl hover:shadow-green-900/10 animate-in slide-in-from-bottom-8 fade-in fill-mode-both" style={{ animationDelay: `${i * 50}ms` }}>
            <div className="relative h-64 w-full overflow-hidden rounded-[24px]">
              <div className="absolute inset-0 bg-cover bg-center transition-transform duration-700 group-hover:scale-110" style={{ backgroundImage: `url(${product.image})` }} />
              <div className="absolute left-4 top-4 flex w-[calc(100%-2rem)] items-center justify-between">
                <span className="rounded-full bg-white/90 px-3 py-1.5 text-xs font-bold text-[#2F6B3B] shadow-sm backdrop-blur-md">{product.badge}</span>
                <span className="rounded-full bg-black/50 px-3 py-1.5 text-xs font-bold text-white backdrop-blur-md">Stock: {product.stock}</span>
              </div>
            </div>

            <div className="flex flex-1 flex-col p-5">
              <p className="text-sm font-bold text-[#5C6B5D]">{product.farmer}</p>
              <h3 className="mt-1 text-xl font-black text-gray-900">{product.name}</h3>
              <p className="mt-1 text-xs font-medium uppercase tracking-wider text-gray-500">{product.category}</p>

              <div className="mt-auto flex items-center justify-between pt-6">
                <p className="text-3xl font-black text-[#2F6B3B]">₱{product.price}</p>
                <div className="flex gap-2">
                  <button onClick={() => setSelectedProduct(product)} className="flex h-12 w-12 items-center justify-center rounded-full bg-green-50 text-[#2F6B3B] transition-colors hover:bg-green-100">👁</button>
                  {!isFarmer && (
                    <button onClick={() => addToCart(product)} disabled={product.stock === 0} className="flex h-12 w-12 items-center justify-center rounded-full bg-[#2F6B3B] text-white shadow-[0_8px_16px_rgba(47,107,59,0.3)] transition-all duration-300 hover:scale-110 active:scale-95 disabled:opacity-50 disabled:hover:scale-100">
                      <svg className="h-5 w-5" fill="none" viewBox="0 0 24 24" stroke="currentColor"><path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2.5} d="M12 4v16m8-8H4" /></svg>
                    </button>
                  )}
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
              <h2 className="text-2xl font-black tracking-tight text-gray-900">Your Cart</h2>
              <span className="rounded-full bg-green-50 px-3 py-1 text-xs font-bold text-[#2F6B3B]">{cartCount} Items</span>
            </div>

            {cart.length === 0 ? (
              <div className="flex flex-col items-center justify-center rounded-[24px] border-2 border-dashed border-gray-100 bg-gray-50 py-12 text-center">
                <p className="font-medium text-gray-500">Your cart is completely empty.</p>
                <button onClick={() => setCurrentView("shop")} className="mt-4 rounded-full bg-white px-6 py-2 text-sm font-bold text-[#2F6B3B] shadow-sm ring-1 ring-gray-200 hover:bg-gray-50">Browse Store</button>
              </div>
            ) : (
              <div className="space-y-4">
                {cart.map((item, i) => (
                  <div key={item.id} className="group flex items-center gap-4 rounded-[20px] border border-gray-100 bg-white p-4 transition-all hover:shadow-md animate-in slide-in-from-bottom-4 fade-in fill-mode-both" style={{ animationDelay: `${i * 100}ms` }}>
                    <div className="h-20 w-20 shrink-0 overflow-hidden rounded-[14px]">
                      <div className="h-full w-full bg-cover bg-center transition-transform duration-500 group-hover:scale-110" style={{ backgroundImage: `url(${item.image})` }} />
                    </div>
                    <div className="flex flex-1 flex-col">
                      <h3 className="text-base font-bold text-gray-900">{item.name}</h3>
                      <p className="text-xs font-medium text-gray-500">{item.farmer}</p>
                      <p className="mt-1 text-lg font-black text-[#2F6B3B]">₱{item.price}</p>
                    </div>
                    <div className="flex flex-col items-center gap-2 rounded-xl bg-gray-50 p-1 sm:flex-row sm:gap-4 sm:px-2 sm:py-1">
                      <button onClick={() => updateQuantity(item.id, -1)} className="flex h-7 w-7 items-center justify-center rounded-lg bg-white font-bold text-gray-600 shadow-sm ring-1 ring-black/5 transition-all hover:bg-gray-100 hover:text-gray-900 active:scale-95">-</button>
                      <span className="w-4 text-center text-sm font-bold text-gray-900">{item.quantity}</span>
                      <button onClick={() => updateQuantity(item.id, 1)} className="flex h-7 w-7 items-center justify-center rounded-lg bg-white font-bold text-gray-600 shadow-sm ring-1 ring-black/5 transition-all hover:bg-gray-100 hover:text-gray-900 active:scale-95">+</button>
                    </div>
                  </div>
                ))}
              </div>
            )}
          </div>

          <div className={`rounded-[32px] bg-white p-8 shadow-sm ring-1 ring-black/5 transition-opacity ${cart.length === 0 ? "pointer-events-none opacity-50" : "opacity-100"}`}>
            <h3 className="text-lg font-black text-gray-900">Delivery Information</h3>
            <div className="mt-6 grid gap-4 md:grid-cols-2">
              <input value={checkoutForm.fullName} onChange={(e) => setCheckoutForm({ ...checkoutForm, fullName: e.target.value })} placeholder="Full Name" className="rounded-2xl border border-gray-100 bg-gray-50 px-5 py-3.5 text-sm font-medium outline-none focus:border-green-300" />
              <input value={checkoutForm.email} onChange={(e) => setCheckoutForm({ ...checkoutForm, email: e.target.value })} placeholder="Email" className="rounded-2xl border border-gray-100 bg-gray-50 px-5 py-3.5 text-sm font-medium outline-none focus:border-green-300" />
              <input value={checkoutForm.phone} onChange={(e) => setCheckoutForm({ ...checkoutForm, phone: e.target.value })} placeholder="Phone" className="rounded-2xl border border-gray-100 bg-gray-50 px-5 py-3.5 text-sm font-medium outline-none focus:border-green-300 md:col-span-2" />
            </div>

            <div className="mt-6">
              <p className="mb-3 text-xs font-black uppercase tracking-[2px] text-gray-500">Delivery Method</p>
              <div className="grid gap-3 sm:grid-cols-2">
                {(["Delivery", "Pickup"] as const).map((method) => (
                  <button key={method} type="button" onClick={() => handleDeliveryMethodChange(method)} className={`rounded-2xl border px-5 py-4 text-left text-sm font-black transition ${checkoutForm.deliveryMethod === method ? "border-[#2F6B3B] bg-green-50 text-[#2F6B3B]" : "border-gray-100 bg-gray-50 text-gray-600"}`}>
                    {method}
                  </button>
                ))}
              </div>
            </div>

            {checkoutForm.deliveryMethod === "Delivery" && (
              <div className="mt-6 grid gap-4">
                <input value={checkoutForm.address} onChange={(e) => setCheckoutForm({ ...checkoutForm, address: e.target.value })} placeholder="Street Address" className="rounded-2xl border border-gray-100 bg-gray-50 px-5 py-3.5 text-sm font-medium outline-none focus:border-green-300" />
                <div className="grid gap-4 sm:grid-cols-2">
                  <input value={checkoutForm.city} onChange={(e) => setCheckoutForm({ ...checkoutForm, city: e.target.value })} placeholder="City" className="rounded-2xl border border-gray-100 bg-gray-50 px-5 py-3.5 text-sm font-medium outline-none focus:border-green-300" />
                  <input value={checkoutForm.postalCode} onChange={(e) => setCheckoutForm({ ...checkoutForm, postalCode: e.target.value })} placeholder="Postal Code" className="rounded-2xl border border-gray-100 bg-gray-50 px-5 py-3.5 text-sm font-medium outline-none focus:border-green-300" />
                </div>
              </div>
            )}

            <div className="mt-6">
              <p className="mb-3 text-xs font-black uppercase tracking-[2px] text-gray-500">Payment Method</p>
              <div className="grid gap-3 sm:grid-cols-3">
                {paymentMethods.map((method) => (
                  <button key={method} type="button" onClick={() => setCheckoutForm({ ...checkoutForm, paymentMethod: method })} className={`rounded-2xl border px-4 py-4 text-sm font-black transition ${checkoutForm.paymentMethod === method ? "border-[#2F6B3B] bg-green-50 text-[#2F6B3B]" : "border-gray-100 bg-gray-50 text-gray-600"}`}>
                    {method}
                  </button>
                ))}
              </div>
            </div>
          </div>
        </div>

        <div className="h-fit rounded-[32px] bg-white p-8 shadow-xl shadow-green-900/5 ring-1 ring-black/5">
          <h2 className="text-2xl font-black text-gray-900">Order Summary</h2>
          <div className="mt-6 space-y-4">
            <div className="flex justify-between text-sm text-gray-500"><span>Subtotal</span><span className="font-bold text-gray-900">₱{subtotal}</span></div>
            <div className="flex justify-between text-sm text-gray-500"><span>Shipping</span><span className="font-bold text-gray-900">₱{shipping}</span></div>
            <div className="flex justify-between text-sm text-gray-500"><span>Delivery Method</span><span className="font-bold text-gray-900">{checkoutForm.deliveryMethod}</span></div>
            <div className="flex justify-between text-sm text-gray-500"><span>Payment Method</span><span className="font-bold text-gray-900">{checkoutForm.paymentMethod}</span></div>
            <div className="border-t border-gray-100 pt-4">
              <div className="flex items-end justify-between">
                <span className="font-black text-gray-900">Total</span>
                <span className="text-4xl font-black text-[#2F6B3B]">₱{total}</span>
              </div>
            </div>
          </div>
          <button onClick={handleCheckout} disabled={loadingOrder || cart.length === 0} className="mt-8 w-full rounded-full bg-[#2F6B3B] px-8 py-4 text-sm font-black text-white shadow-lg shadow-green-900/20 transition hover:-translate-y-1 hover:bg-[#1E2A1F] disabled:cursor-not-allowed disabled:opacity-50">
            {loadingOrder ? "Placing Order..." : "Place Order"}
          </button>
        </div>
      </div>
    </div>
  );

  const renderOrders = () => (
    <div className="mx-auto max-w-7xl px-4 py-16 sm:px-6 lg:px-8">
      <div>
        <p className="text-sm font-bold uppercase tracking-widest text-[#2F6B3B]">My Orders</p>
        <h2 className="mt-2 text-4xl font-black tracking-tight md:text-5xl">Order history</h2>
      </div>

      <div className="mt-10 grid gap-6">
        {orders.length === 0 ? (
          <div className="flex min-h-[300px] items-center justify-center rounded-[32px] border-2 border-dashed border-green-100 bg-white text-sm font-bold text-[#5C6B5D]">No orders yet.</div>
        ) : (
          orders.map((order) => (
            <div key={order.id} className="rounded-[32px] border border-green-100 bg-white p-6 shadow-sm">
              <div className="flex flex-col gap-5 lg:flex-row lg:items-center lg:justify-between">
                <div>
                  <p className="text-xs font-black uppercase tracking-[2px] text-[#5C6B5D]">Order #{order.id}</p>
                  <h3 className="mt-1 text-xl font-black text-[#1E2A1F]">{order.fullName}</h3>
                  <p className="mt-1 text-sm text-[#5C6B5D]">{formatDate(order.date)}</p>
                </div>
                <div className="lg:text-right">
                  <p className="text-3xl font-black text-[#2F6B3B]">₱{formatMoney(order.total_amount)}</p>
                  <span className={`mt-2 inline-flex rounded-full px-3 py-1 text-xs font-black ${statusColors[order.status] || "bg-gray-100 text-gray-600"}`}>{order.status}</span>
                </div>
              </div>

              <div className="mt-6 grid gap-4 md:grid-cols-2">
                {order.items.map((item) => (
                  <div key={`${order.id}-${item.productId}`} className="rounded-2xl bg-[#F7FBF6] p-4">
                    <p className="font-black text-[#1E2A1F]">{item.productName}</p>
                    <p className="mt-1 text-sm text-[#5C6B5D]">{item.quantity} × ₱{item.price}</p>
                    <p className="mt-2 font-black text-[#2F6B3B]">₱{item.subtotal}</p>
                  </div>
                ))}
              </div>
            </div>
          ))
        )}
      </div>
    </div>
  );

  const renderAbout = () => (
    <div className="mx-auto max-w-6xl px-4 py-20 sm:px-6 lg:px-8">
      <div className="overflow-hidden rounded-[40px] border border-green-100 bg-white shadow-xl shadow-green-900/5 ring-1 ring-black/5">
        <div className="grid lg:grid-cols-[0.8fr_1.2fr]">
          <div className="relative flex min-h-[340px] items-center justify-center overflow-hidden bg-gradient-to-br from-[#EAF7EC] via-white to-[#F7FBF6] p-10">
            <div className="absolute -left-20 -top-20 h-56 w-56 rounded-full bg-[#5DBB63]/20 blur-3xl" />
            <div className="absolute -bottom-24 -right-16 h-64 w-64 rounded-full bg-[#2F6B3B]/15 blur-3xl" />
            <div className="relative flex h-56 w-56 items-center justify-center rounded-[42px] border border-white/80 bg-white/80 p-8 shadow-[0_24px_70px_rgba(47,107,59,0.18)] backdrop-blur-xl sm:h-64 sm:w-64">
              <img src="/green.png" alt="GreenGuard AI official logo" className="h-full w-full object-contain" />
            </div>
          </div>

          <div className="p-8 sm:p-10 md:p-14">
            <p className="text-sm font-black uppercase tracking-[3px] text-[#2F6B3B]">About GreenGuard AI</p>
            <h2 className="mt-4 text-4xl font-black tracking-tight text-[#1E2A1F] md:text-6xl">Smart farming meets local commerce.</h2>
            <p className="mt-6 text-lg leading-8 text-[#5C6B5D]">GreenGuard AI is an AI and IoT-integrated smart farming platform designed for lettuce disease detection, farmer monitoring, and a connected local marketplace.</p>
            <p className="mt-4 text-lg leading-8 text-[#5C6B5D]">The current web system supports buyer marketplace access, farmer selling tools, health logs, live weather context, and order management.</p>
            <div className="mt-8 grid gap-3 sm:grid-cols-3">
              {["AI Disease Detection", "Farmer Monitoring", "Local Marketplace"].map((item) => (
                <div key={item} className="rounded-2xl border border-green-100 bg-[#F7FBF6] px-4 py-3 text-sm font-black text-[#2F6B3B]">{item}</div>
              ))}
            </div>
          </div>
        </div>
      </div>
    </div>
  );

  // ==================== MAIN RETURN ====================
  return (
    <main className="min-h-screen bg-[#F5FAF4] text-[#1E2A1F]">
      {/* FIXED NOTIFICATION - ALWAYS VISIBLE */}
      {message && (
        <div className="fixed left-1/2 top-20 z-[999] -translate-x-1/2 flex items-center gap-3 rounded-2xl bg-[#2F6B3B] px-8 py-4 text-sm font-black text-white shadow-[0_20px_60px_rgba(47,107,59,0.5)] ring-1 ring-white/30">
          <div className="flex h-7 w-7 items-center justify-center rounded-full bg-white/25 text-base">✓</div>
          <span className="font-black">{message}</span>
        </div>
      )}

      <header className="fixed left-0 right-0 top-0 z-50 border-b border-black/5 bg-white/90 shadow-sm shadow-green-900/5 backdrop-blur-xl">
        <div className="mx-auto flex h-20 max-w-7xl items-center justify-between gap-3 px-4 sm:px-6 lg:px-8">
          <button onClick={() => setCurrentView("home")} className="group flex min-w-0 items-center gap-4">
            {/* VERY ZOOMED LOGO */}
            <div className="relative flex h-16 w-16 shrink-0 items-center justify-center rounded-3xl border border-white/70 bg-white p-2 shadow-lg ring-1 ring-white/60 transition-all duration-500 group-hover:scale-110 group-hover:shadow-xl">
              <img src="/green.png" alt="GreenGuard AI" className="h-full w-full object-contain transition-transform duration-500 group-hover:scale-105" />
            </div>
            <div className="min-w-0 text-left">
              <p className="truncate text-xl font-black text-[#2F6B3B] sm:text-2xl">GreenGuard AI</p>
              <p className="hidden text-[10px] font-black uppercase tracking-[2px] text-[#5C6B5D] sm:block">Marketplace</p>
            </div>
          </button>

          <nav className="hidden items-center gap-7 md:flex">
            {[
              { label: "Home", view: "home" as const },
              { label: "Shop", view: "shop" as const },
              ...(!isFarmer ? [{ label: "Checkout", view: "checkout" as const }, { label: "Orders", view: "orders" as const }] : []),
              { label: "About", view: "about" as const },
            ].map((item) => (
              <button key={item.view} onClick={() => setCurrentView(item.view)} className={`group relative py-2 text-sm font-bold transition-colors duration-300 ${currentView === item.view ? "text-[#2F6B3B]" : "text-[#5C6B5D] hover:text-[#2F6B3B]"}`}>
                {item.label}
                <span className={`absolute inset-x-0 -bottom-0.5 h-0.5 origin-left rounded-full bg-[#2F6B3B] transition-all duration-300 ${currentView === item.view ? "scale-x-100" : "scale-x-0 group-hover:scale-x-100"}`} />
              </button>
            ))}
          </nav>

          <div className="flex shrink-0 items-center gap-2 sm:gap-3">
            {!isFarmer && (
              <button onClick={() => setCurrentView("checkout")} className={`group flex h-11 items-center gap-2.5 rounded-full border px-4 text-sm font-black transition-all duration-300 ${currentView === "checkout" ? "border-[#2F6B3B] bg-[#2F6B3B] text-white" : "border-green-100 bg-white text-[#2F6B3B] hover:-translate-y-0.5 hover:bg-green-50"}`}>
                <svg className="h-4 w-4" fill="none" viewBox="0 0 24 24" stroke="currentColor"><path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2.25} d="M3 3h2l.4 2M7 13h10l4-8H5.4M7 13 5.4 5M7 13l-2.3 2.3c-.63.63-.18 1.7.7 1.7H17m0 0a2 2 0 1 0 0 4 2 2 0 0 0 0-4Zm-10 0a2 2 0 1 0 0 4 2 2 0 0 0 0-4Z" /></svg>
                <span>Cart</span>
                <span className={`flex h-6 min-w-[22px] items-center justify-center rounded-full px-1.5 text-[10px] font-black ${currentView === "checkout" ? "bg-white/20 text-white" : "bg-[#2F6B3B] text-white"}`}>{cartCount}</span>
              </button>
            )}

            {account ? (
              <div className="flex items-center gap-2">
                <div className="hidden rounded-full border border-green-100 bg-white px-4 py-2 lg:block">
                  <p className="text-xs font-black text-[#1E2A1F]">{account.name}</p>
                  <p className="text-[9px] font-black uppercase tracking-[1.5px] text-[#2F6B3B]">{account.role}</p>
                </div>
                <button onClick={handleLogout} className="flex h-11 w-11 items-center justify-center rounded-full border border-gray-100 bg-white text-sm shadow-sm transition hover:border-red-100 hover:bg-red-50">↪</button>
              </div>
            ) : (
              <button onClick={() => { setAuthMode("login"); setAuthOpen(true); }} className="rounded-full bg-[#1E2A1F] px-5 py-2.5 text-sm font-black text-white shadow-md transition hover:-translate-y-0.5 hover:bg-[#2F6B3B]">Login</button>
            )}
          </div>
        </div>
      </header>

      {/* IMPROVED AUTH MODAL WITH VERY ZOOMED LOGO */}
      {authOpen && (
        <div className="fixed inset-0 z-[200] flex items-center justify-center bg-[#07100B]/70 p-4 backdrop-blur-md">
          <div className="relative w-full max-w-md overflow-hidden rounded-3xl border border-white/70 bg-white shadow-[0_30px_100px_rgba(7,16,11,0.4)]">
            <div className="p-8">
              <div className="flex items-center justify-between">
                <div className="flex items-center gap-4">
                  <div className="flex h-20 w-20 items-center justify-center rounded-3xl border border-white/70 bg-white p-3 shadow-lg ring-1 ring-white/60 transition-all duration-500 hover:scale-105">
                    <img src="/green.png" alt="GreenGuard AI" className="h-full w-full object-contain" />
                  </div>
                  <div>
                    <p className="text-xs font-black uppercase tracking-[2px] text-[#2F6B3B]">GreenGuard AI</p>
                    <h2 className="text-3xl font-black tracking-tight text-[#1E2A1F]">{authMode === "login" ? "Welcome back" : authMode === "register" ? "Create account" : "Reset password"}</h2>
                  </div>
                </div>
                <button onClick={() => setAuthOpen(false)} className="text-3xl leading-none text-gray-400 hover:text-red-500">×</button>
              </div>

              <form onSubmit={handleAuthSubmit} className="mt-8 space-y-5">
                {authMode === "register" && <input value={authForm.name} onChange={(e) => setAuthForm({ ...authForm, name: e.target.value })} placeholder="Full Name" className="w-full rounded-2xl border border-green-100 bg-[#F7FBF6] px-6 py-4 text-sm font-bold outline-none focus:border-[#2F6B3B] focus:bg-white" />}
                <input type="email" value={authForm.email} onChange={(e) => setAuthForm({ ...authForm, email: e.target.value })} placeholder="Email" className="w-full rounded-2xl border border-green-100 bg-[#F7FBF6] px-6 py-4 text-sm font-bold outline-none focus:border-[#2F6B3B] focus:bg-white" />
                {authMode !== "reset" && <input type="password" value={authForm.password} onChange={(e) => setAuthForm({ ...authForm, password: e.target.value })} placeholder="Password" className="w-full rounded-2xl border border-green-100 bg-[#F7FBF6] px-6 py-4 text-sm font-bold outline-none focus:border-[#2F6B3B] focus:bg-white" />}
                <button type="submit" disabled={authLoading} className="mt-3 w-full rounded-full bg-[#2F6B3B] py-4 text-sm font-black text-white shadow-lg transition hover:-translate-y-0.5 hover:bg-[#1E2A1F] disabled:opacity-60">
                  {authLoading ? "Please wait..." : authMode === "login" ? "Login" : authMode === "register" ? "Create Account" : "Send Reset Link"}
                </button>
              </form>

              <div className="mt-6 flex justify-center gap-4 text-sm font-bold text-[#2F6B3B]">
                {authMode !== "login" && <button onClick={() => setAuthMode("login")} className="hover:text-[#1E2A1F] hover:underline">Login</button>}
                {authMode !== "register" && <button onClick={() => setAuthMode("register")} className="hover:text-[#1E2A1F] hover:underline">Register</button>}
                {authMode !== "reset" && <button onClick={() => setAuthMode("reset")} className="hover:text-[#1E2A1F] hover:underline">Forgot Password</button>}
              </div>
            </div>
          </div>
        </div>
      )}

      {selectedProduct && (
        <div className="fixed inset-0 z-[180] flex items-center justify-center bg-black/50 p-4 backdrop-blur-sm">
          <div className="w-full max-w-2xl overflow-hidden rounded-[32px] bg-white shadow-2xl">
            <div className="h-72 bg-cover bg-center" style={{ backgroundImage: `url(${selectedProduct.image})` }} />
            <div className="p-8">
              <div className="flex items-start justify-between gap-5">
                <div>
                  <p className="text-xs font-black uppercase tracking-[2px] text-[#2F6B3B]">{selectedProduct.category}</p>
                  <h2 className="mt-2 text-3xl font-black text-[#1E2A1F]">{selectedProduct.name}</h2>
                  <p className="mt-2 text-sm font-bold text-[#5C6B5D]">Farmer: {selectedProduct.farmer}</p>
                </div>
                <button onClick={() => setSelectedProduct(null)} className="flex h-10 w-10 items-center justify-center rounded-full bg-gray-100 font-black">×</button>
              </div>
              <p className="mt-6 leading-7 text-[#5C6B5D]">{selectedProduct.freshnessInfo}</p>
              <div className="mt-8 flex items-center justify-between">
                <p className="text-4xl font-black text-[#2F6B3B]">₱{selectedProduct.price}</p>
                {!isFarmer && <button onClick={() => { addToCart(selectedProduct); setSelectedProduct(null); }} disabled={selectedProduct.stock === 0} className="rounded-full bg-[#2F6B3B] px-7 py-3.5 text-sm font-black text-white disabled:opacity-50">Add to Cart</button>}
              </div>
            </div>
          </div>
        </div>
      )}

      <div key={currentView} className="pb-20 pt-24 animate-in fade-in duration-300">
        {renderFarmerTools()}
        {currentView === "home" && renderHome()}
        {currentView === "shop" && renderShop()}
        {currentView === "checkout" && renderCheckout()}
        {currentView === "orders" && renderOrders()}
        {currentView === "about" && renderAbout()}
      </div>

      <footer className="border-t border-black/5 bg-white pb-8 pt-16">
        <div className="mx-auto grid max-w-7xl gap-10 px-4 sm:px-6 md:grid-cols-4 lg:px-8">
          <div>
            <div className="flex items-center gap-4">
              <div className="flex h-14 w-14 items-center justify-center rounded-3xl border border-white/70 bg-white p-2 shadow-sm">
                <img src="/green.png" alt="GreenGuard AI official logo" className="h-full w-full object-contain" />
              </div>
              <h3 className="text-2xl font-black text-[#2F6B3B]">GreenGuard AI</h3>
            </div>
            <p className="mt-4 text-sm leading-relaxed text-[#5C6B5D]">Premium lettuce marketplace powered by AI.</p>
          </div>
        </div>
        <div className="mx-auto mt-16 max-w-7xl px-4 text-center text-sm text-[#5C6B5D] sm:px-6 lg:px-8">© 2026 GreenGuard AI Capstone Project. All rights reserved.</div>
      </footer>
    </main>
  );
}

// ==================== HELPER COMPONENTS ====================
function WeatherMetric({ label, value }: { label: string; value: string; }) {
  return (
    <div className="rounded-2xl bg-[#F7FBF6] p-4">
      <p className="text-[10px] font-black uppercase tracking-[2px] text-[#5C6B5D]">{label}</p>
      <p className="mt-1 text-sm font-black text-[#1E2A1F]">{value}</p>
    </div>
  );
}

function FarmerStat({ label, value }: { label: string; value: number; }) {
  return (
    <div className="rounded-2xl border border-green-100 bg-white p-4 shadow-sm">
      <p className="text-3xl font-black text-[#2F6B3B]">{value}</p>
      <p className="mt-1 text-xs font-black uppercase tracking-[2px] text-[#5C6B5D]">{label}</p>
    </div>
  );
}

function FarmerSummaryCard({ label, value }: { label: string; value: string; }) {
  return (
    <div className="rounded-[24px] border border-green-100 bg-[#F7FBF6] p-5">
      <p className="text-2xl font-black text-[#2F6B3B]">{value}</p>
      <p className="mt-1 text-xs font-black uppercase tracking-[2px] text-[#5C6B5D]">{label}</p>
    </div>
  );
}

function StatusPill({ text }: { text: string; }) {
  return (
    <span className={`rounded-full border px-3 py-1 text-[11px] font-black uppercase tracking-[1px] ${statusTone(text)}`}>{text}</span>
  );
}