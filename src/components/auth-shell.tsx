import Link from "next/link";

export function AuthShell({ title, description, children }: {
  title: string;
  description: string;
  children: React.ReactNode;
}) {
  return (
    <main className="mx-auto flex min-h-screen w-full max-w-md flex-col justify-center px-6 py-12">
      <Link href="/" prefetch={false} className="mb-10 text-xl font-bold tracking-widest text-teal-800">旅行帳</Link>
      <section className="rounded-2xl border border-stone-200 bg-white p-6 shadow-sm sm:p-8">
        <h1 className="text-2xl font-bold">{title}</h1>
        <p className="mt-3 mb-7 text-sm leading-7 text-stone-600">{description}</p>
        {children}
      </section>
      <p className="mt-6 text-center text-xs text-stone-500">計画も、思い出も、ひとつの旅行帳に。</p>
    </main>
  );
}
