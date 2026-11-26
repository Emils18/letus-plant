"use client";

import Link from "next/link";
import { useEffect, useId, useLayoutEffect, useRef, useState, useSyncExternalStore } from "react";
import { supabase } from "@/lib/supabase";

type Order = {
  id: string;
  order_code?: string;
  user_id?: string;
  farmer_id?: string;
  shipping_name?: string;
  status?: string;
  delivery_status?: string;
  created_at?: string;
};
type Message = {
  id: string;
  order_id: string;
  sender_id: string;
  message: string;
  created_at: string;
  read_at?: string | null;
};
type MessagePreview = Pick<Message, "message" | "created_at">;
type Conversation = {
  orderId: string;
  messages: Message[];
  receiptsAvailable: boolean;
  loadError: string;
};

const terminalStatuses = new Set(["delivered", "received", "completed"]);
const twoPanelLayout = "(min-width: 48rem)";

function subscribeToLayout(onChange: () => void) {
  const query = window.matchMedia(twoPanelLayout);
  query.addEventListener("change", onChange);
  return () => query.removeEventListener("change", onChange);
}

function isTwoPanelLayout() {
  return window.matchMedia(twoPanelLayout).matches;
}

function getInitialLayout() {
  return false;
}

function shortOrderReference(order?: Order) {
  if (!order) return "";
  const raw = order.order_code?.trim() || order.id;
  const parts = raw.split(/[-\s]+/).filter(Boolean);
  const last = parts.at(-1) || raw;
  if (!order.order_code && raw.length > 8) return raw.slice(0, 8).toUpperCase();
  return (last.length > 10 ? last.slice(-10) : last).toUpperCase();
}

function readableStatus(value?: string) {
  return value?.trim().replaceAll("_", " ").replace(/\b\w/g, (letter) => letter.toUpperCase()) || "Status unavailable";
}

function orderIsClosed(order?: Order) {
  return terminalStatuses.has(order?.status?.trim().toLowerCase() || "")
    || terminalStatuses.has(order?.delivery_status?.trim().toLowerCase() || "");
}

function orderStatusLabel(order?: Order) {
  const status = order?.status?.trim();
  const deliveryStatus = order?.delivery_status?.trim();
  if (terminalStatuses.has(deliveryStatus?.toLowerCase() || "")) return readableStatus(deliveryStatus);
  if (terminalStatuses.has(status?.toLowerCase() || "")) return readableStatus(status);
  if (deliveryStatus && deliveryStatus.toLowerCase() !== "pending") return readableStatus(deliveryStatus);
  return readableStatus(status);
}

function messageTime(value: string) {
  const date = new Date(value);
  return Number.isNaN(date.getTime()) ? "" : new Intl.DateTimeFormat(undefined, { hour: "numeric", minute: "2-digit" }).format(date);
}

function chronologicalMessages(messages: Message[]) {
  return [...messages].sort((a, b) => {
    const aTime = Date.parse(a.created_at);
    const bTime = Date.parse(b.created_at);
    if (Number.isFinite(aTime) && Number.isFinite(bTime) && aTime !== bTime) return aTime - bTime;
    if (Number.isFinite(aTime) !== Number.isFinite(bTime)) return Number.isFinite(aTime) ? -1 : 1;
    return a.id.localeCompare(b.id);
  });
}

function previewTime(value?: string) {
  if (!value) return "";
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return "";
  return new Intl.DateTimeFormat(undefined, {
    hour: "numeric",
    minute: "2-digit",
  }).format(date);
}

function participantName(order: Order, userId: string, names: Record<string, string>) {
  if (order.user_id === userId) return names[order.farmer_id || ""] || "Farmer";
  return names[order.user_id || ""] || order.shipping_name || "Buyer";
}

export default function MessagesPage() {
  const [userId, setUserId] = useState("");
  const [orders, setOrders] = useState<Order[]>([]);
  const [peerNames, setPeerNames] = useState<Record<string, string>>({});
  const [previews, setPreviews] = useState<Record<string, MessagePreview>>({});
  const [activeOrder, setActiveOrder] = useState("");
  const [conversation, setConversation] = useState<Conversation>();
  const [drafts, setDrafts] = useState<Record<string, string>>({});
  const [loading, setLoading] = useState(true);
  const [sending, setSending] = useState(false);
  const sendingLock = useRef(false);
  const [error, setError] = useState("");
  const [sendError, setSendError] = useState<{ orderId: string; message: string }>();
  const [mobileChatOpen, setMobileChatOpen] = useState(false);
  const [search, setSearch] = useState("");
  const shellRef = useRef<HTMLElement>(null);
  const listRef = useRef<HTMLDivElement>(null);
  const conversationHeadingRef = useRef<HTMLHeadingElement>(null);
  const backRef = useRef<HTMLButtonElement>(null);
  const keepAtBottom = useRef(true);
  const scrolledOrder = useRef("");
  const channelId = useId();
  const subscriptionNumber = useRef(0);
  const refreshChat = useRef<{ orderId: string; load: () => Promise<void> }>(null);
  const desktop = useSyncExternalStore(subscribeToLayout, isTwoPanelLayout, getInitialLayout);
  const visibleOrder = desktop || mobileChatOpen ? activeOrder : "";
  const thread = conversation?.orderId === visibleOrder ? conversation : undefined;
  const draft = drafts[activeOrder] || "";

  useEffect(() => {
    const shell = shellRef.current;
    const viewport = window.visualViewport;
    if (!shell || !viewport) return;
    const resize = () => {
      if (viewport.scale === 1) shell.style.setProperty("--chat-viewport-height", `${viewport.height}px`);
      else shell.style.removeProperty("--chat-viewport-height");
    };
    resize();
    viewport.addEventListener("resize", resize);
    return () => viewport.removeEventListener("resize", resize);
  }, []);

  useLayoutEffect(() => {
    const list = listRef.current;
    if (!list || !thread) return;
    if (keepAtBottom.current || scrolledOrder.current !== visibleOrder) {
      list.scrollTop = list.scrollHeight;
      keepAtBottom.current = true;
    }
    scrolledOrder.current = visibleOrder;
  }, [thread, visibleOrder]);

  useEffect(() => {
    let alive = true;
    async function start() {
      const { data: { user } } = await supabase.auth.getUser();
      if (!alive) return;
      if (!user) { setError("Please sign in to message a farmer or buyer."); setLoading(false); return; }
      setUserId(user.id);
      const { data, error: orderError } = await supabase.from("orders")
        .select("id, order_code, user_id, farmer_id, shipping_name, status, delivery_status, created_at")
        .or(`user_id.eq.${user.id},farmer_id.eq.${user.id}`)
        .order("created_at", { ascending: false });
      if (!alive) return;
      if (orderError) {
        const details = orderError.message?.trim();
        setError(details
          ? `Could not load your order chats: ${details}`
          : "Could not load your order chats. Check your connection and retry.");
        setLoading(false);
        return;
      }
      const available = (data || []) as Order[];
      setOrders(available);

      // A missing or unreadable messages table must not prevent the order chat list from loading.
      void Promise.all(available.map(async (order) => {
        const { data: latest } = await supabase.from("order_messages")
          .select("message, created_at")
          .eq("order_id", order.id)
          .order("created_at", { ascending: false })
          .limit(1)
          .maybeSingle();
        return latest ? [order.id, latest as MessagePreview] as const : null;
      })).then((latestMessages) => {
        if (alive) {
          setPreviews(Object.fromEntries(latestMessages.filter((entry): entry is NonNullable<typeof entry> => entry !== null)));
        }
      }).catch(() => undefined);

      const counterpartIds = [...new Set(available
        .map((order) => order.user_id === user.id ? order.farmer_id : order.user_id)
        .filter((id): id is string => Boolean(id)))];
      if (counterpartIds.length) {
        const { data: profiles } = await supabase.from("users")
          .select("id, full_name")
          .in("id", counterpartIds);
        if (alive && profiles) {
          setPeerNames(Object.fromEntries(profiles
            .filter((profile) => profile.full_name?.trim())
            .map((profile) => [profile.id, profile.full_name.trim()])));
        }
      }

      const farmerIds = [...new Set(available
        .map((order) => order.farmer_id)
        .filter((id): id is string => Boolean(id)))];
      if (farmerIds.length) {
        const { data: products } = await supabase.from("products")
          .select("farmer_id, farmer_name, farmer")
          .in("farmer_id", farmerIds);
        if (alive && products?.length) {
          setPeerNames((previous) => {
            const next = { ...previous };
            for (const product of products) {
              const farmerName = product.farmer_name?.trim() || product.farmer?.trim();
              if (product.farmer_id && farmerName && !next[product.farmer_id]) {
                next[product.farmer_id] = farmerName;
              }
            }
            return next;
          });
        }
      }

      if (!alive) return;
      const requestedOrder = new URLSearchParams(window.location.search).get("orderId") || "";
      const requested = available.find((order) => order.id === requestedOrder);
      setActiveOrder(requested?.id || available[0]?.id || "");
      setMobileChatOpen(Boolean(requested));
      setLoading(false);
    }
    void start();
    return () => { alive = false; };
  }, []);

  useEffect(() => {
    if (!visibleOrder || !userId) return;
    let active = true;
    let requestNumber = 0;

    async function loadMessages() {
      const request = ++requestNumber;
      const primary = await supabase.from("order_messages")
        .select("id, order_id, sender_id, message, created_at, read_at")
        .eq("order_id", visibleOrder)
        .order("created_at", { ascending: true })
        .order("id", { ascending: true });
      if (!active || request !== requestNumber) return;

      let data: Message[] | null = primary.data;
      let loadError = primary.error;
      let receiptsAvailable = true;
      if (loadError && (loadError.code === "42703" || loadError.message.toLowerCase().includes("read_at"))) {
        receiptsAvailable = false;
        const fallback = await supabase.from("order_messages")
          .select("id, order_id, sender_id, message, created_at")
          .eq("order_id", visibleOrder)
          .order("created_at", { ascending: true })
          .order("id", { ascending: true });
        if (!active || request !== requestNumber) return;
        data = fallback.data;
        loadError = fallback.error;
      }

      if (loadError) {
        const details = loadError.message?.trim();
        const message = loadError.code === "PGRST205"
          ? "The order_messages table is unavailable. Apply the existing messaging migration, then retry."
          : loadError.code === "42501" || details?.toLowerCase().includes("permission")
          ? "Supabase denied access to this chat. Check the existing order participant policies."
          : details
          ? `Could not load this chat: ${details}`
          : "Could not load this chat. Check your connection and retry.";
        setConversation((previous) => ({
          orderId: visibleOrder,
          messages: previous?.orderId === visibleOrder ? previous.messages : [],
          receiptsAvailable,
          loadError: message,
        }));
        return;
      }

      const messages = chronologicalMessages(data || []);
      setConversation({ orderId: visibleOrder, messages, receiptsAvailable, loadError: "" });
      const latest = messages.at(-1);
      if (latest) setPreviews((previous) => ({ ...previous, [visibleOrder]: latest }));
      if (receiptsAvailable && messages.some((message) => message.sender_id !== userId && !message.read_at)) {
        await supabase.from("order_messages")
          .update({ read_at: new Date().toISOString() })
          .eq("order_id", visibleOrder)
          .neq("sender_id", userId)
          .is("read_at", null);
      }
    }

    refreshChat.current = { orderId: visibleOrder, load: loadMessages };
    void loadMessages();
    const channel = supabase.channel(`web-order-chat-${visibleOrder}-${channelId}-${++subscriptionNumber.current}`)
      .on("postgres_changes", { event: "*", schema: "public", table: "order_messages", filter: `order_id=eq.${visibleOrder}` }, () => void loadMessages())
      .subscribe((status) => {
        if (active && status === "SUBSCRIBED") void loadMessages();
      });
    return () => {
      active = false;
      refreshChat.current = null;
      void supabase.removeChannel(channel);
    };
  }, [visibleOrder, userId, channelId]);

  useEffect(() => {
  if (!activeOrder || !userId) return;

  let mounted = true;

  const refreshOrderStatus = async () => {
    const { data, error } = await supabase
      .from("orders")
      .select("status, delivery_status")
      .eq("id", activeOrder)
      .maybeSingle();

    if (!mounted || error || !data) return;

    setOrders((previous) =>
      previous.map((order) =>
        order.id === activeOrder
          ? {
              ...order,
              status: data.status,
              delivery_status: data.delivery_status,
            }
          : order
      )
    );
  };

  void refreshOrderStatus();

  const channel = supabase
    .channel(`web-order-status-${activeOrder}`)
    .on(
      "postgres_changes",
      {
        event: "UPDATE",
        schema: "public",
        table: "orders",
        filter: `id=eq.${activeOrder}`,
      },
      () => void refreshOrderStatus()
    )
    .subscribe();

  // Fallback if Realtime events are unavailable.
  const timer = window.setInterval(
    () => void refreshOrderStatus(),
    12000
  );

  return () => {
    mounted = false;
    window.clearInterval(timer);
    void supabase.removeChannel(channel);
  };
}, [activeOrder, userId]);

  async function sendMessage(event: React.FormEvent<HTMLFormElement>) {
  event.preventDefault();

  const message = draft.trim();

  if (
    !message ||
    !activeOrder ||
    sendingLock.current ||
    !userId ||
    isClosed ||
    !thread ||
    thread.loadError
  ) {
    return;
  }

  const orderId = activeOrder;

  sendingLock.current = true;
  setSending(true);
  setSendError(undefined);

  try {
    // Check the latest order status before sending.
    const { data: order, error: orderError } = await supabase
      .from("orders")
      .select("status, delivery_status")
      .eq("id", orderId)
      .maybeSingle();

    if (orderError || !order) {
      throw new Error("Could not verify the order status.");
    }

    if (orderIsClosed({ id: orderId, ...order })) {
      setOrders((previous) =>
        previous.map((item) =>
          item.id === orderId
            ? { ...item, ...order }
            : item
        )
      );

      throw new Error(
        "This order is complete. You can no longer send messages."
      );
    }

    const { error: insertError } = await supabase
      .from("order_messages")
      .insert({
        order_id: orderId,
        sender_id: userId,
        message,
      });

    if (insertError) {
      throw new Error(
        `Message could not be sent: ${insertError.message}`
      );
    }

    setDrafts((previous) => ({
      ...previous,
      [orderId]: "",
    }));

    if (refreshChat.current?.orderId === orderId) {
      keepAtBottom.current = true;
      await refreshChat.current.load();
    }
  } catch (error) {
    setSendError({
      orderId,
      message:
        error instanceof Error
          ? error.message
          : "Message not sent. Please try again.",
    });
  } finally {
    sendingLock.current = false;
    setSending(false);
  }
}

  const current = orders.find((order) => order.id === activeOrder);
  const otherName = current ? participantName(current, userId, peerNames) : "Choose an order";
  const isClosed = orderIsClosed(current);
  const messages = thread?.messages || [];
  const lastOutgoingId = messages.findLast((item) => item.sender_id === userId)?.id;
  const searchTerm = search.trim().toLowerCase();
  const filteredOrders = orders.filter((order) => (
    `${participantName(order, userId, peerNames)} Order #${shortOrderReference(order)} ${order.order_code || ""} ${orderStatusLabel(order)}`
      .toLowerCase().includes(searchTerm)
  ));

  function openConversation(orderId: string) {
    setActiveOrder(orderId);
    setMobileChatOpen(true);
    if (!desktop) requestAnimationFrame(() => backRef.current?.focus({ preventScroll: true }));
  }

  function showConversations() {
    setMobileChatOpen(false);
    requestAnimationFrame(() => conversationHeadingRef.current?.focus({ preventScroll: true }));
  }

  return (
    <main ref={shellRef} className="flex h-[var(--chat-viewport-height,100dvh)] min-w-0 flex-col overflow-hidden bg-[#F3F7F3] px-3 pt-3 pb-[max(.75rem,env(safe-area-inset-bottom))] text-[#1E2A1F] sm:px-6 sm:py-5">
      <div className="mx-auto flex min-h-0 w-full max-w-6xl flex-1 flex-col">
        <div className="mb-3 flex shrink-0 items-center justify-between gap-2 sm:mb-5 sm:gap-4">
          <div className="min-w-0">
            <p className="text-[11px] font-black uppercase tracking-wider text-[#2F6B3B] sm:text-sm">GreenGuard marketplace</p>
            <h1 className="text-2xl leading-tight font-black sm:mt-1 sm:text-3xl">Messages</h1>
          </div>
          <Link href="/" className="flex min-h-11 shrink-0 items-center rounded-full border border-green-200 bg-white px-4 text-sm font-bold text-[#2F6B3B] hover:bg-green-50 focus-visible:outline-2 focus-visible:outline-[#2F6B3B] sm:px-5 sm:text-base">Back to store</Link>
        </div>

        {error && <div role="alert" className="mb-3 flex shrink-0 flex-wrap items-center gap-3 rounded-2xl bg-amber-50 p-3 text-sm font-semibold text-amber-900 sm:p-4">
          <span className="flex-1">{error}</span>
          {userId && <button type="button" onClick={() => window.location.reload()} className="min-h-11 rounded-lg px-3 font-bold underline focus-visible:outline-2">Retry</button>}
        </div>}
        {loading ? (
          <div role="status" className="rounded-3xl bg-white p-8">Loading conversationsΓÇª</div>
        ) : !userId ? (
          <div className="rounded-3xl bg-white p-8">
            <p>Sign in to open your order conversations.</p>
            <Link className="mt-4 inline-block rounded-full bg-[#2F6B3B] px-6 py-3 font-bold text-white" href="/">Sign in</Link>
          </div>
        ) : (
          <div className="grid min-h-0 flex-1 grid-cols-[minmax(0,1fr)] grid-rows-[minmax(0,1fr)] overflow-hidden rounded-2xl border border-green-100 bg-white shadow-lg sm:rounded-3xl md:grid-cols-[minmax(15rem,18rem)_minmax(0,1fr)]">
            <aside aria-labelledby="orders-heading" className={`${mobileChatOpen ? "hidden" : "flex"} min-h-0 min-w-0 flex-col md:flex md:border-r md:border-green-100`}>
              <div className="shrink-0 border-b border-green-100 px-4 py-3 sm:px-5 sm:py-4">
                <h2 id="orders-heading" ref={conversationHeadingRef} tabIndex={-1} className="text-lg font-black">Order chats</h2>
                {orders.length > 0 && (
                  <input
                    type="search"
                    aria-label="Search order chats"
                    placeholder="Search by name, order, or status"
                    value={search}
                    onChange={(event) => setSearch(event.target.value)}
                    className="mt-2 min-h-11 w-full rounded-xl border border-green-200 bg-[#FAFCFA] px-3 text-base placeholder:text-gray-500 focus-visible:outline-2 focus-visible:outline-[#2F6B3B] md:text-sm"
                  />
                )}
              </div>
              <div className="min-h-0 flex-1 overflow-y-auto overscroll-contain">
                {filteredOrders.length > 0 ? filteredOrders.map((order) => (
                  <button
                    key={order.id}
                    type="button"
                    onClick={() => openConversation(order.id)}
                    aria-current={visibleOrder === order.id ? "true" : undefined}
                    title={order.order_code || undefined}
                    className={`block w-full border-b border-green-50 border-l-4 py-3 pr-4 pl-3 text-left transition hover:bg-green-50 focus-visible:z-10 focus-visible:outline-2 focus-visible:outline-inset focus-visible:outline-[#2F6B3B] sm:py-4 ${visibleOrder === order.id ? "border-l-[#2F6B3B] bg-[#EAF5EB]" : "border-l-transparent bg-white"}`}
                  >
                    <span className="block truncate font-bold">{participantName(order, userId, peerNames)}</span>
                    <span className="mt-1 flex items-center justify-between gap-2 text-sm text-gray-600">
                      <span className="shrink-0">Order #{shortOrderReference(order)}</span>
                      <span className="truncate">{orderStatusLabel(order)}</span>
                    </span>
                    <span className="mt-1 flex items-center justify-between gap-2 text-sm text-gray-600">
                      <span className="min-w-0 truncate">{previews[order.id]?.message || "Open chat"}</span>
                      <span className="shrink-0 text-xs">{previewTime(previews[order.id]?.created_at)}</span>
                    </span>
                  </button>
                )) : (
                  <p className="px-5 py-6 leading-relaxed text-gray-600">
                    {searchTerm ? "No conversations match your search." : "Your order conversations will appear here."}
                  </p>
                )}
              </div>
            </aside>

            <section aria-labelledby="chat-heading" className={`${mobileChatOpen ? "flex" : "hidden"} min-h-0 min-w-0 flex-col md:flex`}>
              <header className="flex shrink-0 items-center justify-between gap-2 border-b border-green-100 p-3 sm:gap-3 sm:px-5 sm:py-4">
                <div className="flex min-w-0 items-center gap-2 sm:gap-3">
                  <button ref={backRef} type="button" onClick={showConversations} className="flex min-h-11 shrink-0 items-center gap-1 rounded-xl bg-[#EAF5EB] px-3 text-sm font-bold text-[#2F6B3B] hover:bg-green-100 focus-visible:outline-2 focus-visible:outline-[#2F6B3B] md:hidden">
                    <span aria-hidden="true">ΓåÉ</span> Chats
                  </button>
                  <div aria-hidden="true" className="hidden h-11 w-11 shrink-0 items-center justify-center rounded-full bg-[#EAF5EB] text-lg font-black text-[#2F6B3B] md:flex">{otherName.slice(0, 1).toUpperCase()}</div>
                  <div className="min-w-0">
                    <h2 id="chat-heading" className="truncate text-base font-black sm:text-lg" title={otherName}>{otherName}</h2>
                    <p className="text-sm text-gray-600" title={current?.order_code}>
                      {current ? `Order #${shortOrderReference(current)}` : "Select an order conversation"}
                    </p>
                  </div>
                </div>
              </header>

              {current && (
                <div className="shrink-0 border-b border-green-100 bg-[#F7FAF7] px-3 py-3 sm:px-5 sm:py-4">
                  <div className="flex flex-wrap items-center justify-between gap-3 rounded-2xl border border-green-100 bg-white p-4 shadow-sm sm:px-5 sm:py-4">
                    <div className="flex min-w-0 items-center gap-3 sm:gap-4">
                      <span aria-hidden="true" className="flex h-11 w-11 shrink-0 items-center justify-center rounded-full bg-[#EAF5EB] text-[#2F6B3B] sm:h-12 sm:w-12">
                        <svg viewBox="0 0 24 24" fill="none" className="h-6 w-6" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round">
                          <path d="M3 7h11v10H3zM14 10h4l3 3v4h-7z" />
                          <circle cx="7.5" cy="18" r="1.5" /><circle cx="18" cy="18" r="1.5" />
                          <path d="M5 10h5M5 13h4" />
                        </svg>
                      </span>
                      <div className="min-w-0">
                        <p className="text-xs font-black tracking-[0.12em] text-[#527257]">ORDER STATUS</p>
                        <p className="mt-1 truncate text-lg font-black text-[#1E2A1F] sm:text-xl">{orderStatusLabel(current)}</p>
                        <p className="mt-0.5 truncate text-sm text-gray-600">Order #{shortOrderReference(current)}</p>
                      </div>
                    </div>
                    <span className={`inline-flex shrink-0 items-center gap-2 rounded-full px-3.5 py-2 text-xs font-black tracking-wide ${isClosed ? "bg-amber-50 text-amber-900" : "bg-green-100 text-green-800"}`}>
                      <span aria-hidden="true" className={`h-2 w-2 rounded-full ${isClosed ? "bg-amber-500" : "bg-green-600"}`} />
                      {isClosed ? "CHAT CLOSED" : "CHAT OPEN"}
                    </span>
                  </div>
                </div>
              )}

              {current && isClosed && (
                <p className="shrink-0 border-b border-amber-100 bg-amber-50 px-4 py-2 text-sm leading-snug text-amber-950 sm:px-5">
                  This order is complete. You can read the chat history.
                </p>
              )}

              <div
                key={visibleOrder}
                ref={listRef}
                aria-label="Message history"
                role="log"
                tabIndex={0}
                onScroll={(event) => {
                  const list = event.currentTarget;
                  keepAtBottom.current = list.scrollHeight - list.scrollTop - list.clientHeight < 64;
                }}
                className="min-h-0 flex-1 space-y-3 overflow-y-auto overscroll-contain bg-[#F7FAF7] p-3 focus-visible:outline-2 focus-visible:outline-inset focus-visible:outline-[#2F6B3B] sm:p-5"
              >
                {messages.length > 0 ? messages.map((item) => {
                  const mine = item.sender_id === userId;
                  const isLastOutgoing = item.id === lastOutgoingId;
                  const time = messageTime(item.created_at);
                  return (
                    <div key={item.id} className={`flex ${mine ? "justify-end" : "justify-start"}`}>
                      <div className={`min-w-0 max-w-[88%] rounded-2xl px-3.5 py-2.5 shadow-sm sm:max-w-[75%] sm:px-4 sm:py-3 ${mine ? "rounded-br-sm bg-[#2F6B3B] text-white" : "rounded-bl-sm border border-green-100 bg-white text-[#1E2A1F]"}`}>
                        <p className="whitespace-pre-wrap [overflow-wrap:anywhere] text-base leading-relaxed">{item.message}</p>
                        <div className={`mt-1.5 flex flex-wrap items-center justify-end gap-1.5 text-xs ${mine ? "text-green-100" : "text-gray-600"}`}>
                          {time && <time dateTime={item.created_at}>{time}</time>}
                          {mine && isLastOutgoing && (
                            <><span aria-hidden="true">┬╖</span><span>{item.read_at ? "Seen" : thread?.receiptsAvailable ? "Sent" : "Seen unavailable"}</span></>
                          )}
                        </div>
                      </div>
                    </div>
                  );
                }) : (
                  <div className="grid min-h-full place-content-center px-3 py-4 text-center text-gray-600">
                    {!current ? <p>Choose an order to see its messages.</p> : !thread ? <p>Loading messagesΓÇª</p> : !thread.loadError ? (
                      <>
                        <p className="font-bold text-[#1E2A1F]">No messages yet</p>
                        {!isClosed && <p className="mt-1 text-sm">Send a message to start the conversation.</p>}
                      </>
                    ) : null}
                  </div>
                )}
              </div>

              {thread?.loadError && (
                <div className="flex shrink-0 flex-wrap items-center gap-x-3 border-t border-amber-100 bg-amber-50 px-4 py-2 text-sm text-amber-950 sm:px-5">
                  <p role="alert" className="flex-1">{thread.loadError}</p>
                  <button type="button" onClick={() => void refreshChat.current?.load()} className="min-h-11 rounded-lg px-3 font-bold underline focus-visible:outline-2">Retry</button>
                </div>
              )}
              {sendError?.orderId === visibleOrder && (
                <p role="alert" className="shrink-0 bg-amber-50 px-4 py-2 text-sm text-amber-950 sm:px-5">{sendError.message}</p>
              )}
              {current && !isClosed && !thread?.loadError && (
                <form onSubmit={sendMessage} className="flex shrink-0 gap-2 border-t border-green-100 bg-white p-3 sm:gap-3 sm:p-4">
                  <input
                    aria-label="Message"
                    value={draft}
                    onChange={(event) => {
                      const value = event.target.value;
                      setDrafts((previous) => ({ ...previous, [activeOrder]: value }));
                    }}
                    disabled={!thread}
                    readOnly={sending}
                    placeholder={`Message ${otherName}ΓÇª`}
                    className="min-h-12 min-w-0 flex-1 rounded-2xl border border-green-200 bg-[#FAFCFA] px-3 text-base text-[#1E2A1F] placeholder:text-gray-500 focus-visible:outline-2 focus-visible:outline-[#2F6B3B] sm:px-4"
                  />
                  <button type="submit" disabled={!thread || !draft.trim() || sending} className="min-h-12 shrink-0 rounded-2xl bg-[#2F6B3B] px-4 font-black text-white hover:bg-[#244D2B] focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-[#2F6B3B] disabled:opacity-50 sm:px-6">{sending ? "SendingΓÇª" : "Send"}</button>
                </form>
              )}
            </section>
          </div>
        )}
      </div>
    </main>
  );
}
