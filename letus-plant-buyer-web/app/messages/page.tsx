"use client";

import Link from "next/link";
import { useCallback, useEffect, useRef, useState } from "react";
import { supabase } from "@/lib/supabase";

type Order = { id: string; order_code?: string; user_id?: string; farmer_id?: string; shipping_name?: string; status?: string; delivery_status?: string; created_at?: string };
type Message = { id: string; order_id: string; sender_id: string; message: string; created_at: string };

export default function MessagesPage() {
  const [userId, setUserId] = useState("");
  const [orders, setOrders] = useState<Order[]>([]);
  const [activeOrder, setActiveOrder] = useState("");
  const [messages, setMessages] = useState<Message[]>([]);
  const [draft, setDraft] = useState("");
  const [loading, setLoading] = useState(true);
  const [sending, setSending] = useState(false);
  const [error, setError] = useState("");
  const listRef = useRef<HTMLDivElement>(null);

  const loadMessages = useCallback(async (orderId: string) => {
    if (!orderId) return;
    const { data, error: loadError } = await supabase.from("order_messages")
      .select("id, order_id, sender_id, message, created_at")
      .eq("order_id", orderId).order("created_at", { ascending: true });
    if (loadError) { setError(loadError.code === "PGRST205" ? "Chat database setup is required. Apply the included order_messages migration, then refresh." : "Could not load this chat. Check connection and try again."); return; }
    setMessages((data || []) as Message[]);
    setError("");
    requestAnimationFrame(() => listRef.current?.scrollTo({ top: listRef.current.scrollHeight, behavior: "smooth" }));
  }, []);

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
    setSending(true); setError("");
    const { error: sendError } = await supabase.from("order_messages").insert({ order_id: activeOrder, sender_id: userId, message });
    if (sendError) setError("Message not sent. Check your internet and try again.");
    else { setDraft(""); await loadMessages(activeOrder); }
    setSending(false);
  }

  const current = orders.find((order) => order.id === activeOrder);
  const otherName = current?.user_id === userId ? "Farmer" : (current?.shipping_name || "Buyer");
  const terminalStatuses = new Set(["delivered", "received", "completed"]);
  const isClosed = terminalStatuses.has((current?.status || "").toLowerCase()) || terminalStatuses.has((current?.delivery_status || "").toLowerCase());

  return <main className="min-h-screen bg-[#F5F9F4] px-4 py-8 text-[#1E2A1F] sm:px-8">
    <div className="mx-auto max-w-6xl">
      <div className="mb-6 flex items-center justify-between gap-4">
        <div><p className="text-sm font-black uppercase tracking-widest text-[#2F6B3B]">GreenGuard marketplace</p><h1 className="mt-1 text-3xl font-black">Messages</h1></div>
        <Link href="/" className="rounded-full border border-green-200 bg-white px-5 py-3 font-bold text-[#2F6B3B]">Back to store</Link>
      </div>
      {error && <div role="alert" className="mb-4 rounded-2xl bg-amber-50 p-4 font-semibold text-amber-900">{error}</div>}
      {loading ? <div className="rounded-3xl bg-white p-8">Loading conversations…</div> : !userId ? <div className="rounded-3xl bg-white p-8"><p>Sign in to open your order conversations.</p><Link className="mt-4 inline-block rounded-full bg-[#2F6B3B] px-6 py-3 font-bold text-white" href="/">Sign in</Link></div> : <div className="grid min-h-[70vh] overflow-hidden rounded-3xl border border-green-100 bg-white shadow-xl md:grid-cols-[280px_1fr]">
        <aside className="border-b border-green-100 md:border-b-0 md:border-r">
          <h2 className="border-b border-green-100 p-5 text-lg font-black">Order chats</h2>
          {orders.length ? orders.map((order) => <button key={order.id} onClick={() => setActiveOrder(order.id)} className={`block w-full border-b border-green-50 p-4 text-left hover:bg-green-50 ${activeOrder === order.id ? "bg-green-50" : ""}`}><span className="block font-bold">Order {order.order_code || order.id.slice(0, 8)}</span><span className="mt-1 block text-sm text-gray-600">{order.user_id === userId ? "Farmer" : order.shipping_name || "Buyer"}</span></button>) : <p className="p-5 text-sm text-gray-600">Your order conversations will appear here.</p>}
        </aside>
        <section className="flex min-h-[65vh] flex-col">
          <header className="flex items-center justify-between gap-4 border-b border-green-100 px-5 py-4">
            <div className="flex min-w-0 items-center gap-3">
              <div className="flex h-11 w-11 shrink-0 items-center justify-center rounded-full bg-[#EAF5EB] text-lg font-black text-[#2F6B3B]">{otherName.slice(0, 1).toUpperCase()}</div>
              <div className="min-w-0"><h2 className="truncate font-black">{current ? `${otherName} · Order ${current.order_code || current.id.slice(0, 8)}` : "Choose an order"}</h2><p className="text-sm text-gray-600">{isClosed ? "Conversation history" : "Order conversation"}</p></div>
            </div>
            <span className={`shrink-0 rounded-full px-3 py-1.5 text-xs font-black ${isClosed ? "bg-amber-100 text-amber-900" : "bg-green-100 text-green-800"}`}>{isClosed ? "ORDER COMPLETE" : "IN PROGRESS"}</span>
          </header>
          {isClosed && <div className="mx-5 mt-4 flex items-start gap-3 rounded-2xl border border-amber-200 bg-amber-50 px-4 py-3 text-sm text-amber-950"><span aria-hidden="true">🔒</span><p><strong>Chat closed.</strong> This order has been delivered or completed. You can still read past messages, but neither person can send new ones.</p></div>}
          <div ref={listRef} className="flex-1 space-y-3 overflow-y-auto p-5">{messages.length ? messages.map((item) => <div key={item.id} className={`flex ${item.sender_id === userId ? "justify-end" : "justify-start"}`}><p className={`max-w-[80%] whitespace-pre-wrap break-words rounded-2xl px-4 py-3 ${item.sender_id === userId ? "bg-[#2F6B3B] text-white" : "bg-[#F1F5F0] text-[#1E2A1F]"}`}>{item.message}</p></div>) : <p className="pt-10 text-center text-gray-500">No messages yet. Start the conversation.</p>}</div>
          {!isClosed && <form onSubmit={sendMessage} className="flex gap-3 border-t border-green-100 bg-[#FCFDFC] p-4"><input value={draft} onChange={(event) => setDraft(event.target.value)} disabled={!activeOrder || sending} placeholder="Write a message…" className="min-w-0 flex-1 rounded-full border border-green-200 bg-white px-5 py-3 text-[#1E2A1F] placeholder:text-gray-500 outline-none focus:border-[#2F6B3B]"/><button disabled={!activeOrder || !draft.trim() || sending} className="rounded-full bg-[#2F6B3B] px-6 py-3 font-black text-white transition hover:bg-[#1E2A1F] disabled:opacity-50">{sending ? "Sending…" : "Send"}</button></form>}
        </section>
      </div>}
    </div>
  </main>;
}
