"use client";

import Link from "next/link";
import { useCallback, useEffect, useRef, useState } from "react";
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

const terminalStatuses = new Set(["delivered", "received", "completed"]);

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
  return terminalStatuses.has((order?.status || "").toLowerCase()) || terminalStatuses.has((order?.delivery_status || "").toLowerCase());
}

function orderStatusLabel(order?: Order) {
  if (terminalStatuses.has((order?.delivery_status || "").toLowerCase())) return readableStatus(order?.delivery_status);
  if (order?.delivery_status?.trim() && order.delivery_status.toLowerCase() !== "pending") return readableStatus(order.delivery_status);
  return readableStatus(order?.status);
}

function messageTime(value: string) {
  const date = new Date(value);
  return Number.isNaN(date.getTime()) ? "" : new Intl.DateTimeFormat(undefined, { hour: "numeric", minute: "2-digit" }).format(date);
}

function previewTime(value?: string) {
  if (!value) return "";
  const date = new Date(value);
  return Number.isNaN(date.getTime()) ? "" : new Intl.DateTimeFormat(undefined, { month: "short", day: "numeric" }).format(date);
}

export default function MessagesPage() {
  const [userId, setUserId] = useState("");
  const [orders, setOrders] = useState<Order[]>([]);
  const [peerNames, setPeerNames] = useState<Record<string, string>>({});
  const [previews, setPreviews] = useState<Record<string, MessagePreview>>({});
  const [activeOrder, setActiveOrder] = useState("");
  const [messages, setMessages] = useState<Message[]>([]);
  const [draft, setDraft] = useState("");
  const [loading, setLoading] = useState(true);
  const [sending, setSending] = useState(false);
  const [error, setError] = useState("");
  const [seenReceiptsAvailable, setSeenReceiptsAvailable] = useState(true);
  const listRef = useRef<HTMLDivElement>(null);

  const loadMessages = useCallback(async (orderId: string) => {
    if (!orderId) return;
    const primary = await supabase.from("order_messages")
      .select("id, order_id, sender_id, message, created_at, read_at")
      .eq("order_id", orderId).order("created_at", { ascending: true });
    let data: Message[] | null = primary.data as Message[] | null;
    let loadError = primary.error;
    let receiptsAvailable = true;

    if (loadError && (loadError.code === "42703" || loadError.message.toLowerCase().includes("read_at"))) {
      receiptsAvailable = false;
      const fallback = await supabase.from("order_messages")
        .select("id, order_id, sender_id, message, created_at")
        .eq("order_id", orderId).order("created_at", { ascending: true });
      data = fallback.data as Message[] | null;
      loadError = fallback.error;
    }

    if (loadError) {
      setError(loadError.code === "PGRST205"
        ? "Chat database setup is required. Apply the included order_messages migration, then refresh."
        : "Could not load this chat. Check your connection and try again.");
      return;
    }

    const loadedMessages = (data || []) as Message[];
    setMessages(loadedMessages);
    const latest = loadedMessages.at(-1);
    if (latest) setPreviews((previous) => ({ ...previous, [orderId]: { message: latest.message, created_at: latest.created_at } }));
    setSeenReceiptsAvailable(receiptsAvailable);
    setError(receiptsAvailable ? "" : "Seen receipts need the chat read receipts SQL update in Supabase.");
    requestAnimationFrame(() => listRef.current?.scrollTo({ top: listRef.current.scrollHeight, behavior: "smooth" }));

    if (receiptsAvailable && userId) {
      await supabase.from("order_messages")
        .update({ read_at: new Date().toISOString() })
        .eq("order_id", orderId)
        .neq("sender_id", userId)
        .is("read_at", null);
    }
  }, [userId]);

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
      if (orderError) { setError("Could not load your orders. Please retry."); setLoading(false); return; }
      const available = (data || []) as Order[];
      setOrders(available);

      void Promise.all(available.map(async (order) => {
        const { data: latest } = await supabase.from("order_messages")
          .select("message, created_at")
          .eq("order_id", order.id)
          .order("created_at", { ascending: false })
          .limit(1)
          .maybeSingle();
        return latest ? [order.id, latest as MessagePreview] as const : null;
      })).then((latestMessages) => {
        if (alive) setPreviews(Object.fromEntries(latestMessages.filter((item): item is NonNullable<typeof item> => item !== null)));
      });

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
      const initial = available.find((order) => order.id === requestedOrder)?.id || available[0]?.id || "";
      setActiveOrder(initial);
      setLoading(false);
    }
    void start();
    return () => { alive = false; };
  }, []);

  useEffect(() => {
    if (!activeOrder) return;
    void Promise.resolve().then(() => loadMessages(activeOrder));
    const channel = supabase.channel(`web-order-chat-${activeOrder}`)
      .on("postgres_changes", { event: "*", schema: "public", table: "order_messages", filter: `order_id=eq.${activeOrder}` }, () => void loadMessages(activeOrder))
      .subscribe();
    return () => { void supabase.removeChannel(channel); };
  }, [activeOrder, loadMessages]);

  useEffect(() => {
    if (!activeOrder) return;
    const refreshOrderStatus = async () => {
      const { data } = await supabase.from("orders")
        .select("status, delivery_status")
        .eq("id", activeOrder)
        .maybeSingle();
      if (!data) return;
      setOrders((previous) => previous.map((order) => order.id === activeOrder
        ? { ...order, status: data.status, delivery_status: data.delivery_status }
        : order));
    };
    const timer = window.setInterval(() => void refreshOrderStatus(), 12000);
    return () => window.clearInterval(timer);
  }, [activeOrder]);

  async function sendMessage(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault();
    const message = draft.trim();
    if (!message || !activeOrder || sending || !userId || isClosed) return;
    setSending(true);
    setError("");
    const { error: sendError } = await supabase.from("order_messages").insert({ order_id: activeOrder, sender_id: userId, message });
    if (sendError) setError("Message not sent. Check your internet and try again.");
    else { setDraft(""); await loadMessages(activeOrder); }
    setSending(false);
  }

  const current = orders.find((order) => order.id === activeOrder);
  const otherName = current
    ? current.user_id === userId
      ? peerNames[current.farmer_id || ""] || "Farmer"
      : peerNames[current.user_id || ""] || current.shipping_name || "Buyer"
    : "Choose an order";
  const isClosed = orderIsClosed(current);
  const lastOutgoingId = [...messages].reverse().find((item) => item.sender_id === userId)?.id;

  return <main className="min-h-[100dvh] bg-[#F3F7F3] px-3 py-4 text-[#1E2A1F] sm:px-6 sm:py-7">
    <div className="mx-auto max-w-6xl">
      <div className="mb-4 flex items-center justify-between gap-3 sm:mb-6">
        <div><p className="text-xs font-black uppercase tracking-[.16em] text-[#2F6B3B] sm:text-sm">GreenGuard marketplace</p><h1 className="mt-1 text-2xl font-black sm:text-3xl">Messages</h1></div>
        <Link href="/" className="shrink-0 rounded-full border border-green-200 bg-white px-4 py-2.5 text-sm font-bold text-[#2F6B3B] sm:px-5 sm:py-3 sm:text-base">Back to store</Link>
      </div>
      {error && <div role="alert" className="mb-3 rounded-2xl bg-amber-50 p-3 text-sm font-semibold text-amber-900 sm:mb-4 sm:p-4">{error}</div>}
      {loading ? <div className="rounded-3xl bg-white p-8">Loading conversations…</div> : !userId ? <div className="rounded-3xl bg-white p-8"><p>Sign in to open your order conversations.</p><Link className="mt-4 inline-block rounded-full bg-[#2F6B3B] px-6 py-3 font-bold text-white" href="/">Sign in</Link></div> : <div className="grid h-[calc(100dvh-8.5rem)] min-h-[560px] max-h-[900px] grid-rows-[170px_minmax(0,1fr)] overflow-hidden rounded-3xl border border-green-100 bg-white shadow-lg md:grid-rows-1 md:grid-cols-[300px_minmax(0,1fr)]">
        <aside className="flex min-h-0 flex-col overflow-hidden border-b border-green-100 md:border-b-0 md:border-r">
          <div className="shrink-0 border-b border-green-100 bg-white px-4 py-3 sm:p-5"><h2 className="text-base font-black sm:text-lg">Conversations</h2><p className="mt-0.5 text-xs text-gray-500">Your order chats</p></div><div className="min-h-0 flex-1 overflow-y-auto">
          {orders.length ? orders.map((order) => {
            const participant = order.user_id === userId
              ? peerNames[order.farmer_id || ""] || "Farmer"
              : peerNames[order.user_id || ""] || order.shipping_name || "Buyer";
            const preview = previews[order.id];
            return <button key={order.id} onClick={() => setActiveOrder(order.id)} aria-current={activeOrder === order.id ? "true" : undefined} className={`block w-full border-b border-green-50 px-4 py-3 text-left transition hover:bg-green-50 sm:px-4 sm:py-3.5 ${activeOrder === order.id ? "bg-[#EAF5EB]" : "bg-white"}`}>
              <span className="flex items-center justify-between gap-2"><span className="truncate font-extrabold text-[#1E2A1F]">{participant}</span><span className="shrink-0 text-[11px] text-gray-500">{previewTime(preview?.created_at)}</span></span>
              <span className="mt-1 block truncate text-sm text-gray-600">{preview?.message || `Order #${shortOrderReference(order)}`}</span>
              <span className="mt-1.5 flex items-center justify-between gap-2"><span className="truncate text-[11px] text-gray-500">Order #{shortOrderReference(order)}</span><span className="shrink-0 rounded-full bg-green-50 px-2 py-0.5 text-[10px] font-bold text-green-800">{orderStatusLabel(order)}</span></span>
            </button>;
          }) : <p className="p-5 text-sm text-gray-600">Your order conversations will appear here.</p>}
          </div>
        </aside>
        <section className="flex min-h-0 min-w-0 flex-col">
          <header className="flex items-center justify-between gap-3 border-b border-green-100 px-4 py-3 sm:px-5 sm:py-4">
            <div className="flex min-w-0 items-center gap-3">
              <div className="flex h-10 w-10 shrink-0 items-center justify-center rounded-full bg-[#EAF5EB] text-lg font-black text-[#2F6B3B] sm:h-11 sm:w-11">{otherName.slice(0, 1).toUpperCase()}</div>
              <div className="min-w-0"><h2 className="truncate font-black sm:text-lg">{otherName}</h2><p className="truncate text-xs text-gray-600 sm:text-sm">{current ? `Order #${shortOrderReference(current)} · ${orderStatusLabel(current)}` : "Select an order conversation"}</p></div>
            </div>
            {current && <span className={`shrink-0 rounded-full px-2.5 py-1.5 text-[10px] font-black leading-tight sm:px-3 sm:text-xs ${isClosed ? "bg-amber-100 text-amber-900" : "bg-green-100 text-green-800"}`}>{isClosed ? "CHAT CLOSED" : "CHAT OPEN"}</span>}
          </header>
          {current && <div className={`mx-3 mt-3 flex items-center gap-2 rounded-xl px-3 py-2.5 text-sm sm:mx-5 sm:mt-4 sm:rounded-2xl sm:px-4 ${isClosed ? "border border-amber-200 bg-amber-50 text-amber-950" : "border border-green-100 bg-[#F5FAF5] text-[#355D3A]"}`}>
            <span><strong>{orderStatusLabel(current)}.</strong> {isClosed ? "The order is complete; both people can read the chat but cannot send new messages." : "Messages are about this order."}</span>
          </div>}
          <div ref={listRef} className="flex-1 space-y-3 overflow-y-auto bg-[#F7FAF7] px-3 py-4 sm:px-5 sm:py-5">
            {messages.length ? messages.map((item) => {
              const mine = item.sender_id === userId;
              const isLastOutgoing = item.id === lastOutgoingId;
              const time = messageTime(item.created_at);
              return <div key={item.id} className={`flex ${mine ? "justify-end" : "justify-start"}`}>
                <div className={`max-w-[88%] rounded-2xl px-3.5 py-2.5 shadow-sm sm:max-w-[75%] sm:px-4 sm:py-3 ${mine ? "rounded-br-sm bg-[#2F6B3B] text-white" : "rounded-bl-sm border border-green-100 bg-white text-[#1E2A1F]"}`}>
                  <p className="whitespace-pre-wrap break-words text-[15px] leading-relaxed">{item.message}</p>
                  <div className={`mt-1.5 flex items-center justify-end gap-1.5 text-[10px] ${mine ? "text-green-100" : "text-gray-500"}`}>
                    {time && <span>{time}</span>}
                    {mine && isLastOutgoing && <><span>{item.read_at ? "Seen" : seenReceiptsAvailable ? "Sent" : "Seen unavailable"}</span></>}
                  </div>
                </div>
              </div>;
            }) : <div className="flex h-full min-h-48 flex-col items-center justify-center px-5 text-center text-gray-500">
              <span className="flex h-14 w-14 items-center justify-center rounded-full bg-[#EAF5EB] text-2xl text-[#2F6B3B]">☘</span>
              <p className="mt-3 font-bold text-[#1E2A1F]">No messages yet</p><p className="mt-1 text-sm">{isClosed ? "This order is complete. The conversation is read-only." : "Send a message to start the conversation."}</p>
            </div>}
          </div>
          {!isClosed && <form onSubmit={sendMessage} className="flex gap-2 border-t border-green-100 bg-white p-3 sm:gap-3 sm:p-4">
            <input value={draft} onChange={(event) => setDraft(event.target.value)} disabled={!activeOrder || sending} placeholder={`Message ${otherName}…`} className="min-w-0 flex-1 rounded-full border border-green-200 bg-[#FAFCFA] px-4 py-3 text-[#1E2A1F] placeholder:text-gray-500 outline-none focus:border-[#2F6B3B] sm:px-5"/>
            <button disabled={!activeOrder || !draft.trim() || sending} className="shrink-0 rounded-full bg-[#2F6B3B] px-5 py-3 font-black text-white transition hover:bg-[#1E2A1F] disabled:opacity-50 sm:px-6">{sending ? "…" : "Send"}</button>
          </form>}
        </section>
      </div>}
    </div>
  </main>;
}
