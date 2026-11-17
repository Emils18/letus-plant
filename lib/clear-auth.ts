import type { SupabaseClient } from "@supabase/supabase-js";

function isAuthStorageKey(name: string) {
  const lower = name.toLowerCase();
  return lower.startsWith("sb-") || lower.includes("supabase");
}

function clearBrowserAuthStorage() {
  if (typeof window === "undefined") return;

  try {
    for (const key of Object.keys(localStorage)) {
      if (isAuthStorageKey(key)) localStorage.removeItem(key);
    }
  } catch {
    // Ignore storage access errors (private mode, blocked storage).
  }

  try {
    for (const key of Object.keys(sessionStorage)) {
      if (isAuthStorageKey(key)) sessionStorage.removeItem(key);
    }
  } catch {
    // Ignore storage access errors.
  }

  document.cookie.split(";").forEach((cookie) => {
    const name = cookie.split("=")[0]?.trim();
    if (!name || !isAuthStorageKey(name)) return;
    document.cookie = `${name}=; Max-Age=0; path=/; SameSite=Lax`;
  });
}

export async function completeSignOut(client: SupabaseClient) {
  await client.auth.signOut({ scope: "global" }).catch(() => undefined);
  clearBrowserAuthStorage();
}
