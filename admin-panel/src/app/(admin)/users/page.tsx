import { countShields, listPublicUsers, sumEnergyDelta } from "@/lib/queries";
import Link from "next/link";

export const dynamic = "force-dynamic";

const PAGE_SIZE = 50;

function fmt(v: string | null | undefined) {
  return v && v.trim().length ? v : "—";
}

export default async function UsersPage({
  searchParams,
}: {
  searchParams: Promise<{ page?: string; q?: string }>;
}) {
  const sp = await searchParams;
  const page = Math.max(1, Number(sp.page) || 1);
  const offset = (page - 1) * PAGE_SIZE;
  const search = sp.q ?? "";

  let users: Awaited<ReturnType<typeof listPublicUsers>> = { rows: [], total: 0 };
  let totalShields: number | null = null;
  let totalEnergy: Awaited<ReturnType<typeof sumEnergyDelta>> | null = null;
  let error: string | null = null;

  try {
    [users, totalShields, totalEnergy] = await Promise.all([
      listPublicUsers({ limit: PAGE_SIZE, offset, search: search || undefined }),
      countShields(),
      sumEnergyDelta(),
    ]);
  } catch (e: any) {
    error = String(e?.message ?? e);
  }

  const totalPages = Math.max(1, Math.ceil(users.total / PAGE_SIZE));

  return (
    <div className="space-y-6">
      <div className="flex items-end justify-between gap-6">
        <div>
          <h1 className="text-xl font-semibold tracking-tight">Users</h1>
          <p className="mt-1 text-sm text-zinc-600 dark:text-zinc-400">
            {users.total} profiles from <code className="font-mono">public.users</code>.
          </p>
        </div>
        <div className="text-right text-xs text-zinc-600 dark:text-zinc-400">
          <div>Total shields: {totalShields ?? "—"}</div>
          <div>Total energy: {totalEnergy?.total ?? "—"}</div>
        </div>
      </div>

      {/* Search */}
      <form className="flex gap-2" method="GET">
        <input
          name="q"
          type="text"
          defaultValue={search}
          placeholder="Search by nickname, email, or UUID..."
          className="w-full max-w-md rounded-lg border border-zinc-200 bg-white px-3 py-2 text-sm outline-none focus:border-zinc-400 dark:border-zinc-800 dark:bg-zinc-950"
        />
        <button
          type="submit"
          className="rounded-lg bg-zinc-900 px-4 py-2 text-sm font-medium text-white hover:bg-zinc-800 dark:bg-zinc-50 dark:text-zinc-900 dark:hover:bg-zinc-200"
        >
          Search
        </button>
        {search ? (
          <Link
            href="/users"
            className="flex items-center rounded-lg border border-zinc-200 px-3 py-2 text-sm hover:bg-zinc-50 dark:border-zinc-800 dark:hover:bg-zinc-900"
          >
            Clear
          </Link>
        ) : null}
      </form>

      {error ? (
        <div className="rounded-2xl border border-red-200 bg-red-50 p-4 text-sm text-red-800 dark:border-red-900/60 dark:bg-red-950/40 dark:text-red-200">
          <div className="font-medium">Failed to load</div>
          <div className="mt-1 font-mono text-xs">{error}</div>
          <div className="mt-2 text-xs">
            Check <code className="font-mono">/api/health</code>.
          </div>
        </div>
      ) : null}

      <div className="overflow-hidden rounded-2xl border border-zinc-200 bg-white dark:border-zinc-800 dark:bg-zinc-950">
        <table className="w-full text-sm">
          <thead className="bg-zinc-50 text-left text-xs text-zinc-600 dark:bg-zinc-900/30 dark:text-zinc-400">
            <tr>
              <th className="px-4 py-3">User</th>
              <th className="px-4 py-3">Email</th>
              <th className="px-4 py-3">Country</th>
              <th className="px-4 py-3">Created</th>
              <th className="px-4 py-3">Status</th>
            </tr>
          </thead>
          <tbody>
            {users.rows.map((u) => (
              <tr
                key={u.id}
                className="border-t border-zinc-100 hover:bg-zinc-50/60 dark:border-zinc-900 dark:hover:bg-zinc-900/20"
              >
                <td className="px-4 py-3">
                  <Link
                    href={`/users/${u.id}`}
                    className="font-mono text-xs text-zinc-900 hover:underline dark:text-zinc-50"
                  >
                    {u.id}
                  </Link>
                  <div className="text-xs text-zinc-600 dark:text-zinc-400">{fmt(u.nickname)}</div>
                </td>
                <td className="px-4 py-3">{fmt(u.email)}</td>
                <td className="px-4 py-3">{fmt(u.country)}</td>
                <td className="px-4 py-3">{new Date(u.created_at).toLocaleString()}</td>
                <td className="px-4 py-3">
                  {u.is_banned ? (
                    <span className="rounded-full bg-red-100 px-2 py-1 text-xs text-red-700 dark:bg-red-950 dark:text-red-300">
                      banned
                    </span>
                  ) : (
                    <span className="rounded-full bg-green-100 px-2 py-1 text-xs text-green-700 dark:bg-green-950 dark:text-green-300">
                      ok
                    </span>
                  )}
                </td>
              </tr>
            ))}
            {users.rows.length === 0 ? (
              <tr>
                <td className="px-4 py-6 text-zinc-600 dark:text-zinc-400" colSpan={5}>
                  No users found.
                </td>
              </tr>
            ) : null}
          </tbody>
        </table>
      </div>

      {/* Pagination */}
      {totalPages > 1 ? (
        <div className="flex items-center justify-between text-sm">
          <div className="text-zinc-500">
            Page {page} of {totalPages}
          </div>
          <div className="flex gap-2">
            {page > 1 ? (
              <Link
                href={`/users?page=${page - 1}${search ? `&q=${encodeURIComponent(search)}` : ""}`}
                className="rounded-lg border border-zinc-200 px-3 py-1.5 hover:bg-zinc-50 dark:border-zinc-800 dark:hover:bg-zinc-900"
              >
                Previous
              </Link>
            ) : null}
            {page < totalPages ? (
              <Link
                href={`/users?page=${page + 1}${search ? `&q=${encodeURIComponent(search)}` : ""}`}
                className="rounded-lg border border-zinc-200 px-3 py-1.5 hover:bg-zinc-50 dark:border-zinc-800 dark:hover:bg-zinc-900"
              >
                Next
              </Link>
            ) : null}
          </div>
        </div>
      ) : null}
    </div>
  );
}
