"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";

export async function logout(): Promise<{ error: string }> {
  try {
    const supabase = await createClient();
    const { error } = await supabase.auth.signOut({ scope: "local" });
    if (error) return { error: "ログアウトできませんでした。もう一度お試しください。" };
  } catch {
    return { error: "接続できませんでした。時間をおいて再度お試しください。" };
  }
  revalidatePath("/", "layout");
  redirect("/login");
}
