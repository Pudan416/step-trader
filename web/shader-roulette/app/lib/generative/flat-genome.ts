import { generateGenome } from './genome.ts';
import { integer, mulberry32, normalizeSeed, pick, range } from './random.ts';
import type { FlatFamily, PaletteRoles, VisualGenome } from './types.ts';

export const FLAT_FAMILIES: readonly FlatFamily[] = ['rosette', 'spark', 'organism', 'loop', 'crescent', 'emblem', 'fan', 'ribbon'];
export const FAMILY_LABELS: Record<FlatFamily, string> = {
  rosette: 'Розетка', spark: 'Искра', organism: 'Органика', loop: 'Петля',
  crescent: 'Серп', emblem: 'Эмблема', fan: 'Веер', ribbon: 'Лента',
};
const COLORS = [
  ['#ff583d', '#ffd46b', '#eabfff'], ['#a4ee4a', '#efffb4', '#26ba85'],
  ['#a890ff', '#f4d6ff', '#6478ff'], ['#31c8f0', '#d2fdff', '#367dff'],
  ['#ff809c', '#ffdaae', '#ed4d5d'], ['#f4ede1', '#ffffff', '#9eb6cc'],
  ['#ffc336', '#fff3ac', '#ff773b'], ['#ff5ea8', '#ffcdea', '#cb72ff'],
] as const;

/** v2 only: v1 genomes are preserved so existing shared URLs keep their artwork. */
export function generateArtwork(value: number, variation = 0): VisualGenome {
  const seed = normalizeSeed(value);
  const base = mulberry32(seed);
  const family = pick(base, FLAT_FAMILIES);
  const colors = pick(base, COLORS);
  const palette: PaletteRoles = {
    background: '#090a0c', dark: colors[2], light: colors[1], accent: colors[0], emission: colors[2],
  };
  const material = pick(base, ['ink', 'ink', 'matte', 'film', 'contour'] as const);
  const rotation = range(base, -Math.PI, Math.PI);
  const lobes = integer(base, 3, family === 'spark' ? 12 : 8);
  const index = Math.max(0, Math.trunc(variation)) >>> 0;
  const random = mulberry32(seed ^ Math.imul(index + 1, 0x9e3779b9));
  const genome = generateGenome(seed);
  return {
    ...genome, seed, flat: {family, variation: index}, dimension: 'graphic', geometry: 'glyph', material, palette,
    params: {
      ...genome.params, scale: range(random, .88, .98), rotation: rotation + range(random, -.12, .12),
      lobes, warp: range(random, .12, .65), hollow: range(random, .04, .23),
      thickness: range(random, .08, .17), satelliteCount: 0, bloom: 0, grain: .035,
    },
    motion: {tempo: .28, breathe: .014, orbit: .035, phase: range(base, 0, Math.PI * 2)},
    rareMutation: [], title: `${FAMILY_LABELS[family]} ${seed.toString(16).toUpperCase().slice(-4).padStart(4, '0')}`,
  };
}
