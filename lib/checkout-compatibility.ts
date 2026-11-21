type DatabaseError = { code?: string; message: string };

export function isMissingCheckoutRpc(error: DatabaseError | null): boolean {
  return error?.code === "PGRST202" && error.message.includes("place_marketplace_order");
}

export function canUseLegacyCheckout(error: DatabaseError | null): boolean {
  return error?.code === "42703" && error.message.includes("archived_at");
}
