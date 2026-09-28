import { redirect } from "next/navigation";
import { getAccount } from "@/lib/auth/account";

export const dynamic = "force-dynamic";

export default async function Home() {
  const account = await getAccount();
  if (!account) redirect("/login");
  redirect(account.profile ? "/trips" : "/profile");
}
