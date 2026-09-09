export function normalizeSeed(value: string | number): number {
  const parsed = typeof value === 'number' ? value : Number(value);
  if (!Number.isFinite(parsed)) return 0;
  return Math.trunc(parsed) >>> 0;
}

export function mulberry32(seed: number): () => number {
  let state = normalizeSeed(seed);
  return () => {
    state = (state + 0x6d2b79f5) | 0;
    let value = Math.imul(state ^ (state >>> 15), 1 | state);
    value = (value + Math.imul(value ^ (value >>> 7), 61 | value)) ^ value;
    return ((value ^ (value >>> 14)) >>> 0) / 4294967296;
  };
}

export function range(random: () => number, min: number, max: number): number {
  return min + (max - min) * random();
}

export function integer(
  random: () => number,
  min: number,
  max: number,
): number {
  return Math.floor(range(random, min, max + 1));
}

export function pick<T>(random: () => number, values: readonly T[]): T {
  return values[
    Math.min(values.length - 1, Math.floor(random() * values.length))
  ]!;
}
