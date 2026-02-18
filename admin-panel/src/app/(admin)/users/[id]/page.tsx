import {
  banUser,
  countShields,
  getPublicUser,
  grantEnergy,
  listEnergyLedger,
  listShields,
  sumEnergyDelta,
  unbanUser,
} from "@/lib/queries";
import { notFound, redirect } from "next/navigation";

export const dynamic = "force-dynamic";

export default async function UserDetailPage({
  params,
  searchParams,
}: {
  params: Promise<{ id: string }>;
  searchParams: Promise<{ success?: string }>;
}) {
  const { id } = await params;
  const sp = await searchParams;
  const user = await getPublicUser(id);
  if (!user) notFound();

  const [shields, shieldCount, energySum, ledger] = await Promise.all([
    listShields(id),
    countShields(id),
    sumEnergyDelta(id),
    listEnergyLedger(id, 200),
  ]);

  // Server Actions
  async function handleBan(formData: FormData) {
    "use server";
    const reason = String(formData.get("reason") ?? "Admin action");
    const until = String(formData.get("until") ?? "");
    await banUser(id, reason, until || undefined);
    redirect(`/users/${id}?success=banned`);
  }

  async function handleUnban() {
    "use server";
    await unbanUser(id);
    redirect(`/users/${id}?success=unbanned`);
  }

  async function handleGrantEnergy(formData: FormData) {
    "use server";
    const delta = Number(formData.get("delta"));
    const reason = String(formData.get("reason") ?? "Admin grant");
    if (!delta || !Number.isFinite(delta)) return;
    await grantEnergy(id, delta, reason);
    redirect(`/users/${id}?success=energy_granted`);
  }

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-xl font-semibold tracking-tight">User</h1>
        <div className="mt-1 font-mono text-xs text-zinc-600 dark:text-zinc-400">{user.id}</div>
      </div>

      {sp.success ? (
        <div className="rounded-lg border border-green-200 bg-green-50 px-4 py-2 text-sm text-green-800 dark:border-green-900 dark:bg-green-950/40 dark:text-green-200">
          {sp.success === "banned" && "User banned."}
          {sp.success === "unbanned" && "User unbanned."}
          {sp.success === "energy_granted" && "Energy granted."}
        </div>
      ) : null}

      <div className="grid gap-4 md:grid-cols-3">
        <div className="rounded-2xl border border-zinc-200 bg-white p-5 dark:border-zinc-800 dark:bg-zinc-950">
          <div className="text-sm text-zinc-600 dark:text-zinc-400">Profile</div>
          <div className="mt-2 space-y-1 text-sm">
            <div>
              <span className="text-zinc-500">email:</span> {user.email ?? "—"}
            </div>
            <div>
              <span className="text-zinc-500">nickname:</span> {user.nickname ?? "—"}
            </div>
            <div>
              <span className="text-zinc-500">country:</span> {user.country ?? "—"}
            </div>
            <div>
              <span className="text-zinc-500">created:</span>{" "}
              {new Date(user.created_at).toLocaleString()}
            </div>
            <div>
              <span className="text-zinc-500">status:</span>{" "}
              {user.is_banned ? (
                <span className="text-red-600 dark:text-red-400">
                  banned{user.ban_reason ? ` — ${user.ban_reason}` : ""}
                </span>
              ) : (
                "ok"
              )}
            </div>
          </div>
        </div>

        <div className="rounded-2xl border border-zinc-200 bg-white p-5 dark:border-zinc-800 dark:bg-zinc-950">
          <div className="text-sm text-zinc-600 dark:text-zinc-400">Shields</div>
          <div className="mt-2 text-2xl font-semibold tracking-tight">{shieldCount}</div>
          <div className="mt-2 text-xs text-zinc-500 dark:text-zinc-500">
            Rows: {shields.length}
          </div>
        </div>

        <div className="rounded-2xl border border-zinc-200 bg-white p-5 dark:border-zinc-800 dark:bg-zinc-950">
          <div className="text-sm text-zinc-600 dark:text-zinc-400">Energy (ledger)</div>
          <div className="mt-2 text-2xl font-semibold tracking-tight">{energySum.total}</div>
          <div className="mt-2 text-xs text-zinc-500 dark:text-zinc-500">
            Rows scanned: {energySum.rowsScanned.toLocaleString()}
          </div>
        </div>
      </div>

      {/* Actions */}
      <div className="grid gap-4 md:grid-cols-2">
        {/* Ban / Unban */}
        <div className="rounded-2xl border border-zinc-200 bg-white p-5 dark:border-zinc-800 dark:bg-zinc-950">
          <div className="text-sm font-medium">Moderation</div>
          {user.is_banned ? (
            <form action={handleUnban} className="mt-3">
              <button
                type="submit"
                className="rounded-lg bg-green-600 px-4 py-2 text-sm font-medium text-white hover:bg-green-500"
              >
                Unban user
              </button>
            </form>
          ) : (
            <form action={handleBan} className="mt-3 space-y-2">
              <input
                name="reason"
                type="text"
                placeholder="Ban reason"
                required
                className="w-full rounded-lg border border-zinc-200 bg-white px-3 py-2 text-sm outline-none focus:border-zinc-400 dark:border-zinc-800 dark:bg-zinc-950"
              />
              <input
                name="until"
                type="datetime-local"
                className="w-full rounded-lg border border-zinc-200 bg-white px-3 py-2 text-sm outline-none focus:border-zinc-400 dark:border-zinc-800 dark:bg-zinc-950"
              />
              <div className="text-xs text-zinc-500">Leave date empty for permanent ban.</div>
              <button
                type="submit"
                className="rounded-lg bg-red-600 px-4 py-2 text-sm font-medium text-white hover:bg-red-500"
              >
                Ban user
              </button>
            </form>
          )}
        </div>

        {/* Grant Energy */}
        <div className="rounded-2xl border border-zinc-200 bg-white p-5 dark:border-zinc-800 dark:bg-zinc-950">
          <div className="text-sm font-medium">Grant Energy</div>
          <form action={handleGrantEnergy} className="mt-3 space-y-2">
            <input
              name="delta"
              type="number"
              placeholder="Amount (positive or negative)"
              required
              className="w-full rounded-lg border border-zinc-200 bg-white px-3 py-2 text-sm outline-none focus:border-zinc-400 dark:border-zinc-800 dark:bg-zinc-950"
            />
            <input
              name="reason"
              type="text"
              placeholder="Reason"
              defaultValue="Admin grant"
              className="w-full rounded-lg border border-zinc-200 bg-white px-3 py-2 text-sm outline-none focus:border-zinc-400 dark:border-zinc-800 dark:bg-zinc-950"
            />
            <button
              type="submit"
              className="rounded-lg bg-zinc-900 px-4 py-2 text-sm font-medium text-white hover:bg-zinc-800 dark:bg-zinc-50 dark:text-zinc-900 dark:hover:bg-zinc-200"
            >
              Grant
            </button>
          </form>
        </div>
      </div>

      <div className="grid gap-4 lg:grid-cols-2">
        <div className="overflow-hidden rounded-2xl border border-zinc-200 bg-white dark:border-zinc-800 dark:bg-zinc-950">
          <div className="border-b border-zinc-200 px-4 py-3 text-sm font-medium dark:border-zinc-800">
            Shields
          </div>
          <table className="w-full text-sm">
            <thead className="bg-zinc-50 text-left text-xs text-zinc-600 dark:bg-zinc-900/30 dark:text-zinc-400">
              <tr>
                <th className="px-4 py-3">bundle_id</th>
                <th className="px-4 py-3">mode</th>
                <th className="px-4 py-3">updated</th>
              </tr>
            </thead>
            <tbody>
              {shields.map((s) => (
                <tr key={s.id} className="border-t border-zinc-100 dark:border-zinc-900">
                  <td className="px-4 py-3 font-mono text-xs">{s.bundle_id}</td>
                  <td className="px-4 py-3">{s.mode}</td>
                  <td className="px-4 py-3">
                    {s.updated_at ? new Date(s.updated_at).toLocaleString() : "—"}
                  </td>
                </tr>
              ))}
              {shields.length === 0 ? (
                <tr>
                  <td className="px-4 py-6 text-zinc-600 dark:text-zinc-400" colSpan={4}>
                    No shields.
                  </td>
                </tr>
              ) : null}
            </tbody>
          </table>
        </div>

        <div className="overflow-hidden rounded-2xl border border-zinc-200 bg-white dark:border-zinc-800 dark:bg-zinc-950">
          <div className="border-b border-zinc-200 px-4 py-3 text-sm font-medium dark:border-zinc-800">
            Energy ledger (latest)
          </div>
          <table className="w-full text-sm">
            <thead className="bg-zinc-50 text-left text-xs text-zinc-600 dark:bg-zinc-900/30 dark:text-zinc-400">
              <tr>
                <th className="px-4 py-3">created_at</th>
                <th className="px-4 py-3">delta</th>
                <th className="px-4 py-3">reason</th>
              </tr>
            </thead>
            <tbody>
              {ledger.map((r, idx) => (
                <tr key={`${r.created_at}-${idx}`} className="border-t border-zinc-100 dark:border-zinc-900">
                  <td className="px-4 py-3">{new Date(r.created_at).toLocaleString()}</td>
                  <td className="px-4 py-3 font-mono">{r.delta}</td>
                  <td className="px-4 py-3">{r.reason ?? "—"}</td>
                </tr>
              ))}
              {ledger.length === 0 ? (
                <tr>
                  <td className="px-4 py-6 text-zinc-600 dark:text-zinc-400" colSpan={3}>
                    No ledger rows.
                  </td>
                </tr>
              ) : null}
            </tbody>
          </table>
        </div>
      </div>
    </div>
  );
}
