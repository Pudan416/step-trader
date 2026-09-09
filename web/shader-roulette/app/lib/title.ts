import type {
  GeometryFamily,
  MaterialFamily,
  VisualGenome,
} from './generative/types.ts';

const NOUNS: Record<GeometryFamily, readonly string[]> = {
  organism: ['Creature', 'Bloom', 'Organ', 'Pulse', 'Molt', 'Cell'],
  relic: ['Relic', 'Monument', 'Idol', 'Artifact', 'Vault', 'Monolith'],
  ribbon: ['Fold', 'Ribbon', 'Knot', 'Loop', 'Current', 'Tendon'],
  glyph: ['Glyph', 'Mark', 'Sigil', 'Letter', 'Cipher', 'Rune'],
  field: ['Veil', 'Weather', 'Field', 'Mist', 'Static', 'Aurora'],
  constellation: ['Orbit', 'Kinship', 'System', 'Choir', 'Cluster', 'Assembly'],
};

const ADJECTIVES: Record<MaterialFamily, readonly string[]> = {
  matte: ['Quiet', 'Earthen', 'Tender', 'Chalk', 'Blind'],
  glass: ['Lucid', 'Liquid', 'Clear', 'Fragile', 'Frozen'],
  film: ['Oilskin', 'Prismatic', 'Thin', 'Spectral', 'Peacock'],
  plasma: ['Electric', 'Solar', 'Hot', 'Radiant', 'Charged'],
  metal: ['Mercury', 'Silver', 'Burnished', 'Cold', 'Forged'],
  ink: ['Saturated', 'Printed', 'Wet', 'Dyed', 'Soft'],
  contour: ['Hollow', 'Outlined', 'Open', 'Interrupted', 'Negative'],
};

function mix(value: number): number {
  let result = value >>> 0;
  result ^= result >>> 16;
  result = Math.imul(result, 0x7feb352d);
  result ^= result >>> 15;
  result = Math.imul(result, 0x846ca68b);
  return (result ^ (result >>> 16)) >>> 0;
}

export function titleForGenome(genome: VisualGenome): string {
  const hash = mix(genome.seed ^ (genome.params.lobes << 16));
  const adjective =
    ADJECTIVES[genome.material][hash % ADJECTIVES[genome.material].length]!;
  const nouns = NOUNS[genome.geometry];
  const noun = nouns[(hash >>> 8) % nouns.length]!;
  const suffix = (genome.seed & 0xffff)
    .toString(16)
    .toUpperCase()
    .padStart(4, '0');
  return `${adjective} ${noun} #${suffix}`;
}
