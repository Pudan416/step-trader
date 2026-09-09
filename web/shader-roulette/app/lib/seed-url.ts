export function readSeed(search: string): number | null {
  const raw = new URLSearchParams(search).get('seed');
  if (!raw || !/^(?:0x[0-9a-f]{1,8}|[0-9]{1,10})$/i.test(raw)) return null;
  const value = Number.parseInt(
    raw,
    raw.toLowerCase().startsWith('0x') ? 16 : 10,
  );
  return Number.isSafeInteger(value) && value >= 0 && value <= 0xffffffff
    ? value
    : null;
}

export function seedHref(seed: number, base: URL): string {
  const url = new URL(base.toString());
  url.search = '';
  url.hash = '';
  url.searchParams.set(
    'seed',
    `0x${(seed >>> 0).toString(16).toUpperCase().padStart(8, '0')}`,
  );
  return url.toString();
}

export function newRandomSeed(): number {
  const values = new Uint32Array(1);
  globalThis.crypto.getRandomValues(values);
  return values[0]!;
}
