"use client";

import { useActionState } from "react";
import { logout } from "@/app/auth/actions";

export function LogoutButton() {
  const [state, action, pending] = useActionState(logout, { error: "" });
  return (
    <form action={action}>
      <button type="submit" disabled={pending} className="text-link disabled:opacity-50">
        {pending ? "ログアウト中…" : "ログアウト"}
      </button>
      {state.error && <p role="alert" className="error-message mt-3">{state.error}</p>}
    </form>
  );
}
