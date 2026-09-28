import { redirect } from "next/navigation";
import { AuthForm } from "@/components/auth-form";
import { AuthShell } from "@/components/auth-shell";
import { getAccount } from "@/lib/auth/account";

export const dynamic = "force-dynamic";
export const metadata = { title: "アカウント作成 | 旅行帳" };

export default async function SignupPage() {
  const account = await getAccount();
  if (account) redirect(account.profile ? "/trips" : "/profile");
  return (
    <AuthShell title="旅行帳をはじめる" description="旅の計画と思い出を、あなたの一冊に。">
      <AuthForm mode="signup" />
    </AuthShell>
  );
}
