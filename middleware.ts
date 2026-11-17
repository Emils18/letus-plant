import { createServerClient } from "@supabase/ssr";
import { NextResponse, type NextRequest } from "next/server";

function clearAuthCookies(response: NextResponse, request: NextRequest) {
  for (const cookie of request.cookies.getAll()) {
    const name = cookie.name.toLowerCase();
    if (name.startsWith("sb-") || name.includes("supabase")) {
      response.cookies.set(cookie.name, "", { maxAge: 0, path: "/" });
    }
  }
}

export async function middleware(request: NextRequest) {
  if (!request.nextUrl.pathname.startsWith("/admin")) {
    return NextResponse.next();
  }

  let supabaseResponse = NextResponse.next({ request });

  const supabase = createServerClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
    {
      cookies: {
        getAll() {
          return request.cookies.getAll();
        },
        setAll(cookiesToSet) {
          cookiesToSet.forEach(({ name, value }) => request.cookies.set(name, value));
          supabaseResponse = NextResponse.next({ request });
          cookiesToSet.forEach(({ name, value, options }) =>
            supabaseResponse.cookies.set(name, value, options)
          );
        },
      },
    }
  );

  const {
    data: { user },
  } = await supabase.auth.getUser();

  if (!user) {
    const loginUrl = new URL("/", request.url);
    const redirect = NextResponse.redirect(loginUrl);
    clearAuthCookies(redirect, request);
    return redirect;
  }

  const { data: profile } = await supabase
    .from("users")
    .select("role")
    .eq("id", user.id)
    .maybeSingle();

  if (!profile || String(profile.role).toLowerCase() !== "admin") {
    const homeUrl = new URL("/", request.url);
    const redirect = NextResponse.redirect(homeUrl);
    if (!profile) clearAuthCookies(redirect, request);
    return redirect;
  }

  return supabaseResponse;
}

export const config = {
  matcher: "/admin/:path*",
};
