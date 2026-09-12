import { FLAT_SDF_GLSL } from './flat-sdf.generated.ts';
import type { FlatFamily } from '../generative/types.ts';

export const FLAT_IDS: Record<FlatFamily, number> = {rosette: 0, spark: 1, organism: 2, loop: 3, crescent: 4, emblem: 5, fan: 6, ribbon: 7};

export const FLAT_FRAGMENT_SHADER = `#version 300 es
precision highp float;
precision highp int;
in vec2 v_uv;
out vec4 outColor;
uniform vec2 u_resolution;
uniform float u_time;
uniform int u_geometry;
uniform int u_material;
uniform vec3 u_palette0;
uniform vec3 u_palette1;
uniform vec3 u_palette2;
uniform vec3 u_palette3;
uniform vec4 u_params0;
uniform vec4 u_params1;
uniform vec4 u_motion;
uniform float u_seed;

// Uniform inputs to the Shader Park recipes.
#define n u_params0.z
#define w u_params0.w
#define h u_params1.x
#define t u_params1.y
float add(float a, float b) { return min(a,b); }
${FLAT_SDF_GLSL}
#undef n
#undef w
#undef h
#undef t

float distanceToFigure(vec2 q) {
  vec3 p=vec3(q,0.0);
  if(u_geometry==0) return flat_rosette(p);
  if(u_geometry==1) return flat_spark(p);
  if(u_geometry==2) return flat_organism(p);
  if(u_geometry==3) return flat_loop(p);
  if(u_geometry==4) return flat_crescent(p);
  if(u_geometry==5) return flat_emblem(p);
  if(u_geometry==6) return flat_fan(p);
  return flat_ribbon(p);
}
vec3 toSrgb(vec3 c) {
  return mix(12.92*c,1.055*pow(max(c,vec3(0.0)),vec3(1.0/2.4))-.055,step(vec3(.0031308),c));
}
void main() {
  vec2 p=(v_uv*2.0-1.0)*u_resolution/min(u_resolution.x,u_resolution.y);
  float angle=u_params0.y+sin(u_time*u_motion.x)*u_motion.z;
  float c=cos(angle), s=sin(angle);
  p=mat2(c,-s,s,c)*p;
  p/=u_params0.x*(1.0+sin(u_time*u_motion.x+u_motion.w)*u_motion.y);
  float d=distanceToFigure(p);
  float aa=max(fwidth(d),.0005);
  float mask=1.0-smoothstep(-aa,aa,d);
  vec3 ink=u_palette3;
  if(u_material==0) ink=mix(u_palette3,u_palette2,clamp(.12+.19*p.y+.08*p.x,0.0,.4));
  if(u_material==2) {
    float gradient=smoothstep(-.65,.65,p.x*.65+p.y);
    ink=mix(u_palette1,u_palette3,gradient);
    ink=mix(ink,u_palette2,.35*pow(gradient,3.0));
  }
  if(u_material==6) {
    float outline=1.0-smoothstep(.012-aa,.012+aa,abs(d));
    mask=max(outline,mask*.10);
    ink=mix(u_palette3,u_palette2,.35);
  }
  vec3 color=toSrgb(mix(u_palette0,ink,mask));
  outColor=vec4(clamp(color,0.0,1.0),1.0);
}`;
