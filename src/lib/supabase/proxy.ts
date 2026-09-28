import "server-only";

import { createServerClient } from "@supabase/ssr";
import { NextResponse, type NextRequest } from "next/server";

import type { Database } from "@/types/database.types";
import { getSupabaseEnv } from "./env";

export async function updateSession(request: NextRequest) {
  const { url, publishableKey } = getSupabaseEnv();
  let response = NextResponse.next({ request });

  const supabase = createServerClient<Database>(url, publishableKey, {
    cookies: {
      getAll() {
        return request.cookies.getAll();
      },
      setAll(cookiesToSet, headers) {
        cookiesToSet.forEach(({ name, value }) => {
          request.cookies.set(name, value);
        });

        const previousCookies = response.cookies.getAll();
        response = NextResponse.next({ request, headers: response.headers });
        previousCookies.forEach((cookie) => response.cookies.set(cookie));
        cookiesToSet.forEach(({ name, value, options }) => {
          response.cookies.set(name, value, options);
        });
        Object.entries(headers).forEach(([name, value]) => {
          response.headers.set(name, value);
        });
      },
    },
  });

  // Refresh and verify the JWT before downstream Server Components read cookies.
  // This is not a route guard: each protected operation must check auth and RLS.
  await supabase.auth.getClaims();

  // Auth responses (including refreshed cookies) must not enter shared caches.
  response.headers.set("Cache-Control", "private, no-store");
  return response;
}
