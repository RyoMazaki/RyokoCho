import Link from "next/link";
import { redirect } from "next/navigation";
import { LogoutButton } from "@/components/logout-button";
import { getAccount } from "@/lib/auth/account";

export const dynamic = "force-dynamic";
export const metadata = { title: "ホーム | 旅行帳" };

export default async function TripsPage() {
  const account = await getAccount();
  if (!account) redirect("/login");
  if (!account.profile) redirect("/profile");

  return (
    <main className="mx-auto w-full max-w-3xl px-6 py-10">
      <header className="flex flex-wrap items-center justify-between gap-5 border-b border-stone-200 pb-6">
        <span className="text-xl font-bold tracking-widest text-teal-800">旅行帳</span>
        <nav aria-label="アカウント" className="flex gap-6 text-sm">
          <Link href="/profile" prefetch={false} className="text-link">プロフィール</Link>
          <LogoutButton />
        </nav>
      </header>
      <section className="py-16">
        <p className="mb-3 text-sm text-stone-600">こんにちは、{account.profile.display_name}さん</p>
        <h1 className="text-3xl font-bold">旅行帳へようこそ</h1>
        <p className="mt-6 leading-8 text-stone-600">アカウントの準備ができました。<br />旅行一覧は準備中です。</p>
      </section>
    </main>
  );
}
