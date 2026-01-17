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
  settings_json: unknown;
  updated_at: string | null;
};

export type EnergyLedgerRow = {
  id?: string;
  user_id: string;
  delta: number;
  created_at: string;
  reason?: string | null;
};

