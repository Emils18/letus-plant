export type Product = {
  id: number;
  name: string;
  farmer: string;
  category: string;
  price: number;
  stock: number;
  badge: string;
  image: string;
  freshnessInfo: string;
  createdAt: string;
};

export type OrderStatus =
  | "Pending"
  | "Confirmed"
  | "Preparing"
  | "Shipped"
  | "Delivered";

export type OrderItem = {
  productId: number;
  productName: string;
  price: number;
  quantity: number;
  subtotal: number;
};

export type Order = {
  id: string;
  date: string;
  fullName: string;
  email: string;
  phone: string;
  address: string;
  city: string;
  postalCode: string;
  paymentMethod: string;
  items: OrderItem[];
  total: number;
  status: OrderStatus;
};

export type BuyerUser = {
  id: number;
  name: string;
  email: string;
  password: string;
};

export const products: Product[] = [
  {
    id: 1,
    name: "Fresh Green Lettuce",
    farmer: "Farm Verde",
    category: "Fresh Lettuce",
    price: 85,
    stock: 24,
    badge: "Fresh Today",
    image:
      "https://images.unsplash.com/photo-1540420773420-3366772f4999?q=80&w=1200&auto=format&fit=crop",
    freshnessInfo: "Harvested within the last 24 hours",
    createdAt: "2026-04-07T09:00:00Z",
  },
  {
    id: 2,
    name: "Premium Romaine Lettuce",
    farmer: "Highland Harvest",
    category: "Premium Lettuce",
    price: 120,
    stock: 12,
    badge: "Premium",
    image:
      "https://images.unsplash.com/photo-1622206151226-18ca2c9ab4a1?q=80&w=1200&auto=format&fit=crop",
    freshnessInfo: "Premium-grade romaine, crisp and clean",
    createdAt: "2026-04-06T08:00:00Z",
  },
  {
    id: 3,
    name: "Lettuce Seed Pack",
    farmer: "SeedNest",
    category: "Seeds",
    price: 60,
    stock: 50,
    badge: "Best Seller",
    image:
      "https://images.unsplash.com/photo-1464226184884-fa280b87c399?q=80&w=1200&auto=format&fit=crop",
    freshnessInfo: "Packed for high germination quality",
    createdAt: "2026-04-05T08:00:00Z",
  },
  {
    id: 4,
    name: "Healthy Seedlings",
    farmer: "GreenSprout Farm",
    category: "Seedlings",
    price: 95,
    stock: 18,
    badge: "Verified",
    image:
      "https://images.unsplash.com/photo-1416879595882-3373a0480b5b?q=80&w=1200&auto=format&fit=crop",
    freshnessInfo: "Young healthy lettuce seedlings",
    createdAt: "2026-04-04T08:00:00Z",
  },
  {
    id: 5,
    name: "Lettuce Bundle Pack",
    farmer: "Leaf & Co.",
    category: "Bundles",
    price: 150,
    stock: 15,
    badge: "Bundle",
    image:
      "https://images.unsplash.com/photo-1515356956468-873f7ad7b9f8?q=80&w=1200&auto=format&fit=crop",
    freshnessInfo: "Family-size bundle for multiple servings",
    createdAt: "2026-04-03T08:00:00Z",
  },
  {
    id: 6,
    name: "Bulk Lettuce Order",
    farmer: "AgriPrime",
    category: "Bulk Orders",
    price: 420,
    stock: 8,
    badge: "Bulk",
    image:
      "https://images.unsplash.com/photo-1566385101042-1a0aa0c1268c?q=80&w=1200&auto=format&fit=crop",
    freshnessInfo: "Ideal for restaurants and resellers",
    createdAt: "2026-04-02T08:00:00Z",
  },
];

export const buyers: BuyerUser[] = [
  {
    id: 1,
    name: "Sample Buyer",
    email: "buyer@letusplant.com",
    password: "123456",
  },
];

export const initialOrders: Order[] = [
  {
    id: "ORD-1001",
    date: "April 7, 2026",
    fullName: "Sample Buyer",
    email: "buyer@letusplant.com",
    phone: "09123456789",
    address: "Sample Street",
    city: "Cebu City",
    postalCode: "6000",
    paymentMethod: "Cash on Delivery",
    items: [
      {
        productId: 1,
        productName: "Fresh Green Lettuce",
        price: 85,
        quantity: 1,
        subtotal: 85,
      },
    ],
    total: 85,
    status: "Pending",
  },
  {
    id: "ORD-1002",
    date: "April 6, 2026",
    fullName: "Sample Buyer",
    email: "buyer@letusplant.com",
    phone: "09123456789",
    address: "Sample Street",
    city: "Cebu City",
    postalCode: "6000",
    paymentMethod: "GCash",
    items: [
      {
        productId: 5,
        productName: "Lettuce Bundle Pack",
        price: 150,
        quantity: 1,
        subtotal: 150,
      },
    ],
    total: 150,
    status: "Confirmed",
  },
];