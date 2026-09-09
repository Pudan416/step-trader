import { integer, mulberry32, normalizeSeed, pick, range } from './random.ts';
import { makePalette } from './color.ts';
import type {
  DimensionMode,
  GeometryFamily,
  MaterialFamily,
  PaletteRoles,
  RareMutation,
  VisualGenome,
} from './types.ts';

export { normalizeSeed } from './random.ts';
export type { VisualGenome } from './types.ts';

const GEOMETRIES: readonly GeometryFamily[] = [
  'organism',
  'relic',
  'ribbon',
  'glyph',
  'field',
  'constellation',
];

const DIMENSIONS: Record<GeometryFamily, readonly DimensionMode[]> = {
  organism: ['volumetric', 'volumetric', 'hybrid'],
  relic: ['volumetric', 'hybrid'],
  ribbon: ['volumetric', 'hybrid', 'graphic'],
  glyph: ['graphic', 'graphic', 'hybrid'],
  field: ['graphic', 'hybrid'],
  constellation: ['volumetric', 'hybrid', 'graphic'],
};

const MATERIALS: Record<GeometryFamily, readonly MaterialFamily[]> = {
  organism: ['matte', 'glass', 'film', 'plasma'],
  relic: ['matte', 'metal', 'glass', 'film'],
  ribbon: ['film', 'metal', 'ink', 'contour'],
  glyph: ['ink', 'contour', 'metal', 'plasma'],
  field: ['plasma', 'ink', 'film', 'contour'],
  constellation: ['glass', 'metal', 'plasma', 'matte'],
};

const MUTATIONS: readonly RareMutation[] = [
  'slice',
  'hollow-core',
  'chromatic-edge',
  'satellite',
  'flatland',
];

const SAFE_PALETTE: PaletteRoles = {
  background: '#08090b',
  dark: '#182126',
  light: '#e8ded0',
  accent: '#e7724b',
  emission: '#a9d8dc',
};

function title(seed: number, geometry: GeometryFamily): string {
  const label = geometry[0]!.toUpperCase() + geometry.slice(1);
  return `${label} #${(seed & 0xffff).toString(16).toUpperCase().padStart(4, '0')}`;
}

function candidate(seed: number): VisualGenome {
  const random = mulberry32(seed);
  const geometry = pick(random, GEOMETRIES);
  const dimension = pick(random, DIMENSIONS[geometry]);
  const material = pick(random, MATERIALS[geometry]);
  const hasMutation = random() < 0.17;
  const rareMutation: [] | [RareMutation] = hasMutation
    ? [pick(random, MUTATIONS)]
    : [];
  const complex = geometry === 'constellation' || geometry === 'ribbon';
  const transparent = material === 'glass' || material === 'film';

  return {
    seed: normalizeSeed(seed),
    dimension,
    geometry,
    material,
    palette: makePalette(random, material),
    params: {
      scale: range(random, 0.68, 1.12),
      rotation: range(random, -Math.PI, Math.PI),
      lobes: integer(random, 3, complex ? 7 : 9),
      warp: range(random, 0.08, complex ? 0.48 : 0.66),
      hollow:
        rareMutation[0] === 'hollow-core'
          ? range(random, 0.28, 0.62)
          : range(random, 0, 0.19),
      thickness: range(random, 0.07, complex ? 0.2 : 0.3),
      roughness: range(
        random,
        material === 'metal' ? 0.14 : 0.24,
        material === 'glass' ? 0.38 : 0.84,
      ),
      metallic:
        material === 'metal'
          ? range(random, 0.72, 0.96)
          : range(random, 0, 0.18),
      transmission: transparent
        ? range(random, 0.55, 0.92)
        : range(random, 0, 0.12),
      bloom:
        material === 'plasma'
          ? range(random, 0.28, 0.52)
          : range(random, 0.02, 0.22),
      grain: range(random, 0.03, 0.18),
      cameraZ: range(random, 2.65, 4.35),
      satelliteCount:
        geometry === 'constellation'
          ? integer(random, 2, 4)
          : rareMutation[0] === 'satellite'
            ? 1
            : 0,
    },
    motion: {
      tempo: range(random, 0.05, 0.19),
      breathe: range(random, 0.008, 0.055),
      orbit: range(random, 0.015, 0.11),
      phase: range(random, 0, Math.PI * 2),
    },
    rareMutation,
    title: title(seed, geometry),
  };
}

function contrastProxy(palette: PaletteRoles): number {
  const channels = [1, 3, 5].map((index) =>
    Number.parseInt(palette.light.slice(index, index + 2), 16),
  );
  return Math.max(...channels) / 255;
}

function qualityScore(genome: VisualGenome): number {
  const occupied = genome.params.scale / 1.4;
  const complexity =
    (genome.params.lobes + genome.params.satelliteCount * 2) / 18;
  const contrast = contrastProxy(genome.palette);
  const effects =
    genome.params.bloom +
    genome.params.transmission * 0.25 +
    genome.params.warp * 0.18;
  return (
    occupied * 0.32 +
    complexity * 0.18 +
    contrast * 0.3 +
    Math.min(effects, 0.75) * 0.2
  );
}

export function isGenomeValid(genome: VisualGenome): boolean {
  const finiteValues = [
    ...Object.values(genome.params),
    ...Object.values(genome.motion),
  ].every(Number.isFinite);
  const score = qualityScore(genome);
  return (
    finiteValues &&
    GEOMETRIES.includes(genome.geometry) &&
    MATERIALS[genome.geometry].includes(genome.material) &&
    DIMENSIONS[genome.geometry].includes(genome.dimension) &&
    genome.params.scale >= 0.62 &&
    genome.params.scale <= 1.18 &&
    genome.params.warp >= 0.04 &&
    genome.params.warp <= 0.72 &&
    genome.params.hollow >= 0 &&
    genome.params.hollow <= 0.68 &&
    genome.params.thickness >= 0.04 &&
    genome.params.thickness <= 0.34 &&
    genome.params.roughness >= 0.08 &&
    genome.params.roughness <= 0.92 &&
    genome.params.bloom >= 0 &&
    genome.params.bloom <= 0.55 &&
    genome.params.cameraZ >= 2.4 &&
    genome.params.cameraZ <= 4.8 &&
    genome.params.satelliteCount >= 0 &&
    genome.params.satelliteCount <= 4 &&
    genome.motion.tempo >= 0.045 &&
    genome.motion.tempo <= 0.22 &&
    genome.rareMutation.length <= 1 &&
    score >= 0.28 &&
    score <= 0.82
  );
}

export function generateGenome(value: number): VisualGenome {
  const seed = normalizeSeed(value);
  for (let attempt = 0; attempt < 6; attempt += 1) {
    const mixed = normalizeSeed(seed + Math.imul(attempt, 0x9e3779b9));
    const genome = candidate(mixed);
    genome.seed = seed;
    genome.title = title(seed, genome.geometry);
    if (isGenomeValid(genome)) return genome;
  }

  return {
    ...candidate(seed),
    seed,
    geometry: 'organism',
    dimension: 'volumetric',
    material: 'matte',
    palette: SAFE_PALETTE,
    rareMutation: [],
    title: title(seed, 'organism'),
  };
}
