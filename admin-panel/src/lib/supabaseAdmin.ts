import { createClient } from "@supabase/supabase-js";
import { getSupabaseEnv } from "./env";

export function supabaseAdmin() {
  const { url, serviceRoleKey } = getSupabaseEnv();
  return createClient(url, serviceRoleKey, {
    db: {
      schema: "public",
    },
    auth: {
      persistSession: false,
      autoRefreshToken: false,
      detectSessionInUrl: false,
    },
  });
}

