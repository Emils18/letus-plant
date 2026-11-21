export function paymentStatusLabel(status?: unknown, paymentMethod?: unknown): string {
  const value = typeof status === "string" ? status.trim() : "";
  const method = typeof paymentMethod === "string" ? paymentMethod.trim().toLowerCase() : "";
  if (!value || value.toLowerCase() === "to be agreed in person") return "Unpaid";
  if (value.toLowerCase() === "paid") return "Paid";
  if (value.toLowerCase() === "unpaid" || value.toLowerCase() === method) return "Unpaid";
  return value;
}
