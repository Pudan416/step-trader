import { pick, range } from './random.ts';
import type { MaterialFamily, PaletteRoles } from './types.ts';

type Oklch = { l: number; c: number; h: number };

function clamp01(value: number): number {
  return Math.max(0, Math.min(1, value));
}

function linearToSrgb(value: number): number {
  const channel = clamp01(value);
  return channel <= 0.0031308
    ? channel * 12.92
    : 1.055 * channel ** (1 / 2.4) - 0.055;
}

function oklchToHex({ l, c, h }: Oklch): string {
  const radians = (h * Math.PI) / 180;
  const a = c * Math.cos(radians);
  const b = c * Math.sin(radians);
  const l1 = l + 0.3963377774 * a + 0.2158037573 * b;
  const m1 = l - 0.1055613458 * a - 0.0638541728 * b;
  const s1 = l - 0.0894841775 * a - 1.291485548 * b;
  const ll = l1 ** 3;
  const mm = m1 ** 3;
  const ss = s1 ** 3;
  const red = linearToSrgb(
    4.0767416621 * ll - 3.3077115913 * mm + 0.2309699292 * ss,
  );
  const green = linearToSrgb(
    -1.2684380046 * ll + 2.6097574011 * mm - 0.3413193965 * ss,
  );
  const blue = linearToSrgb(
    -0.0041960863 * ll - 0.7034186147 * mm + 1.707614701 * ss,
  );
  return `#${[red, green, blue]
    .map((channel) =>
      Math.round(channel * 255)
        .toString(16)
        .padStart(2, '0'),
    )
    .join('')}`;
}

function parseHex(hex: string): [number, number, number] {
  return [1, 3, 5].map(
    (index) => Number.parseInt(hex.slice(index, index + 2), 16) / 255,
  ) as [number, number, number];
}

export function relativeLuminance(hex: string): number {
  const [red, green, blue] = parseHex(hex).map((channel) =>
    channel <= 0.04045 ? channel / 12.92 : ((channel + 0.055) / 1.055) ** 2.4,
  );
  return 0.2126 * red + 0.7152 * green + 0.0722 * blue;
}

export function makePalette(
  random: () => number,
  material: MaterialFamily,
): PaletteRoles {
  const base = range(random, 0, 360);
  const harmony = pick(random, [
    'analogous',
    'split',
    'temperature',
    'mono',
  ] as const);
  const accentOffset =
    harmony === 'analogous'
      ? range(random, 28, 64)
      : harmony === 'split'
        ? range(random, 132, 178)
        : harmony === 'temperature'
          ? range(random, 175, 215)
          : range(random, -14, 14);
  const accentHue = (base + accentOffset + 360) % 360;
  const quietChroma =
    material === 'metal' ? 0.025 : material === 'ink' ? 0.045 : 0.075;
  const accentChroma =
    material === 'metal'
      ? 0.08
      : material === 'glass'
        ? 0.13
        : range(random, 0.15, 0.235);
  const background = oklchToHex({
    l: range(random, 0.055, 0.13),
    c: quietChroma * 0.45,
    h: base,
  });
  const dark = oklchToHex({
    l: range(random, 0.19, 0.31),
    c: quietChroma,
    h: base,
  });
  let light = oklchToHex({
    l: range(random, 0.78, 0.91),
    c: material === 'metal' ? 0.025 : 0.07,
    h: (base + 18) % 360,
  });
  if (relativeLuminance(light) - relativeLuminance(background) < 0.36) {
    light = oklchToHex({ l: 0.92, c: 0.035, h: base });
  }
  return {
    background,
    dark,
    light,
    accent: oklchToHex({
      l: material === 'plasma' ? 0.73 : 0.66,
      c: accentChroma,
      h: accentHue,
    }),
    emission: oklchToHex({
      l: material === 'plasma' ? 0.86 : 0.76,
      c: Math.min(0.19, accentChroma),
      h: (accentHue + 35) % 360,
    }),
  };
}
