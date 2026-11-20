export type UserRole = "buyer" | "farmer" | "admin";

export interface UserAccount {
  id: string;
  email: string;
  password?: string;
  role: UserRole;
  fullName?: string;
}

export interface Product {
  id: number;
  name: string;
  category: string;
  price: number;
  stock: number;
  description: string;
  imageUrl: string | null;
  farmerId: string;
  hidden?: boolean;
}

export interface CartItem extends Product {
  quantity: number;
}

export type DeliveryMethod = "Delivery" | "Pickup";

export interface CheckoutForm {
  fullName: string;
  email: string;
  phone: string;
  deliveryMethod: DeliveryMethod;
  address: string;
  city: string;
  postalCode: string;
}

export type OrderStatus =
  | "Pending"
  | "Confirmed"
  | "Preparing"
  | "Shipped"
  | "Delivered"
  | "Completed"
  | "Cancelled";

export interface OrderRecord {
  id: string;
  userId: string;
  farmerId: string;
  items: { productId: number; productName: string; price: number; quantity: number }[];
  subtotal: number;
  shipping: number;
  totalAmount: number;
  status: OrderStatus;
  paymentStatus: "paid" | "unpaid" | "pending";
  deliveryStatus?: "Pending" | "Received";
  paymentProofUrl?: string | null;
  deliveryProofUrl?: string | null;
}

export interface ChatMessage {
  id: string;
  orderId: string;
  senderId: string;
  senderRole: UserRole;
  body: string;
  createdAt: string;
}

export interface AppNotification {
  id: string;
  userId: string;
  message: string;
  read: boolean;
}

export interface DiagnosticLog {
  id: string;
  userId: string;
  diseaseName: string;
  confidenceScore: number;
  imageUrl: string;
  location: string;
  capturedAt: string;
}

export interface DatasetImage {
  id: string;
  filename: string;
  storagePath: string;
  annotations: { label: string; bbox: [number, number, number, number] }[];
}

// --- Authentication ---

export function isValidEmailFormat(email: string): boolean {
  return /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email.trim());
}

export function loginBuyer(
  users: UserAccount[],
  email: string,
  password: string
): { success: boolean; redirectTo?: string; user?: UserAccount; message?: string } {
  if (!email.trim() || !password) {
    return { success: false, message: "Email and password required." };
  }
  const found = users.find(
    (u) => u.email.toLowerCase() === email.trim().toLowerCase() && u.password === password
  );
  if (!found) {
    return { success: false, message: "Invalid login credentials." };
  }
  return {
    success: true,
    redirectTo: found.role === "admin" ? "/admin" : "/shop",
    user: found,
  };
}

export function registerBuyer(
  users: UserAccount[],
  email: string,
  password: string
): { success: boolean; message: string; user?: UserAccount } {
  if (!email.trim() || !password) {
    return { success: false, message: "Email and password required." };
  }
  if (!isValidEmailFormat(email)) {
    return { success: false, message: "Please enter a valid email address." };
  }
  const exists = users.some((u) => u.email.toLowerCase() === email.trim().toLowerCase());
  if (exists) {
    return { success: false, message: "This email is already registered. Please log in instead." };
  }
  const created: UserAccount = {
    id: `user-${users.length + 1}`,
    email: email.trim().toLowerCase(),
    password,
    role: "buyer",
  };
  users.push(created);
  return { success: true, message: "Registration successful.", user: created };
}

export function requestPasswordReset(
  users: UserAccount[],
  email: string,
  onSendEmail?: (to: string) => void
): { success: boolean; message: string; emailDispatched: boolean } {
  const normalized = email.trim().toLowerCase();
  if (!normalized) {
    return { success: false, message: "Please enter your email first.", emailDispatched: false };
  }
  const exists = users.some((u) => u.email.toLowerCase() === normalized);
  if (exists && onSendEmail) {
    onSendEmail(normalized);
  }
  return {
    success: true,
    message: "Password reset link sent! Check your inbox.",
    emailDispatched: exists,
  };
}

export function completePasswordReset(
  users: UserAccount[],
  email: string,
  newPassword: string
): { success: boolean; message: string } {
  const user = users.find((u) => u.email.toLowerCase() === email.trim().toLowerCase());
  if (!user) return { success: false, message: "User not found." };
  user.password = newPassword;
  return { success: true, message: "Password updated." };
}

export function logoutAdmin(session: { user: UserAccount | null }): {
  sessionCleared: boolean;
  redirectTo: string;
} {
  session.user = null;
  return { sessionCleared: true, redirectTo: "/" };
}

export function canAccessAdminPage(user: UserAccount | null): {
  allowed: boolean;
  status: number;
  redirectTo?: string;
} {
  if (!user || user.role !== "admin") {
    return { allowed: false, status: 307, redirectTo: "/" };
  }
  return { allowed: true, status: 200 };
}

// --- Marketplace ---

export function filterAndSortProducts(
  products: Product[],
  options: {
    search?: string;
    category?: string;
    sortBy?: "Default" | "Price: Low to High" | "Price: High to Low";
  }
): Product[] {
  let data = products.filter((p) => !p.hidden);
  const query = (options.search || "").trim().toLowerCase();
  if (query) {
    data = data.filter((p) => p.name.toLowerCase().includes(query));
  }
  if (options.category && options.category !== "All Categories") {
    data = data.filter((p) => p.category === options.category);
  }
  if (options.sortBy === "Price: Low to High") {
    data.sort((a, b) => a.price - b.price);
  } else if (options.sortBy === "Price: High to Low") {
    data.sort((a, b) => b.price - a.price);
  }
  return data;
}

export function getProductDetails(products: Product[], id: number): Product | null {
  return products.find((p) => p.id === id) ?? null;
}

// --- Product Management ---

export function validateProductDraft(draft: {
  name: string;
  price: number;
  stock: number;
  imageUrl: string | null;
  description?: string;
}): { valid: boolean; message?: string; normalizedDescription: string } {
  if (!draft.name.trim()) {
    return { valid: false, message: "Product name is required.", normalizedDescription: "" };
  }
  if (!draft.imageUrl) {
    return { valid: false, message: "Please select a product image.", normalizedDescription: "" };
  }
  if (!Number.isFinite(draft.price) || draft.price < 1) {
    return { valid: false, message: "Price must be at least 1.", normalizedDescription: "" };
  }
  if (!Number.isFinite(draft.stock) || draft.stock < 1) {
    return { valid: false, message: "Stock must be at least 1.", normalizedDescription: "" };
  }
  const normalizedDescription =
    draft.description?.trim() || "Freshly harvested organic lettuce.";
  return { valid: true, normalizedDescription };
}

export function createProductListing(
  products: Product[],
  draft: {
    name: string;
    category: string;
    price: number;
    stock: number;
    description?: string;
    imageUrl: string | null;
    farmerId: string;
  }
): { success: boolean; message?: string; product?: Product } {
  const check = validateProductDraft(draft);
  if (!check.valid) {
    return { success: false, message: check.message };
  }
  const product: Product = {
    id: products.length ? Math.max(...products.map((p) => p.id)) + 1 : 1,
    name: draft.name.trim(),
    category: draft.category,
    price: draft.price,
    stock: draft.stock,
    description: check.normalizedDescription,
    imageUrl: draft.imageUrl,
    farmerId: draft.farmerId,
    hidden: false,
  };
  products.push(product);
  return { success: true, product };
}

export function getProductPreviewState(draft: {
  name: string;
  price: number;
  stock: number;
  imageUrl: string | null;
}): { hasInvalidValues: boolean; warnings: string[] } {
  const warnings: string[] = [];
  if (!draft.name.trim()) warnings.push("Missing name");
  if (draft.price < 1) warnings.push("Invalid price");
  if (draft.stock < 1) warnings.push("Invalid stock");
  if (!draft.imageUrl) warnings.push("Missing image");
  return { hasInvalidValues: warnings.length > 0, warnings };
}

export function editProductListing(
  products: Product[],
  id: number,
  updates: Partial<Pick<Product, "name" | "category" | "price" | "description">>
): { success: boolean; product?: Product; message?: string } {
  const target = products.find((p) => p.id === id);
  if (!target) return { success: false, message: "Product not found." };
  if (updates.name !== undefined && !updates.name.trim()) {
    return { success: false, message: "Product name is required." };
  }
  if (updates.price !== undefined && updates.price < 1) {
    return { success: false, message: "Price must be at least 1." };
  }
  Object.assign(target, updates);
  return { success: true, product: target };
}

export function updateProductStock(
  products: Product[],
  id: number,
  newStock: number
): { success: boolean; product?: Product; outOfStock?: boolean; message?: string } {
  const target = products.find((p) => p.id === id);
  if (!target) return { success: false, message: "Product not found." };
  if (!Number.isFinite(newStock) || newStock < 0) {
    return { success: false, message: "Stock cannot be negative." };
  }
  target.stock = newStock;
  target.hidden = newStock === 0;
  return { success: true, product: target, outOfStock: newStock === 0 };
}

export function deleteProductListing(
  products: Product[],
  id: number,
  confirmed: boolean
): { success: boolean; message?: string } {
  if (!confirmed) return { success: false, message: "Deletion cancelled." };
  const idx = products.findIndex((p) => p.id === id);
  if (idx === -1) return { success: false, message: "Product not found." };
  products.splice(idx, 1);
  return { success: true };
}

// --- Shopping Cart ---

export function addItemToCart(
  cart: CartItem[],
  product: Product
): { cart: CartItem[]; added: boolean; message?: string } {
  if (product.stock <= 0) {
    return { cart, added: false, message: "Product is out of stock." };
  }
  const existing = cart.find((item) => item.id === product.id);
  if (existing) {
    const nextQty = Math.min(existing.quantity + 1, product.stock);
    return {
      cart: cart.map((item) => (item.id === product.id ? { ...item, quantity: nextQty } : item)),
      added: nextQty > existing.quantity,
      message: nextQty === existing.quantity ? "Maximum available stock reached." : undefined,
    };
  }
  return { cart: [...cart, { ...product, quantity: 1 }], added: true };
}

export function updateCartItemQuantity(
  cart: CartItem[],
  productId: number,
  delta: number
): CartItem[] {
  return cart
    .map((item) => {
      if (item.id !== productId) return item;
      const next = Math.max(0, Math.min(item.quantity + delta, item.stock));
      return { ...item, quantity: next };
    })
    .filter((item) => item.quantity > 0);
}

export function calculateCartTotals(
  cart: CartItem[],
  deliveryMethod: DeliveryMethod
): { subtotal: number; shipping: number; total: number; canCheckout: boolean } {
  const subtotal = cart.reduce((sum, item) => sum + item.price * item.quantity, 0);
  const shipping = deliveryMethod === "Delivery" && cart.length > 0 ? 50 : 0;
  return {
    subtotal,
    shipping,
    total: subtotal + shipping,
    canCheckout: cart.length > 0,
  };
}

export function persistCart(
  storage: Map<string, string>,
  cart: CartItem[]
): void {
  storage.set("greenguard_cart", JSON.stringify(cart));
}

export function restoreCart(storage: Map<string, string>): CartItem[] {
  const raw = storage.get("greenguard_cart");
  if (!raw) return [];
  return JSON.parse(raw) as CartItem[];
}

export function getInitialCheckoutForm(): CheckoutForm {
  return {
    fullName: "",
    email: "",
    phone: "",
    deliveryMethod: "Delivery",
    address: "",
    city: "",
    postalCode: "",
  };
}

// --- Checkout & Orders ---

export function canOpenCheckoutView(account: UserAccount | null): {
  allowed: boolean;
  redirectToAuth: boolean;
  message?: string;
} {
  if (!account) {
    return {
      allowed: false,
      redirectToAuth: true,
      message: "You must be logged in to proceed to checkout.",
    };
  }
  return { allowed: true, redirectToAuth: false };
}

export function validateCheckoutSubmission(
  account: UserAccount | null,
  cart: CartItem[],
  form: CheckoutForm
): { valid: boolean; message?: string } {
  if (!account) {
    return { valid: false, message: "You must be logged in to place an order." };
  }
  if (cart.length === 0) {
    return { valid: false, message: "Your cart is empty" };
  }
  if (!form.fullName.trim() || !form.phone.trim() || !form.email.trim()) {
    return { valid: false, message: "Please fill in your contact details." };
  }
  if (
    form.deliveryMethod === "Delivery" &&
    (!form.address.trim() || !form.city.trim() || !form.postalCode.trim())
  ) {
    return { valid: false, message: "Please provide your full delivery address." };
  }
  return { valid: true };
}

export function createOrder(
  orders: OrderRecord[],
  account: UserAccount | null,
  cart: CartItem[],
  form: CheckoutForm
): { success: boolean; order?: OrderRecord; message?: string } {
  const check = validateCheckoutSubmission(account, cart, form);
  if (!check.valid || !account) {
    return { success: false, message: check.message };
  }
  const { subtotal, shipping, total } = calculateCartTotals(cart, form.deliveryMethod);
  const order: OrderRecord = {
    id: `ORD-${orders.length + 1}`,
    userId: account.id,
    farmerId: cart[0].farmerId,
    items: cart.map((i) => ({
      productId: i.id,
      productName: i.name,
      price: i.price,
      quantity: i.quantity,
    })),
    subtotal,
    shipping,
    totalAmount: total,
    status: "Pending",
    paymentStatus: "unpaid",
    deliveryStatus: "Pending",
  };
  orders.push(order);
  return { success: true, order };
}

export function progressOrderStatus(
  order: OrderRecord,
  nextStatus: OrderStatus
): OrderRecord {
  order.status = nextStatus;
  return order;
}

export function cancelBuyerOrder(
  order: OrderRecord,
  buyerId: string
): { success: boolean; message: string } {
  if (order.userId !== buyerId) {
    return { success: false, message: "Unauthorized to cancel this order." };
  }
  if (order.status !== "Pending") {
    return { success: false, message: "Only pending orders can be cancelled." };
  }
  order.status = "Cancelled";
  return { success: true, message: "Order cancelled." };
}

export function confirmBuyerReceipt(order: OrderRecord): OrderRecord {
  order.status = "Completed";
  order.deliveryStatus = "Received";
  order.paymentStatus = "paid";
  return order;
}

// --- Messaging & Notifications ---

export function sendOrderMessage(
  messages: ChatMessage[],
  order: OrderRecord,
  sender: UserAccount,
  body: string
): { success: boolean; message?: ChatMessage; error?: string } {
  if (order.status === "Completed") {
    return { success: false, error: "Chat is read-only after order completion." };
  }
  if (!body.trim()) {
    return { success: false, error: "Message cannot be empty." };
  }
  const msg: ChatMessage = {
    id: `msg-${messages.length + 1}`,
    orderId: order.id,
    senderId: sender.id,
    senderRole: sender.role,
    body: body.trim(),
    createdAt: new Date().toISOString(),
  };
  messages.push(msg);
  return { success: true, message: msg };
}

export function markNotificationRead(
  notifications: AppNotification[],
  id: string
): AppNotification | null {
  const target = notifications.find((n) => n.id === id);
  if (!target) return null;
  target.read = true;
  return target;
}

// --- Dashboard & Admin ---

export function computeDashboardMetrics(orders: OrderRecord[]): {
  totalOrders: number;
  grossSalesPaidOnly: number;
  pendingOrderValue: number;
} {
  const totalOrders = orders.length;
  const grossSalesPaidOnly = orders
    .filter((o) => o.paymentStatus === "paid")
    .reduce((sum, o) => sum + o.totalAmount, 0);
  const pendingOrderValue = orders
    .filter((o) => o.paymentStatus !== "paid" && o.status !== "Cancelled")
    .reduce((sum, o) => sum + o.totalAmount, 0);
  return { totalOrders, grossSalesPaidOnly, pendingOrderValue };
}

export function searchAdminUsers(users: UserAccount[], keyword: string): UserAccount[] {
  const q = keyword.trim().toLowerCase();
  if (!q) return users;
  return users.filter(
    (u) =>
      u.email.toLowerCase().includes(q) ||
      (u.fullName || "").toLowerCase().includes(q) ||
      u.role.toLowerCase().includes(q)
  );
}

export function promoteUserToAdmin(
  actor: UserAccount,
  target: UserAccount,
  confirmed: boolean
): { success: boolean; requiresConfirmation?: boolean; message: string } {
  if (actor.role !== "admin") {
    return { success: false, message: "Admin permission is required." };
  }
  if (!confirmed) {
    return { success: false, requiresConfirmation: true, message: "Role change cancelled." };
  }
  target.role = "admin";
  return { success: true, message: `${target.email} is now an admin.` };
}

// --- AI, IoT, Weather, Logs, Dataset, DB & Reporting ---

export function validateAiImageInput(file: {
  mimeType: string;
  sizeBytes: number;
  corrupted?: boolean;
}): { valid: boolean; message?: string } {
  if (!file.mimeType.startsWith("image/") || file.sizeBytes <= 0) {
    return { valid: false, message: "Choose a valid image under 12 MB." };
  }
  if (file.sizeBytes > 12 * 1024 * 1024) {
    return { valid: false, message: "Choose a valid image under 12 MB." };
  }
  if (file.corrupted) {
    return { valid: false, message: "Image file is corrupted or unreadable." };
  }
  return { valid: true };
}

export function runYoloInferenceMock(imageBufferSize: number): {
  success: boolean;
  displayName: string;
  confidence: number;
} {
  if (imageBufferSize <= 0) {
    throw new Error("Empty image buffer.");
  }
  return {
    success: true,
    displayName: "Downy_Mildew",
    confidence: 0.94,
  };
}

export function formatDetectionResult(raw: {
  displayName: string;
  confidence: number;
}): { label: string; confidencePercent: string } {
  return {
    label: raw.displayName.replaceAll("_", " "),
    confidencePercent: `${(raw.confidence * 100).toFixed(1)}%`,
  };
}

export function generateSummaryReport(
  requester: UserAccount,
  orders: OrderRecord[],
  logs: DiagnosticLog[]
): {
  success: boolean;
  status: number;
  report?: { orderCount: number; revenue: number; scanCount: number };
} {
  if (requester.role !== "admin" && requester.role !== "farmer") {
    return { success: false, status: 403 };
  }
  const revenue = orders
    .filter((o) => o.paymentStatus === "paid")
    .reduce((sum, o) => sum + o.totalAmount, 0);
  return {
    success: true,
    status: 200,
    report: { orderCount: orders.length, revenue, scanCount: logs.length },
  };
}
