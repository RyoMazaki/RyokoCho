import Link from "next/link";
import { AuthShell } from "@/components/auth-shell";

export const metadata = { title: "認証を完了できませんでした | 旅行帳" };

export default function AuthErrorPage() {
  return (
    <AuthShell title="認証を完了できませんでした" description="リンクの有効期限が切れているか、すでに使用されている可能性があります。Googleでの認証を中断した場合は、もう一度お試しください。">
      <div className="space-y-5">
        <p className="text-sm leading-7 text-stone-600">メール確認が済んでいる場合は、メールアドレスとパスワードでログインできます。</p>
        <Link href="/login" prefetch={false} className="primary-button">ログインへ</Link>
        <Link href="/signup" prefetch={false} className="secondary-button">アカウント作成へ</Link>
      </div>
    </AuthShell>
  );
}
