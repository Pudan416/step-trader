import { mulberry32, range } from '../generative/random.ts';
import type { VisualGenome } from '../generative/types.ts';

function radialPath(
  context: CanvasRenderingContext2D,
  genome: VisualGenome,
  radius: number,
  time: number,
): void {
  const { lobes, warp } = genome.params;
  const random = mulberry32(genome.seed);
  const phaseA = range(random, 0, Math.PI * 2);
  const phaseB = range(random, 0, Math.PI * 2);
  const points = 112;
  for (let index = 0; index <= points; index += 1) {
    const angle = (index / points) * Math.PI * 2;
    const ripple =
      Math.sin(angle * lobes + phaseA + time * genome.motion.tempo) *
        warp *
        0.16 +
      Math.sin(angle * (lobes - 1) + phaseB) * warp * 0.08;
    const localRadius = radius * (0.82 + ripple);
    const x = Math.cos(angle) * localRadius;
    const y = Math.sin(angle) * localRadius;
    if (index === 0) context.moveTo(x, y);
    else context.lineTo(x, y);
  }
  context.closePath();
}

export function drawFallback(
  context: CanvasRenderingContext2D,
  genome: VisualGenome,
  width: number,
  height: number,
  time: number,
): void {
  const centerX = width / 2;
  const centerY = height / 2;
  const radius = Math.min(width, height) * 0.38 * genome.params.scale;
  context.save();
  context.setTransform(1, 0, 0, 1, 0, 0);
  const backdrop = context.createRadialGradient(
    width * 0.3,
    height * 0.2,
    0,
    centerX,
    centerY,
    Math.max(width, height) * 0.85,
  );
  backdrop.addColorStop(0, genome.palette.dark);
  backdrop.addColorStop(0.48, genome.palette.background);
  backdrop.addColorStop(1, '#030405');
  context.fillStyle = backdrop;
  context.fillRect(0, 0, width, height);

  context.translate(centerX, centerY);
  context.rotate(
    genome.params.rotation +
      Math.sin(time * genome.motion.tempo) * genome.motion.orbit,
  );
  context.beginPath();
  radialPath(context, genome, radius, time);
  const fill = context.createRadialGradient(
    -radius * 0.3,
    -radius * 0.38,
    0,
    0,
    0,
    radius * 1.25,
  );
  fill.addColorStop(0, genome.palette.light);
  fill.addColorStop(0.38, genome.palette.accent);
  fill.addColorStop(0.72, genome.palette.dark);
  fill.addColorStop(1, genome.palette.emission);
  context.fillStyle = fill;
  context.shadowColor = genome.palette.emission;
  context.shadowBlur = radius * genome.params.bloom * 0.7;
  context.fill();

  if (genome.material === 'contour' || genome.geometry === 'glyph') {
    context.lineWidth = Math.max(2, radius * genome.params.thickness * 0.18);
    context.strokeStyle = genome.palette.light;
    context.globalCompositeOperation = 'screen';
    context.stroke();
  }

  if (genome.params.hollow > 0.2) {
    context.globalCompositeOperation = 'destination-out';
    context.beginPath();
    context.arc(
      radius * 0.08,
      -radius * 0.04,
      radius * genome.params.hollow * 0.55,
      0,
      Math.PI * 2,
    );
    context.fill();
  }

  context.globalCompositeOperation = 'screen';
  for (let index = 0; index < genome.params.satelliteCount; index += 1) {
    const angle =
      (index / Math.max(1, genome.params.satelliteCount)) * Math.PI * 2 +
      time * genome.motion.orbit;
    const distance = radius * (1.25 + index * 0.15);
    context.beginPath();
    context.arc(
      Math.cos(angle) * distance,
      Math.sin(angle) * distance,
      radius * (0.07 + index * 0.012),
      0,
      Math.PI * 2,
    );
    context.fillStyle =
      index % 2 === 0 ? genome.palette.accent : genome.palette.light;
    context.fill();
  }
  context.restore();
}
