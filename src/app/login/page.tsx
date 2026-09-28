import { redirect } from "next/navigation";
import { AuthForm } from "@/components/auth-form";
import { AuthShell } from "@/components/auth-shell";
import { getAccount } from "@/lib/auth/account";

export const dynamic = "force-dynamic";
export const metadata = { title: "ログイン | 旅行帳" };

export default async function LoginPage() {
  const account = await getAccount();
  if (account) redirect(account.profile ? "/trips" : "/profile");
  return (
    <AuthShell title="おかえりなさい" description="ログインして、旅の続きをはじめましょう。">
      <AuthForm mode="login" />
    </AuthShell>
  );
}
