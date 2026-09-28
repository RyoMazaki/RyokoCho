import Link from "next/link";
import { redirect } from "next/navigation";
import { AuthShell } from "@/components/auth-shell";
import { ProfileForm } from "@/components/profile-form";
import { LogoutButton } from "@/components/logout-button";
import { getAccount } from "@/lib/auth/account";

export const dynamic = "force-dynamic";
export const metadata = { title: "プロフィール | 旅行帳" };

export default async function ProfilePage() {
  const account = await getAccount();
  if (!account) redirect("/login");
  return (
    <AuthShell
      title={account.profile ? "プロフィール" : "はじめまして"}
      description={account.profile ? "旅行帳で使う名前を変更できます。" : "まずは、旅行帳で使う名前を教えてください。"}
    >
      <ProfileForm displayName={account.profile?.display_name ?? ""} initial={!account.profile} />
      <div className="mt-7 flex items-center justify-between border-t border-stone-200 pt-5 text-sm">
        {account.profile && <Link href="/trips" prefetch={false} className="text-link">戻る</Link>}
        <LogoutButton />
      </div>
    </AuthShell>
  );
}
