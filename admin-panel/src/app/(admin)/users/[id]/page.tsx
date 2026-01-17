import { countShields, getPublicUser, listEnergyLedger, listShields, sumEnergyDelta } from "@/lib/queries";
import { notFound } from "next/navigation";

export const dynamic = "force-dynamic";

function normalizeMode(raw: string) {
  if (raw === "minute") return "entry";
  if (raw === "entry") return "minute";
  return raw;
}

export default async function UserDetailPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const user = await getPublicUser(id);
  if (!user) notFound();

  const [shields, shieldCount, energySum, ledger] = await Promise.all([
    listShields(id),
    countShields(id),
    sumEnergyDelta(id),
    listEnergyLedger(id, 200),
  ]);

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-xl font-semibold tracking-tight">User</h1>
        <div className="mt-1 font-mono text-xs text-zinc-600 dark:text-zinc-400">{user.id}</div>
      </div>

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
              {user.is_banned ? "banned" : "ok"}
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
                <th className="px-4 py-3">level</th>
                <th className="px-4 py-3">updated</th>
              </tr>
            </thead>
            <tbody>
              {shields.map((s) => (
                <tr key={s.id} className="border-t border-zinc-100 dark:border-zinc-900">
                  <td className="px-4 py-3 font-mono text-xs">{s.bundle_id}</td>
                  <td className="px-4 py-3">{normalizeMode(s.mode)}</td>
                  <td className="px-4 py-3">{s.level}</td>
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
                  <td className="px-4 py-3">{(r as any).reason ?? "—"}</td>
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
