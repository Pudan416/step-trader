import { supabaseAdmin } from "./supabaseAdmin";
import type { PublicUserRow, ShieldRow, UserPrefsRow } from "./types";

const HARD_ROW_LIMIT = 200_000;

export async function listPublicUsers(params: {
  limit?: number;
  offset?: number;
  search?: string;
}): Promise<{ rows: PublicUserRow[]; total: number }> {
  const limit = params.limit ?? 50;
  const offset = params.offset ?? 0;
  const sb = supabaseAdmin();
  let q = sb
    .from("users")
    .select("id,email,nickname,country,created_at,is_banned,ban_reason,ban_until", {
      count: "exact",
    })
    .order("created_at", { ascending: false })
    .range(offset, offset + limit - 1);

  if (params.search?.trim()) {
    const raw = params.search.trim();
    // Escape PostgREST special chars to prevent filter injection
    const s = raw.replace(/[%_,()\\]/g, (ch) => `\\${ch}`);
    // Only use UUID-format strings for id.eq to avoid malformed filter
    const isUUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(raw);
    const filters = [`nickname.ilike.%${s}%`, `email.ilike.%${s}%`];
    if (isUUID) filters.push(`id.eq.${raw}`);
    q = q.or(filters.join(","));
  }

  const { data, error, count } = await q;
  if (error) throw error;
  return { rows: (data ?? []) as PublicUserRow[], total: count ?? 0 };
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

export async function getUserPrefs(userId: string): Promise<UserPrefsRow | null> {
  const sb = supabaseAdmin();
  const { data, error } = await sb
    .from("user_preferences")
    .select("user_id,last_opened_at,has_medium_widget,has_large_widget")
    .eq("user_id", userId)
    .maybeSingle();
  if (error) throw error;
  return (data ?? null) as UserPrefsRow | null;
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

// MARK: - Write Operations

export async function banUser(
  userId: string,
  reason: string,
  banUntil?: string
): Promise<void> {
  const sb = supabaseAdmin();
  const { error } = await sb
    .from("users")
    .update({
      is_banned: true,
      ban_reason: reason,
      ban_until: banUntil ?? null,
    })
    .eq("id", userId);
  if (error) throw error;
}

export async function unbanUser(userId: string): Promise<void> {
  const sb = supabaseAdmin();
  const { error } = await sb
    .from("users")
    .update({
      is_banned: false,
      ban_reason: null,
      ban_until: null,
    })
    .eq("id", userId);
  if (error) throw error;
}

