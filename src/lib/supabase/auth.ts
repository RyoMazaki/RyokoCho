import "server-only";

import { createClient } from "./server";

// Validate with Supabase Auth; never authorize from getSession().data.session.
// Preserve the SDK's error so callers can distinguish missing auth from outages.
export async function getCurrentUser() {
  const supabase = await createClient();
  return supabase.auth.getUser();
}
