import type { VisualGenome } from '../generative/types.ts';
import { flatDistances } from './flat-sdf.generated.ts';

const stamps = new WeakMap<VisualGenome, Map<number, HTMLCanvasElement>>();
const clamp = (x: number) => Math.max(0,Math.min(1,x));
function smooth(a: number, b: number, x: number): number {
  const t = clamp((x-a)/(b-a)); return t*t*(3-2*t);
}
function rgb(hex: string): number[] {
  return [1,3,5].map(i => {
    const c=parseInt(hex.slice(i,i+2),16)/255;
    return c <= .04045 ? c/12.92 : ((c+.055)/1.055)**2.4;
  });
}
function srgb(c: number): number { return Math.round(clamp(c <= .0031308 ? 12.92*c : 1.055*c**(1/2.4)-.055)*255); }

function stamp(genome: VisualGenome, size: number): HTMLCanvasElement {
  let cache = stamps.get(genome);
  if (!cache) {cache = new Map(); stamps.set(genome, cache);}
  const existing=cache.get(size); if(existing) return existing;
  const canvas=document.createElement('canvas'); canvas.width=size; canvas.height=size;
  const ctx=canvas.getContext('2d'); if(!ctx || !genome.flat) return canvas;
  const pixels=ctx.createImageData(size,size);
  const distance=flatDistances[genome.flat.family];
  const {lobes,warp,hollow,thickness}=genome.params;
  const accent=rgb(genome.palette.accent), light=rgb(genome.palette.light), dark=rgb(genome.palette.dark);
  for(let iy=0;iy<size;iy++) for(let ix=0;ix<size;ix++) {
    const x=(ix+.5)/size*2-1, y=1-(iy+.5)/size*2;
    const d=distance(x,y,lobes,warp,hollow,thickness), aa=2/size;
    let alpha=1-smooth(-aa,aa,d);
    if(genome.material==='contour') alpha=Math.max(1-smooth(.012-aa,.012+aa,Math.abs(d)),alpha*.1);
    if(alpha===0) continue;
    const offset=(iy*size+ix)*4;
    for(let channel=0;channel<3;channel++) {
      let color=accent[channel]!;
      if(genome.material==='matte') color += (light[channel]!-color)*clamp(.12+.19*y+.08*x);
      if(genome.material==='film') {
        const gradient=smooth(-.65,.65,x*.65+y);
        color=dark[channel]!+(accent[channel]!-dark[channel]!)*gradient;
        color+=(light[channel]!-color)*.35*gradient**3;
      }
      if(genome.material==='contour') color+=(light[channel]!-color)*.35;
      pixels.data[offset+channel]=srgb(color);
    }
    pixels.data[offset+3]=Math.round(alpha*255);
  }
  ctx.putImageData(pixels,0,0); cache.set(size,canvas); return canvas;
}

/** Same distance recipes as the GPU; cached rasterisation keeps fallback animation inexpensive. */
export function drawFlatCanvas(ctx: CanvasRenderingContext2D, g: VisualGenome, width: number, height: number, time: number): void {
  const size=Math.min(width,height);
  const image=stamp(g,Math.min(size, width===2048 && height===2048 ? 2048 : 640));
  const scale=g.params.scale*(1+Math.sin(time*g.motion.tempo+g.motion.phase)*g.motion.breathe);
  ctx.save(); ctx.setTransform(1,0,0,1,0,0);
  ctx.fillStyle=g.palette.background; ctx.fillRect(0,0,width,height);
  ctx.translate(width/2,height/2);
  ctx.rotate(g.params.rotation+Math.sin(time*g.motion.tempo)*g.motion.orbit);
  ctx.scale(scale,scale);
  ctx.drawImage(image,-size/2,-size/2,size,size);
  ctx.restore();
}
