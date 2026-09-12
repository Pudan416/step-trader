import type { VisualGenome } from '../generative/types.ts';
import { membraneDistances } from './membranes.generated.ts';

const TAU = Math.PI * 2;
const clamp = (v: number, a = 0, b = 1) => Math.max(a, Math.min(b, v));
function smooth(a: number, b: number, x: number) {
  const t = clamp((x - a) / (b - a));
  return t * t * (3 - 2 * t);
}
const distanceFunctions = Object.values(membraneDistances);
function profile(q: number, along: number, g: VisualGenome) {
  const s = g.sculpture!,
    inside = Math.max(1 - q * q, 0.0001);
  const ridge = Math.sin(along * TAU * s.folds + q * 2);
  return (
    Math.sqrt(inside) * (1 - s.section) +
    inside ** 0.26 * s.section +
    s.twist * q * ridge * 0.42 +
    inside * ridge * 0.07
  );
}
function height(x: number, y: number, g: VisualGenome) {
  const r = Math.hypot(x, y),
    a = Math.atan2(y, x),
    f = g.params.lobes,
    phase = (g.seed % 65521) * 0.002;
  switch (g.sculpture!.model) {
    case 8:
      return (
        0.16 *
          Math.sin(a * f + r * (10 + g.params.warp * 14) + phase) *
          (1 - r * 0.7) +
        0.09 * Math.cos(a * 2)
      );
    case 9:
      return (
        0.22 * Math.sqrt(Math.max(1 - r * r * 1.7, 0.001)) +
        0.052 * Math.sin(a * (f + 5) + r * 4 + phase) * smooth(0.08, 0.6, r)
      );
    case 10:
      return (
        0.28 -
        Math.max(Math.abs(x * 0.8 + y * 0.5), Math.abs(y * 0.85 - x * 0.22)) *
          0.4 +
        0.08 * Math.sin(x * 4 + y * 3 + phase)
      );
    default:
      return (
        0.16 * Math.cos(x * 5 + y * 3 + phase) +
        0.06 * Math.sin(a * f + r * 8) * smooth(0.1, 0.7, r)
      );
  }
}
function rgb(hex: string) {
  return [1, 3, 5].map((i) => {
    const c = parseInt(hex.slice(i, i + 2), 16) / 255;
    return c <= 0.04045 ? c / 12.92 : ((c + 0.055) / 1.055) ** 2.4;
  });
}
function srgb(c: number) {
  return Math.round(
    clamp(
      c <= 0.0031308 ? 12.92 * c : 1.055 * Math.max(c, 0) ** (1 / 2.4) - 0.055,
    ) * 255,
  );
}

/** Raster fallback preserves the exact curve/contour; reflections are simplified. */
export function rasterizeSculpture(
  g: VisualGenome,
  size: number,
): Uint8ClampedArray {
  const s = g.sculpture!,
    points = s.points,
    pixels = new Uint8ClampedArray(size * size * 4);
  const bg = rgb(g.palette.background),
    accent = rgb(g.palette.accent),
    light = rgb(g.palette.light),
    dark = rgb(g.palette.dark);
  for (let iy = 0; iy < size; iy++)
    for (let ix = 0; ix < size; ix++) {
      const x = ((ix + 0.5) / size) * 2 - 1,
        y = 1 - ((iy + 0.5) / size) * 2,
        pixel = 2.5 / size;
      let alpha = 0,
        nx = 0,
        ny = 0,
        nz = 1,
        along = 0,
        side = 0;
      if (s.model >= 8) {
        const distance = distanceFunctions[s.model - 8]!;
        const d = distance(
          x,
          y,
          g.params.lobes,
          g.params.warp,
          g.params.hollow,
        );
        alpha = 1 - smooth(-pixel, pixel, d);
        if (alpha) {
          const e = 0.0025;
          nx = -(height(x + e, y, g) - height(x - e, y, g)) / (2 * e);
          ny = -(height(x, y + e, g) - height(x, y - e, g)) / (2 * e);
        }
        along = Math.atan2(y, x) / TAU + 0.5;
        side = Math.hypot(x, y) * 1.6 - 1;
      } else {
        let best = -100;
        for (let i = 0; i < 128; i++) {
          const k = i * 4,
            ax = points[k]!,
            ay = points[k + 1]!,
            bx = points[k + 4]!,
            by = points[k + 5]!;
          const maxWidth = Math.max(points[k + 2]!, points[k + 6]!) + pixel;
          if (
            x < Math.min(ax, bx) - maxWidth ||
            x > Math.max(ax, bx) + maxWidth ||
            y < Math.min(ay, by) - maxWidth ||
            y > Math.max(ay, by) + maxWidth
          )
            continue;
          const vx = bx - ax,
            vy = by - ay,
            l2 = Math.max(vx * vx + vy * vy, 0.0000001),
            len = Math.sqrt(l2);
          const f = clamp(((x - ax) * vx + (y - ay) * vy) / l2),
            dx = x - ax - vx * f,
            dy = y - ay - vy * f;
          const w = points[k + 2]! + (points[k + 6]! - points[k + 2]!) * f,
            dist = Math.hypot(dx, dy),
            d = dist - w;
          if (d > pixel) continue;
          const tx = vx / len,
            ty = vy / len,
            sign = dx * -ty + dy * tx < 0 ? -1 : 1;
          const q = clamp((sign * dist) / w, -0.999, 0.999),
            arc = (i + f) / 128;
          const z =
            points[k + 3]! +
            (points[k + 7]! - points[k + 3]!) * f +
            profile(q, arc, g) * w * s.relief;
          if (z > best) {
            best = z;
            alpha = 1 - smooth(-pixel, pixel, d);
            side = q;
            along = arc;
            const slope =
              ((profile(clamp(q + 0.006, -0.999, 0.999), arc, g) -
                profile(clamp(q - 0.006, -0.999, 0.999), arc, g)) /
                0.012) *
              s.relief;
            const tangentSlope =
              f > 0.001 && f < 0.999
                ? (points[k + 7]! - points[k + 3]!) / len
                : 0;
            nx =
              -(dist > 0.00001 ? (dx / dist) * sign : -ty) * slope -
              tx * tangentSlope;
            ny =
              -(dist > 0.00001 ? (dy / dist) * sign : tx) * slope -
              ty * tangentSlope;
          }
        }
      }
      const norm = Math.hypot(nx, ny, nz);
      nx /= norm;
      ny /= norm;
      nz /= norm;
      const diffuse = Math.max(0, (-0.5 * nx + 0.65 * ny + 1.1 * nz) / 1.373);
      const rx = 2 * nz * nx,
        ry = 2 * nz * ny,
        rz = 2 * nz * nz - 1;
      const studio = (0.5 + 0.5 * Math.sin(rx * 3.6 + ry * 2.2 + 0.8)) ** 9;
      const spec = Math.max(0, (-0.4 * rx + 0.6 * ry + rz) / 1.233) ** 22,
        edge = (1 - nz) ** 2;
      for (let c = 0; c < 3; c++) {
        const tone =
          0.5 + 0.5 * Math.sin(along * TAU * 2 + (g.seed % 65521) * 0.008);
        const base =
          accent[c]! + (light[c]! - accent[c]!) * (0.15 + 0.18 * tone);
        let value =
          base * (0.22 + 0.67 * diffuse) +
          light[c]! * spec * 0.22 +
          accent[c]! * edge * 0.15;
        if (g.material === 'metal')
          value =
            dark[c]! +
            (base - dark[c]!) * (0.12 + 0.8 * studio + 0.38 * spec) +
            light[c]! * spec * 0.75 +
            base * 0.12 * diffuse +
            light[c]! * edge * 0.22;
        if (g.material === 'film') {
          const spectrum =
            0.5 +
            0.5 *
              Math.cos(
                c * 2.1 +
                  nx * 3.5 +
                  ny * 2.3 +
                  along * 3 +
                  (g.seed % 65521) * 0.003,
              );
          value =
            (base * 0.68 + spectrum * 0.32) * (0.23 + 0.64 * diffuse) +
            light[c]! * (studio * 0.36 + spec * 0.58 + edge * 0.18);
        }
        if (g.material === 'glass')
          value =
            dark[c]! +
            (base - dark[c]!) * (0.15 + 0.7 * edge) +
            light[c]! * (spec * 0.72 + studio * 0.26) +
            accent[c]! * (0.1 + 0.32 * Math.abs(side) ** 4);
        const grooves =
          0.5 + 0.5 * Math.sin(side * (45 + s.etching * 110) + along * 18);
        value =
          value * (1 - s.etching * 0.2 * grooves) +
          light[c]! * s.etching * 0.09 * grooves ** 8;
        pixels[(iy * size + ix) * 4 + c] = srgb(
          bg[c]! + (value - bg[c]!) * alpha,
        );
      }
      pixels[(iy * size + ix) * 4 + 3] = 255;
    }
  return pixels;
}

const cache = new WeakMap<VisualGenome, Map<number, HTMLCanvasElement>>();
export function drawSculptureCanvas(
  ctx: CanvasRenderingContext2D,
  g: VisualGenome,
  width: number,
  height: number,
  time: number,
) {
  const size = Math.min(width, height),
    resolution = width === 2048 && height === 2048 ? 2048 : Math.min(480, size);
  let entries = cache.get(g);
  if (!entries) {
    entries = new Map();
    cache.set(g, entries);
  }
  let image = entries.get(resolution);
  if (!image) {
    image = document.createElement('canvas');
    image.width = resolution;
    image.height = resolution;
    const target = image.getContext('2d')!;
    const data = target.createImageData(resolution, resolution);
    data.data.set(rasterizeSculpture(g, resolution));
    target.putImageData(data, 0, 0);
    entries.set(resolution, image);
  }
  const scale =
    g.params.scale *
    (1 + Math.sin(time * g.motion.tempo + g.motion.phase) * g.motion.breathe);
  ctx.save();
  ctx.setTransform(1, 0, 0, 1, 0, 0);
  ctx.fillStyle = g.palette.background;
  ctx.fillRect(0, 0, width, height);
  ctx.translate(width / 2, height / 2);
  ctx.rotate(
    g.params.rotation + Math.sin(time * g.motion.tempo) * g.motion.orbit,
  );
  ctx.scale(scale, scale);
  ctx.drawImage(image, -size / 2, -size / 2, size, size);
  ctx.restore();
}
