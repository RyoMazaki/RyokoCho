import "server-only";

import { isAuthSessionMissingError } from "@supabase/supabase-js";
import { getCurrentUser } from "@/lib/supabase/auth";
import { createClient } from "@/lib/supabase/server";

export async function getAccount() {
  const { data: { user }, error } = await getCurrentUser();
  if (error) {
    if (isAuthSessionMissingError(error) || error.status === 401 || error.status === 403) {
      return null;
    }
    throw new Error("認証状態を確認できませんでした。時間をおいて再度お試しください。");
  }
  if (!user) return null;

  const supabase = await createClient();
  const { data: profile, error: profileError } = await supabase
    .from("profiles")
    .select("display_name")
    .eq("id", user.id)
    .maybeSingle();

  if (profileError) throw new Error("プロフィールを読み込めませんでした。");
  return { user, profile };
}
