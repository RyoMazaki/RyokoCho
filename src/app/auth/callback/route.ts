import { NextResponse, type NextRequest } from "next/server";
import { createClient } from "@/lib/supabase/server";

export async function GET(request: NextRequest) {
  const params = request.nextUrl.searchParams;
  let destination = "/auth/error";

  // Fixed destinations: never trust an arbitrary next URL or provider error text.
  if (!params.has("error")) {
    const code = params.get("code");
    const tokenHash = params.get("token_hash");
    try {
      const supabase = await createClient();
      if (code && !tokenHash) {
        const { error } = await supabase.auth.exchangeCodeForSession(code);
        if (!error) destination = "/";
      } else if (tokenHash && !code && params.get("type") === "email") {
        const { error } = await supabase.auth.verifyOtp({ token_hash: tokenHash, type: "email" });
        if (!error) destination = "/";
      }
    } catch {
      // Do not expose tokens or the provider's error payload.
    }
  }

  const response = NextResponse.redirect(new URL(destination, request.url));
  response.headers.set("Cache-Control", "private, no-store");
  response.headers.set("Referrer-Policy", "no-referrer");
  return response;
}
