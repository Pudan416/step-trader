import Link from "next/link";
import { logout } from "@/lib/adminAuth";
import { redirect } from "next/navigation";

export const dynamic = "force-dynamic";

export default function AdminLayout({ children }: { children: React.ReactNode }) {
  async function logoutAction() {
    "use server";
    await logout();
    redirect("/login");
  }

  return (
    <div className="min-h-screen bg-zinc-50 text-zinc-900 dark:bg-black dark:text-zinc-50">
      <header className="border-b border-zinc-200 bg-white/70 backdrop-blur dark:border-zinc-800 dark:bg-zinc-950/60">
        <div className="mx-auto flex max-w-6xl items-center justify-between px-6 py-4">
          <div className="flex items-center gap-6">
            <Link href="/dashboard" className="font-semibold tracking-tight">
              DOOM CTRL Admin
            </Link>
            <nav className="flex items-center gap-3 text-sm text-zinc-600 dark:text-zinc-400">
              <Link href="/dashboard" className="hover:text-zinc-900 dark:hover:text-zinc-50">
                Dashboard
              </Link>
              <Link href="/users" className="hover:text-zinc-900 dark:hover:text-zinc-50">
                Users
              </Link>
            </nav>
          </div>
          <form action={logoutAction}>
            <button
              type="submit"
              className="rounded-lg border border-zinc-200 bg-white px-3 py-1.5 text-sm hover:bg-zinc-50 dark:border-zinc-800 dark:bg-zinc-950 dark:hover:bg-zinc-900"
            >
              Logout
            </button>
          </form>
        </div>
      </header>

      <main className="mx-auto max-w-6xl px-6 py-6">{children}</main>
    </div>
  );
}

