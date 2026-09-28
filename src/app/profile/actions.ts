"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { getAccount } from "@/lib/auth/account";
import { createClient } from "@/lib/supabase/server";

export async function saveProfile(
  _previous: { error: string },
  formData: FormData,
): Promise<{ error: string }> {
  const raw = formData.get("display_name");
  if (typeof raw !== "string" || !raw.trim()) {
    return { error: "表示名を入力してください。" };
  }

  let signedOut = false;
  try {
    const account = await getAccount();
    if (!account) {
      signedOut = true;
    } else {
      const supabase = await createClient();
      // Derive identity from verified Auth, never from a submitted user ID.
      // Do not upsert: UPDATE permission is restricted to display_name only.
      const query = account.profile
        ? supabase.from("profiles").update({ display_name: raw.trim() }).eq("id", account.user.id)
        : supabase.from("profiles").insert({ id: account.user.id, display_name: raw.trim() });
      const { data, error } = await query.select("id").single();
      if (error || !data) {
        return { error: "保存できませんでした。内容を確認して、もう一度お試しください。" };
      }
    }
  } catch {
    return { error: "接続できませんでした。入力内容はそのままで、もう一度お試しください。" };
  }

  if (signedOut) redirect("/login");
  revalidatePath("/", "layout");
  redirect("/trips");
}
