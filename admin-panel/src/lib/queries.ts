import { supabaseAdmin } from "./supabaseAdmin";
import type { EnergyLedgerRow, PublicUserRow, ShieldRow } from "./types";

const PAGE_SIZE = 1000;
const HARD_ROW_LIMIT = 200_000;

export async function listPublicUsers(params: {
  limit?: number;
  offset?: number;
}): Promise<PublicUserRow[]> {
  const limit = params.limit ?? 50;
  const offset = params.offset ?? 0;
  const sb = supabaseAdmin();
  const { data, error } = await sb
    .from("users")
    .select("id,email,nickname,country,created_at,is_banned,ban_reason,ban_until")
    .order("created_at", { ascending: false })
    .range(offset, offset + limit - 1);
  if (error) throw error;
  return (data ?? []) as PublicUserRow[];
}

export async function getPublicUser(userId: string): Promise<PublicUserRow | null> {
  const sb = supabaseAdmin();
  const { data, error } = await sb
    .from("users")
    .select("id,email,nickname,country,created_at,is_banned,ban_reason,ban_until")
    .eq("id", userId)
    .maybeSingle();
  if (error) throw error;
  return (data ?? null) as PublicUserRow | null;
}

export async function listShields(userId: string): Promise<ShieldRow[]> {
  const sb = supabaseAdmin();
  const { data, error } = await sb
    .from("shields")
    .select("id,user_id,bundle_id,mode,level,settings_json,updated_at")
    .eq("user_id", userId)
    .order("updated_at", { ascending: false });
  if (error) throw error;
  return (data ?? []) as ShieldRow[];
}

export async function countShields(userId?: string): Promise<number> {
  const sb = supabaseAdmin();
  const q = sb.from("shields").select("id", { count: "exact", head: true });
  const { count, error } = userId ? await q.eq("user_id", userId) : await q;
  if (error) throw error;
  if (typeof count === "number") return count;
  // Fallback: some proxies/backends may not return count headers reliably.
  const { data, error: e2 } = userId
    ? await sb.from("shields").select("id").eq("user_id", userId).limit(10_000)
    : await sb.from("shields").select("id").limit(10_000);
  if (e2) throw e2;
  return (data ?? []).length;
}

export async function sumEnergyDelta(userId?: string): Promise<{ total: number; rowsScanned: number }> {
  const sb = supabaseAdmin();
  let offset = 0;
  let total = 0;
  let scanned = 0;

  while (true) {
    const q = sb
      .from("energy_ledger")
      .select("delta", { count: "exact" })
      .order("created_at", { ascending: false })
      .range(offset, offset + PAGE_SIZE - 1);
    const { data, error } = userId ? await q.eq("user_id", userId) : await q;
    if (error) throw error;

    const rows = (data ?? []) as Array<{ delta: number }>;
    if (rows.length === 0) break;
    total += rows.reduce((acc, r) => acc + (r.delta ?? 0), 0);
    scanned += rows.length;

    if (rows.length < PAGE_SIZE) break;
    offset += PAGE_SIZE;
    if (offset > HARD_ROW_LIMIT) break;
  }

  return { total, rowsScanned: scanned };
}

export async function listEnergyLedger(userId: string, limit = 200): Promise<EnergyLedgerRow[]> {
  const sb = supabaseAdmin();
  const { data, error } = await sb
    .from("energy_ledger")
    .select("user_id,delta,created_at,reason")
    .eq("user_id", userId)
    .order("created_at", { ascending: false })
    .limit(limit);
  if (error) throw error;
  return (data ?? []) as EnergyLedgerRow[];
}

export async function countAuthUsers(): Promise<number> {
  const sb = supabaseAdmin();
  // supabase-js admin listUsers is paginated; we count by iterating pages.
  let page = 1;
  const perPage = 1000;
  let total = 0;
  while (true) {
    const { data, error } = await sb.auth.admin.listUsers({ page, perPage });
    if (error) throw error;
    const users = data?.users ?? [];
    total += users.length;
    if (users.length < perPage) break;
    page += 1;
    if (page * perPage > HARD_ROW_LIMIT) break;
  }
  return total;
}

