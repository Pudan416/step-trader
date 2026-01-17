import { countAuthUsers, countShields, sumEnergyDelta } from "@/lib/queries";

export const dynamic = "force-dynamic";

function StatCard({
  label,
  value,
  hint,
}: {
  label: string;
  value: string;
  hint?: string;
}) {
  return (
    <div className="rounded-2xl border border-zinc-200 bg-white p-5 dark:border-zinc-800 dark:bg-zinc-950">
      <div className="text-sm text-zinc-600 dark:text-zinc-400">{label}</div>
      <div className="mt-2 text-2xl font-semibold tracking-tight">{value}</div>
      {hint ? (
        <div className="mt-2 text-xs text-zinc-500 dark:text-zinc-500">{hint}</div>
      ) : null}
    </div>
  );
}

export default async function DashboardPage() {
  let usersTotal: number | null = null;
  let shieldsTotal: number | null = null;
  let energy: { total: number; rowsScanned: number } | null = null;
  let error: string | null = null;

  try {
    [usersTotal, shieldsTotal, energy] = await Promise.all([
      countAuthUsers(),
      countShields(),
      sumEnergyDelta(),
    ]);
  } catch (e: any) {
    error = String(e?.message ?? e);
  }

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-xl font-semibold tracking-tight">Dashboard</h1>
        <p className="mt-1 text-sm text-zinc-600 dark:text-zinc-400">
          Global stats aggregated from Supabase.
        </p>
      </div>

      {error ? (
        <div className="rounded-2xl border border-red-200 bg-red-50 p-4 text-sm text-red-800 dark:border-red-900/60 dark:bg-red-950/40 dark:text-red-200">
          <div className="font-medium">Failed to load stats</div>
          <div className="mt-1 font-mono text-xs">{error}</div>
          <div className="mt-2 text-xs">
            Check <code className="font-mono">/api/health</code> for details.
          </div>
        </div>
      ) : null}

      <div className="grid gap-4 md:grid-cols-3">
        <StatCard label="Total users" value={usersTotal === null ? "—" : String(usersTotal)} />
        <StatCard label="Total shields" value={shieldsTotal === null ? "—" : String(shieldsTotal)} />
        <StatCard
          label="Total granted energy (sum of energy_ledger.delta)"
          value={energy === null ? "—" : String(energy.total)}
          hint={energy === null ? undefined : `Rows scanned: ${energy.rowsScanned.toLocaleString()}`}
        />
      </div>
    </div>
  );
}

