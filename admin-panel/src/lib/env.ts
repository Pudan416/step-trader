export function requireEnv(name: string): string {
  const v = process.env[name];
  if (!v) throw new Error(`Missing required env var: ${name}`);
  return v;
}

export function getSupabaseEnv() {
  return {
    url: requireEnv("SUPABASE_URL"),
    serviceRoleKey: requireEnv("SUPABASE_SERVICE_ROLE_KEY"),
  };
}

export function getAdminPassword(): string {
  return requireEnv("ADMIN_PASSWORD");
}

