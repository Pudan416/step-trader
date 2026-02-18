import { loginWithPassword } from "@/lib/adminAuth";
import { headers } from "next/headers";
import { redirect } from "next/navigation";

export const dynamic = "force-dynamic";

export default async function LoginPage({
  searchParams,
}: {
  searchParams: Promise<{ next?: string; error?: string }>;
}) {
  const sp = await searchParams;
  const next = sp.next?.startsWith("/") ? sp.next : "/dashboard";
  const hasError = sp.error === "1";
  const isRateLimited = sp.error === "rate";

  async function loginAction(formData: FormData) {
    "use server";
    const password = String(formData.get("password") ?? "");
    const h = await headers();
    const ip = h.get("x-forwarded-for")?.split(",")[0]?.trim() ?? h.get("x-real-ip") ?? "unknown";
    const res = await loginWithPassword(password, ip);
    if (!res.ok) {
      const errorParam = "rateLimited" in res && res.rateLimited ? "rate" : "1";
      redirect(`/login?error=${errorParam}&next=${encodeURIComponent(next)}`);
    }
    redirect(next);
  }

  return (
    <div className="min-h-screen bg-zinc-50 text-zinc-900 dark:bg-black dark:text-zinc-50">
      <div className="mx-auto flex min-h-screen max-w-md flex-col justify-center px-6">
        <h1 className="text-2xl font-semibold tracking-tight">DOOM CTRL Admin</h1>
        <p className="mt-1 text-sm text-zinc-600 dark:text-zinc-400">
          Enter admin password.
        </p>

        <form action={loginAction} className="mt-6 space-y-3">
          <input
            name="password"
            type="password"
            placeholder="Admin password"
            className="w-full rounded-lg border border-zinc-200 bg-white px-3 py-2 text-sm outline-none ring-0 focus:border-zinc-400 dark:border-zinc-800 dark:bg-zinc-950"
            autoFocus
          />
          {isRateLimited ? (
            <div className="text-sm text-red-600">Too many attempts. Try again in 15 minutes.</div>
          ) : hasError ? (
            <div className="text-sm text-red-600">Wrong password.</div>
          ) : null}
          <button
            type="submit"
            className="w-full rounded-lg bg-zinc-900 px-3 py-2 text-sm font-medium text-white hover:bg-zinc-800 dark:bg-zinc-50 dark:text-zinc-900 dark:hover:bg-zinc-200"
          >
            Sign in
          </button>
        </form>
      </div>
    </div>
  );
}

