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

export type Recipe = {
  seed: number;
  version: 1 | 2 | 3;
  variation: number;
  collection?: 'all' | 'new' | 'classic';
};

export function readRecipe(search: string): Recipe | null {
  const seed = readSeed(search);
  if (seed === null) return null;
  const query = new URLSearchParams(search);
  const version = query.get('v') === '3' ? 3 : query.get('v') === '2' ? 2 : 1;
  const raw = query.get('variation') ?? '0';
  const variation = /^\d{1,6}$/.test(raw) ? Number(raw) : 0;
  const collection = query.get('collection');
  return {
    seed,
    version,
    variation: version >= 2 ? variation : 0,
    ...(version === 3
      ? {
          collection:
            collection === 'new' || collection === 'classic'
              ? collection
              : ('all' as const),
        }
      : {}),
  };
}

export function recipeHref(recipe: Recipe, base: URL): string {
  const url = new URL(seedHref(recipe.seed, base));
  if (recipe.version >= 2) {
    url.searchParams.set('v', String(recipe.version));
    if (recipe.variation > 0)
      url.searchParams.set('variation', String(recipe.variation));
  }
  if (recipe.version === 3 && recipe.collection && recipe.collection !== 'all')
    url.searchParams.set('collection', recipe.collection);
  return url.toString();
}
