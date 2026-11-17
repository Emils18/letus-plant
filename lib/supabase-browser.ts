import { createBrowserClient } from "@supabase/ssr";

/**
 * Creates a Supabase client for use in Client Components ("use client").
 * Uses @supabase/ssr so auth tokens are stored in cookies (not just localStorage),
 * making them available to the server on every request.
 */
export function createBrowserSupabaseClient() {
  return createBrowserClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!
  );
}
