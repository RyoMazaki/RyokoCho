"use client";

import { useActionState, useState } from "react";
import { saveProfile } from "@/app/profile/actions";

export function ProfileForm({ displayName, initial }: { displayName: string; initial: boolean }) {
  const [name, setName] = useState(displayName);
  const [state, action, pending] = useActionState(saveProfile, { error: "" });
  return (
    <form action={action} className="space-y-6" aria-busy={pending}>
      <label htmlFor="display-name" className="field-label">表示名
        <input id="display-name" name="display_name" autoComplete="nickname" className="text-input" value={name} onChange={(event) => setName(event.target.value)} required readOnly={pending} />
      </label>
      <p className="text-sm leading-7 text-stone-600">一緒に旅行するメンバーに表示される名前です。ほかの人と同じ名前でも使えます。</p>
      {state.error && <p role="alert" className="error-message">{state.error}</p>}
      <button type="submit" className="primary-button" disabled={pending}>
        {pending ? "保存中…" : initial ? "保存してはじめる" : "保存する"}
      </button>
    </form>
  );
}
