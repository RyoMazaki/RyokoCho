"use client";

import Link from "next/link";
import { useRouter } from "next/navigation";
import { useState, type FormEvent } from "react";
import { createClient } from "@/lib/supabase/client";
import { authErrorMessage } from "@/lib/auth/messages";

export function AuthForm({ mode }: { mode: "login" | "signup" }) {
  const router = useRouter();
  const signup = mode === "signup";
  const [pending, setPending] = useState<"email" | "google" | null>(null);
  const [error, setError] = useState("");
  const [sent, setSent] = useState(false);

  async function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (pending) return;
    setError("");
    const form = new FormData(event.currentTarget);
    const email = String(form.get("email") ?? "").trim();
    const password = String(form.get("password") ?? "");
    if (signup && password !== form.get("confirmation")) {
      setError("確認用パスワードが一致しません。");
      return;
    }
    setPending("email");
    try {
      const supabase = createClient();
      if (signup) {
        const { data, error } = await supabase.auth.signUp({
          email,
          password,
          options: { emailRedirectTo: new URL("/auth/callback", window.location.origin).href },
        });
        if (error) {
          setError(authErrorMessage(error.code));
        } else if (data.session) {
          router.replace("/");
          router.refresh();
          return;
        } else {
          setSent(true);
        }
      } else {
        const { error } = await supabase.auth.signInWithPassword({ email, password });
        if (error) {
          setError(authErrorMessage(error.code));
        } else {
          // Invalidate server navigation data after the SDK writes session cookies.
          router.replace("/");
          router.refresh();
          return;
        }
      }
    } catch {
      setError("接続できませんでした。通信環境を確認して、もう一度お試しください。");
    }
    setPending(null);
  }

  async function google() {
    if (pending) return;
    setError("");
    setPending("google");
    try {
      const { data, error } = await createClient().auth.signInWithOAuth({
        provider: "google",
        options: {
          redirectTo: new URL("/auth/callback", window.location.origin).href,
          skipBrowserRedirect: true,
        },
      });
      if (error || !data.url) {
        setError("Googleログインを開始できませんでした。時間をおいて再度お試しください。");
      } else {
        window.location.assign(data.url);
        return;
      }
    } catch {
      setError("接続できませんでした。通信環境を確認してください。");
    }
    setPending(null);
  }

  if (sent) {
    return (
      <div className="space-y-5">
        <p role="status" className="notice">
          確認メールをご確認ください。届いたリンクを開くと登録を続けられます。
          登録済みの場合はログインしてください。
        </p>
        <p className="text-sm leading-7 text-stone-600">届かない場合は迷惑メールフォルダもご確認ください。</p>
        <Link href="/login" prefetch={false} className="text-link">ログインへ</Link>
        <button type="button" className="secondary-button" onClick={() => setSent(false)}>登録画面に戻る</button>
      </div>
    );
  }

  return (
    <div className="space-y-6">
      <button type="button" onClick={google} disabled={pending !== null} className="secondary-button">
        {pending === "google" ? "Googleに接続中…" : "Googleで続ける"}
      </button>
      <div className="flex items-center gap-3 text-xs text-stone-500">
        <span className="h-px flex-1 bg-stone-200" />またはメールアドレスで<span className="h-px flex-1 bg-stone-200" />
      </div>
      <form onSubmit={submit} className="space-y-5" aria-busy={pending !== null}>
        <fieldset disabled={pending !== null} className="space-y-5">
          <label className="field-label" htmlFor="email">メールアドレス
            <input className="text-input" id="email" name="email" type="email" autoComplete="email" required />
          </label>
          <label className="field-label" htmlFor="password">パスワード
            <input className="text-input" id="password" name="password" type="password" autoComplete={signup ? "new-password" : "current-password"} required />
          </label>
          {signup && (
            <label className="field-label" htmlFor="confirmation">パスワード（確認）
              <input className="text-input" id="confirmation" name="confirmation" type="password" autoComplete="new-password" required />
            </label>
          )}
          {error && <p role="alert" className="error-message">{error}</p>}
          <button type="submit" className="primary-button">
            {pending === "email" ? "送信中…" : signup ? "アカウントを作成" : "ログイン"}
          </button>
        </fieldset>
      </form>
      <p className="text-center text-sm text-stone-600">
        {signup ? "アカウントをお持ちの方は " : "はじめての方は "}
        <Link href={signup ? "/login" : "/signup"} prefetch={false} className="text-link">
          {signup ? "ログイン" : "アカウント作成"}
        </Link>
      </p>
    </div>
  );
}
