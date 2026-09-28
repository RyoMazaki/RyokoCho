"use client";

import Link from "next/link";

export default function ErrorPage({ reset }: { reset: () => void }) {
  return (
    <main className="mx-auto flex min-h-screen max-w-md flex-col justify-center gap-6 px-6">
      <h1 className="text-2xl font-bold">読み込みができませんでした</h1>
      <p className="leading-7 text-stone-600">通信環境を確認して、時間をおいてもう一度お試しください。</p>
      <button onClick={reset} className="primary-button">もう一度試す</button>
      <Link href="/login" prefetch={false} className="text-link">ログイン画面へ</Link>
    </main>
  );
}
