import { createBrowserClient } from "@supabase/ssr";
import { createClient } from "@supabase/supabase-js";

const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL;
const supabaseAnonKey = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;

if (!supabaseUrl) {
  throw new Error("Missing NEXT_PUBLIC_SUPABASE_URL");
}
if (!supabaseAnonKey) {
  throw new Error("Missing NEXT_PUBLIC_SUPABASE_ANON_KEY");
}

/**
 * Public client – used in browser code (auth, data fetches).
 * Uses @supabase/ssr so the auth session is stored in cookies,
 * making it accessible to the server (middleware, server components).
 */
export const supabase = createBrowserClient(supabaseUrl, supabaseAnonKey);

/**
 * Server‑only admin client – uses the service role key.
 * NEVER import this in client‑side bundles.
 */
const supabaseServiceKey = process.env.SUPABASE_SERVICE_ROLE_KEY;
if (!supabaseServiceKey) {
  // In development we still allow the app to run, but any admin‑only code will error.
  console.warn("SUPABASE_SERVICE_ROLE_KEY is not set – admin operations will fail.");
}
export const supabaseAdmin = createClient(supabaseUrl, supabaseServiceKey || "", {
  auth: {
    persistSession: false,
    autoRefreshToken: false,
  },
});
