// Shared Supabase row types — keep in sync with admin-panel/src/lib/types.ts

export type PublicUserRow = {
  id: string;
  email: string | null;
  nickname: string | null;
  country: string | null;
  created_at: string;
  is_banned: boolean;
  ban_reason: string | null;
  ban_until: string | null;
};

export type ShieldRow = {
  id: string;
  user_id: string;
  bundle_id: string;
  mode: string;
  level: number;
  settings_json?: unknown;
  updated_at: string | null;
};

