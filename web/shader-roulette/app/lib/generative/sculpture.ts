import { generateGenome } from './genome.ts';
import { integer, mulberry32, normalizeSeed, pick, range } from './random.ts';
import type { Collection, MaterialFamily, VisualGenome } from './types.ts';

const TAU = Math.PI * 2;
const PALETTES = [
  ['#162631', '#b9d9e1', '#67aeb1'],
  ['#261b38', '#f2d4ed', '#937ba9'],
  ['#312b1d', '#f3deb0', '#c09659'],
  ['#241c21', '#f6cbc1', '#cb8581'],
  ['#1e2636', '#d5e0f5', '#7094d3'],
  ['#242729', '#ece9de', '#b6c3bd'],
  ['#172a26', '#d2e8b7', '#8ab696'],
  ['#361c21', '#ffd4b0', '#c35a42'],
] as const;
const NOUNS = [
  'Undertow',
  'Continuum',
  'Vesper',
  'Undulation',
  'Confluence',
  'Nautilus',
  'Interlace',
  'Aperture',
  'Aeolian',
  'Mantle',
  'Obsidian',
  'Elytra',
];
const FINISHES: Record<string, string> = {
  metal: 'Ртуть',
  film: 'Перламутр',
  glass: 'Стекло',
  matte: 'Сатин',
  plasma: 'Свечение',
};
export function finishLabel(g: VisualGenome): string {
  return FINISHES[g.material] ?? g.material;
}

/** Closed curves, variable sections, folds and over/under depth are independent recipe axes. */
export function generateSculpture(value: number, variation = 0): VisualGenome {
  const seed = normalizeSeed(value),
    r = mulberry32(seed ^ 0x3e7a194b);
  const model = integer(r, 0, 11),
    frequency = integer(r, 2, 6),
    secondary = integer(r, 2, 5);
  const colors = pick(r, PALETTES);
  const material = pick<MaterialFamily>(r, [
    'metal',
    'film',
    'film',
    'glass',
    'matte',
    'metal',
  ]);
  const section = pick(r, [0, 0.35, 0.8, 1]);
  const folds = integer(r, 2, 8),
    etching = pick(r, [0, 0, range(r, 0.3, 0.8)]);
  const phase = range(r, 0, TAU),
    rotation = range(r, -Math.PI, Math.PI);
  const v = mulberry32(seed ^ Math.imul(variation + 1, 0x85ebca6b));
  const a = range(v, 0.18, 0.55),
    b = range(v, 0.12, 0.4),
    aspect = range(v, 0.76, 1.12);
  const width = range(v, 0.12, 0.24),
    twist = range(v, 0.25, 1.05),
    relief = range(v, 0.45, 0.95);
  const raw: number[] = [];
  for (let i = 0; i <= 128; i++) {
    const t = (i / 128) * TAU,
      c = Math.cos(t),
      s = Math.sin(t);
    let x = 0,
      y = 0,
      z = 0.12 * Math.sin(t * frequency + phase);
    if (model === 0) {
      // A rolling wave closing around its own centre.
      const rad = 0.64 + a * Math.cos(frequency * t + phase) * 0.5;
      x = rad * c + b * 0.22 * Math.sin(2 * t);
      y = rad * s * aspect;
    } else if (model === 1) {
      // Projected torus knot: crossings carry independent heights.
      const p = 2,
        q = pick(mulberry32(seed), [3, 5]);
      const rad = 0.5 + a * 0.55 * Math.cos(q * t);
      x = rad * Math.cos(p * t);
      y = rad * Math.sin(p * t) * aspect;
      z = 0.22 * Math.sin(q * t);
    } else if (model === 2) {
      // Superelliptic aperture, bent by a second harmonic.
      const power = range(mulberry32(seed + 17), 0.5, 1.7);
      x =
        0.64 * Math.sign(c) * Math.abs(c) ** power +
        a * 0.18 * Math.sin(3 * t + phase);
      y =
        0.6 * Math.sign(s) * Math.abs(s) ** power +
        b * 0.2 * Math.cos(2 * t + phase);
    } else if (model === 3) {
      // A broad, asymmetric wave with an internal return.
      x = 0.58 * c + a * 0.6 * Math.sin(2 * t + phase);
      y = 0.58 * s + b * 0.65 * Math.cos(3 * t);
      z = 0.2 * Math.sin(2 * t + phase);
    } else if (model === 4) {
      // Hypotrochoid: cusps become folds rather than detached strokes.
      x = 0.56 * c + a * 0.65 * Math.cos((frequency - 1) * t + phase);
      y = 0.56 * s - a * 0.65 * Math.sin((frequency - 1) * t + phase);
      z = 0.15 * Math.sin(frequency * t);
    } else if (model === 5) {
      // A coiled shell; the end caps close the silhouette.
      const u = i / 128,
        angle = u * TAU * (1.35 + a),
        rad = 0.11 + 0.61 * u;
      x = rad * Math.cos(angle);
      y = rad * Math.sin(angle) * aspect;
      z = 0.12 * (1 - u);
    } else if (model === 6) {
      // Two crossing rhythms form one continuous woven object.
      x = 0.64 * Math.sin(2 * t) + b * 0.2 * Math.cos(3 * t);
      y = 0.58 * Math.sin(3 * t + phase * 0.15);
      z = 0.2 * Math.cos(t + phase);
    } else {
      // Folded limacon; continuous modulation produces both open and pinched cores.
      const rad =
        0.46 + 0.38 * Math.cos(t) + a * 0.12 * Math.sin(secondary * t);
      x = rad * c - 0.14;
      y = rad * s * 1.2;
      z = 0.15 * Math.sin(2 * t);
    }
    // Width and local tilt evolve around the entire object, rather than repeating one primitive.
    const taper = 0.78 + 0.22 * Math.cos(t * secondary + phase);
    const tube = model === 5 ? width * (1.1 - (0.42 * i) / 128) : width * taper;
    raw.push(x, y, tube, z);
  }
  // Centre the full silhouette, including the thickest edge, then fit its enclosing disc.
  let minX = Infinity,
    minY = Infinity,
    maxX = -Infinity,
    maxY = -Infinity;
  for (let i = 0; i < raw.length; i += 4) {
    const [x, y, w] = raw.slice(i, i + 3);
    minX = Math.min(minX, x! - w!);
    maxX = Math.max(maxX, x! + w!);
    minY = Math.min(minY, y! - w!);
    maxY = Math.max(maxY, y! + w!);
  }
  const cx = (minX + maxX) / 2,
    cy = (minY + maxY) / 2;
  let radius = 0;
  for (let i = 0; i < raw.length; i += 4)
    radius = Math.max(
      radius,
      Math.hypot(raw[i]! - cx, raw[i + 1]! - cy) + raw[i + 2]!,
    );
  const fit = 0.84 / radius;
  const points = raw.map((value, i) =>
    i % 4 === 0
      ? (value - cx) * fit
      : i % 4 === 1
        ? (value - cy) * fit
        : value * fit,
  );
  const legacy = generateGenome(seed);
  return {
    ...legacy,
    seed,
    identity: `3-new-${seed}-${variation}`,
    dimension: 'hybrid',
    geometry: 'ribbon',
    material,
    palette: {
      background: '#090a0c',
      dark: colors[0],
      light: colors[1],
      accent: colors[2],
      emission: colors[2],
    },
    params: {
      ...legacy.params,
      scale: 0.95,
      rotation,
      lobes: frequency,
      warp: a,
      hollow: b,
      roughness: range(r, 0.18, 0.48),
      satelliteCount: 0,
      bloom: 0,
    },
    motion: { tempo: 0.16, breathe: 0.013, orbit: 0.07, phase },
    rareMutation: [],
    sculpture: { model, points, section, folds, twist, relief, etching },
    title: `${NOUNS[model]} #${seed.toString(16).toUpperCase().slice(-4).padStart(4, '0')}`,
  };
}

export function generateCollection(
  seed: number,
  variation = 0,
  collection: Collection = 'all',
): VisualGenome {
  const classic =
    collection === 'classic' ||
    (collection === 'all' && mulberry32(seed ^ 0xc671b39a)() < 0.25);
  if (!classic) return generateSculpture(seed, variation);
  const g = generateGenome(seed);
  if (!variation) return g;
  const v = mulberry32(seed ^ Math.imul(variation, 0x85ebca6b));
  return {
    ...g,
    identity: `3-classic-${seed}-${variation}`,
    params: {
      ...g.params,
      rotation: g.params.rotation + range(v, -0.4, 0.4),
      warp: range(v, 0.08, 0.6),
      thickness: range(v, 0.08, 0.25),
    },
  };
}
