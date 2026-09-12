import type {
  DimensionMode,
  GeometryFamily,
  MaterialFamily,
} from '../generative/types.ts';

export const GEOMETRY_IDS: Record<GeometryFamily, number> = {
  organism: 0,
  relic: 1,
  ribbon: 2,
  glyph: 3,
  field: 4,
  constellation: 5,
};

export const MATERIAL_IDS: Record<MaterialFamily, number> = {
  matte: 0,
  glass: 1,
  film: 2,
  plasma: 3,
  metal: 4,
  ink: 5,
  contour: 6,
};

export const DIMENSION_IDS: Record<DimensionMode, number> = {
  graphic: 0,
  volumetric: 1,
  hybrid: 2,
};

export const VERTEX_SHADER_SOURCE = `#version 300 es
precision highp float;
out vec2 v_uv;
void main() {
  vec2 p = vec2((gl_VertexID << 1) & 2, gl_VertexID & 2);
  v_uv = p;
  gl_Position = vec4(p * 2.0 - 1.0, 0.0, 1.0);
}`;

export const FRAGMENT_SHADER_SOURCE = `#version 300 es
precision highp float;
precision highp int;

in vec2 v_uv;
out vec4 outColor;

uniform vec2 u_resolution;
uniform float u_time;
uniform int u_geometry;
uniform int u_material;
uniform int u_dimension;
uniform vec3 u_palette0;
uniform vec3 u_palette1;
uniform vec3 u_palette2;
uniform vec3 u_palette3;
uniform vec4 u_params0;
uniform vec4 u_params1;
uniform vec4 u_motion;
uniform float u_seed;
uniform float u_camera;
uniform int u_satellites;
uniform float u_frameFit;

#define PI 3.14159265359
#define TAU 6.28318530718
#define MAX_STEPS 76

mat2 rot(float a) { float c = cos(a), s = sin(a); return mat2(c, -s, s, c); }
float hash11(float p) { p = fract(p * .1031); p *= p + 33.33; p *= p + p; return fract(p); }
float hash21(vec2 p) { vec3 p3 = fract(vec3(p.xyx) * .1031); p3 += dot(p3, p3.yzx + 33.33); return fract((p3.x + p3.y) * p3.z); }
float noise3(vec3 x) {
  vec3 i = floor(x); vec3 f = fract(x); f = f*f*(3.0-2.0*f);
  float n = dot(i, vec3(1.0, 57.0, 113.0));
  return mix(mix(mix(hash11(n), hash11(n+1.0), f.x), mix(hash11(n+57.0), hash11(n+58.0), f.x), f.y),
             mix(mix(hash11(n+113.0), hash11(n+114.0), f.x), mix(hash11(n+170.0), hash11(n+171.0), f.x), f.y), f.z);
}
float smin(float a, float b, float k) { float h = clamp(.5 + .5*(b-a)/k, 0.0, 1.0); return mix(b,a,h)-k*h*(1.0-h); }
float smax(float a, float b, float k) { return -smin(-a,-b,k); }
float sdSphere(vec3 p, float r) { return length(p)-r; }
float sdBox(vec3 p, vec3 b, float r) { vec3 q=abs(p)-b+r; return length(max(q,0.0))+min(max(q.x,max(q.y,q.z)),0.0)-r; }
float sdTorus(vec3 p, vec2 t) { vec2 q=vec2(length(p.xz)-t.x,p.y); return length(q)-t.y; }
float sdCapsule(vec3 p, vec3 a, vec3 b, float r) { vec3 pa=p-a, ba=b-a; float h=clamp(dot(pa,ba)/dot(ba,ba),0.0,1.0); return length(pa-ba*h)-r; }
float sdSegment(vec2 p, vec2 a, vec2 b) { vec2 pa=p-a, ba=b-a; float h=clamp(dot(pa,ba)/dot(ba,ba),0.0,1.0); return length(pa-ba*h); }

vec3 deform(vec3 p) {
  float pulse = sin(u_time*u_motion.x + u_motion.w) * u_motion.y;
  p.xy *= rot(u_params0.y + sin(u_time*u_motion.x*.47)*u_motion.z);
  p.xz *= rot(u_params0.y*.37);
  p *= 1.0 + pulse;
  return p;
}

float organism(vec3 p) {
  float a=atan(p.y,p.x), z=p.z;
  float lobes=u_params0.z;
  float radial=.86 + .095*sin(a*lobes+z*1.7+u_seed*.001) + .055*sin(a*(lobes-1.0)-z*2.4);
  float d=length(p)-radial*u_params0.x;
  d += (noise3(p*2.25+u_seed*.0003)-.5)*u_params0.w*.25;
  if(u_params1.x>.22) d=smax(d,-sdSphere(p+vec3(.15,-.06,.05),u_params1.x),.13);
  return d;
}

float relic(vec3 p) {
  float d=sdBox(p,vec3(.63,.72,.48)*u_params0.x,.24);
  vec3 q=p; q.xy*=rot(.78+u_params0.y);
  d=smin(d,sdTorus(q,vec2(.56,.13+u_params1.y*.3)),.18);
  float cut=sdSphere(p+vec3(.24,-.18,.45),.43+u_params1.x*.25);
  d=smax(d,-cut,.11);
  d+=(noise3(p*4.0)-.5)*u_params0.w*.08;
  return d;
}

float ribbon(vec3 p) {
  vec3 q=p; float twist=q.z*1.35+sin(u_time*u_motion.x)*.18;
  q.xy*=rot(twist+u_params0.y);
  float ring=sdTorus(q,vec2(.62*u_params0.x,.085+u_params1.y*.34));
  vec3 a=vec3(-.62,-.38,-.18), b=vec3(.58,.42,.2);
  float band=sdCapsule(q,a,b,.08+u_params1.y*.24);
  return smin(ring,band,.12+u_params0.w*.08);
}

float constellation(vec3 p) {
  float d=organism(p*1.16)/1.16;
  for(int i=0;i<4;i++) {
    if(i>=u_satellites) break;
    float fi=float(i), a=fi*2.19+u_seed*.013+u_time*u_motion.z;
    vec3 c=vec3(cos(a),sin(a*.83),sin(a))* (1.02+fi*.18);
    d=min(d,sdSphere(p-c,.12+.055*hash11(fi+u_seed)));
  }
  return d;
}

float mapScene(vec3 p) {
  p=deform(p);
  if(u_geometry==0) return organism(p);
  if(u_geometry==1) return relic(p);
  if(u_geometry==2) return ribbon(p);
  if(u_geometry==5) return constellation(p);
  return organism(p);
}

float glyph(vec2 p) {
  p*=rot(u_params0.y);
  float a=atan(p.y,p.x), r=length(p);
  float lobes=u_params0.z;
  float contour=.55*u_params0.x + .14*sin(a*lobes+u_seed*.01)+.06*sin(a*(lobes+2.0));
  float body=abs(r-contour)-(.035+u_params1.y*.23);
  float slash=sdSegment(p,vec2(-.72,.52),vec2(.66,-.48))-(.018+u_params1.y*.12);
  float d=min(body,slash);
  if(u_params1.x>.22) d=max(d,-(length(p-vec2(.12,-.04))-u_params1.x*.45));
  return d;
}

float fieldShape(vec2 p) {
  p*=rot(u_params0.y*.5);
  float a=atan(p.y,p.x), r=length(p);
  float wave=sin(r*10.0-a*u_params0.z+u_time*u_motion.x)*.5+.5;
  float envelope=smoothstep(1.05,.18,r/u_params0.x);
  float veil=(noise3(vec3(p*2.2,u_seed*.001))-.5)*u_params0.w;
  return .42-(wave*.42+envelope*.45+veil);
}

float mapGraphic(vec2 p) { return u_geometry==4 ? fieldShape(p) : glyph(p); }

vec3 normalAt(vec3 p) {
  float e=.0018; vec2 h=vec2(1.0,-1.0)*.5773;
  return normalize(h.xyy*mapScene(p+h.xyy*e)+h.yyx*mapScene(p+h.yyx*e)+h.yxy*mapScene(p+h.yxy*e)+h.xxx*mapScene(p+h.xxx*e));
}

float softShadow(vec3 ro, vec3 rd, float mint, float maxt) {
  float result=1.0, t=mint;
  for(int i=0;i<24;i++) { float h=mapScene(ro+rd*t); result=min(result,12.0*h/t); t+=clamp(h,.018,.16); if(h<.001||t>maxt) break; }
  return clamp(result,0.0,1.0);
}

float ambientOcclusion(vec3 p, vec3 n) {
  float occ=0.0, scale=1.0;
  for(int i=1;i<=4;i++) { float h=.045*float(i); occ+=(h-mapScene(p+n*h))*scale; scale*=.58; }
  return clamp(1.0-occ*2.2,0.0,1.0);
}

vec3 materialColor(vec3 p, vec3 n, vec3 rd, vec3 lightDir, float diff, float spec, float fresnel) {
  float bands=.5+.5*sin(dot(p,vec3(3.1,2.3,4.2))+u_seed*.007);
  vec3 base=mix(u_palette1,u_palette2,.28+.5*bands);
  if(u_material==0) return base*(.24+diff*.9)+u_palette3*spec*.22;
  if(u_material==1) return mix(u_palette1,u_palette2,fresnel)*(.3+diff*.45)+u_palette3*pow(fresnel,2.0)*.7+vec3(spec);
  if(u_material==2) { vec3 iri=.5+.5*cos(TAU*(fresnel*2.4+vec3(0.0,.33,.67)+bands*.12)); return mix(base,iri,.52)*(.35+diff*.7)+u_palette3*spec*.5; }
  if(u_material==3) return base*(.3+diff*.45)+mix(u_palette3,u_palette2,bands)*(.35+fresnel*.85)+vec3(spec*.5);
  if(u_material==4) return base*(.16+diff*.48)+mix(vec3(.75),u_palette3,.35)*spec*1.2+fresnel*u_palette2*.28;
  if(u_material==5) return mix(u_palette1,u_palette3,smoothstep(.25,.78,bands))*(.36+diff*.72);
  float edge=smoothstep(.25,.85,fresnel); return mix(u_palette0,u_palette2,edge)*(.32+diff*.7)+u_palette3*spec*.3;
}

vec3 render3d(vec2 p, out float glow) {
  vec3 ro=vec3(0.0,0.0,u_camera), rd=normalize(vec3(p,-1.75));
  ro.xy+=vec2(sin(u_time*u_motion.z),cos(u_time*u_motion.z*.8))*u_motion.z*.12;
  float t=0.0, d=0.0;
  glow=0.0;
  for(int i=0;i<MAX_STEPS;i++) {
    vec3 pos=ro+rd*t; d=mapScene(pos); glow+=exp(-abs(d)*18.0)*.006;
    if(abs(d)<.0008+t*.00012||t>8.0) break;
    t+=max(d*.72,.008);
  }
  if(t>8.0) return vec3(0.0);
  vec3 pos=ro+rd*t, n=normalAt(pos);
  vec3 lightDir=normalize(vec3(-.55,.8,.62));
  float diff=max(dot(n,lightDir),0.0);
  float shadow=softShadow(pos+n*.012,lightDir,.03,3.5);
  float ao=ambientOcclusion(pos,n);
  vec3 halfDir=normalize(lightDir-rd);
  float spec=pow(max(dot(n,halfDir),0.0),mix(18.0,96.0,1.0-u_params1.z))*shadow;
  float fresnel=pow(1.0-max(dot(n,-rd),0.0),2.8);
  return materialColor(pos,n,rd,lightDir,diff*shadow,spec,fresnel)*ao;
}

vec3 renderGraphic(vec2 p, out float alpha) {
  float d=mapGraphic(p), edge=fwidth(d)*1.35;
  alpha=1.0-smoothstep(-edge,edge,d);
  float contour=1.0-smoothstep(edge,edge*5.0,abs(d));
  float angle=atan(p.y,p.x)/TAU+.5;
  vec3 fill=mix(u_palette1,u_palette2,smoothstep(-.75,.72,p.y+sin(angle*TAU*2.0)*.18));
  fill=mix(fill,u_palette3,.5+.5*sin(angle*TAU*3.0+u_seed*.01));
  if(u_material==6) { alpha=max(contour,alpha*.08); fill=mix(u_palette2,u_palette3,angle); }
  if(u_geometry==4) { alpha=smoothstep(.08,.78,alpha); fill=mix(u_palette1,u_palette3,.5+.5*sin(length(p)*8.0)); }
  return fill*(.74+contour*.5);
}

void main() {
  vec2 uv=v_uv;
  vec2 p=(uv*2.0-1.0); p.x*=u_resolution.x/max(u_resolution.y,1.0);
  if(u_frameFit>.5)p=(uv*2.0-1.0)*u_resolution/min(u_resolution.x,u_resolution.y)*1.45;
  float radial=length(p);
  vec3 bg=mix(u_palette0,mix(u_palette1,u_palette0,.72),smoothstep(.0,1.35,radial));
  bg+=u_palette3*exp(-3.4*length(p-vec2(-.72,.58)))*.08;
  float glow=0.0; vec3 art=vec3(0.0); float alpha=0.0;
  if(u_dimension==0) art=renderGraphic(p,alpha);
  else {
    art=render3d(p,glow); alpha=step(.00001,dot(art,art));
    if(u_dimension==2) { float ga; vec3 graphic=renderGraphic(p*1.08,ga); art=mix(art,graphic,ga*.42); alpha=max(alpha,ga*.42); }
  }
  vec3 color=mix(bg,art,alpha);
  if(u_frameFit>.5){
    float frameMask=1.0-smoothstep(1.05,1.3,length(p));
    color=mix(vec3(.00273,.00304,.00368),art,alpha*frameMask);
  }
  color+=u_palette3*glow*u_params1.w*3.2;
  color*=1.0-.14*smoothstep(.45,1.55,radial);
  float grain=(hash21(gl_FragCoord.xy+u_seed)-.5)*.025;
  color+=grain;
  color=(color*(2.51*color+.03))/(color*(2.43*color+.59)+.14);
  color=pow(clamp(color,0.0,1.0),vec3(.92));
  outColor=vec4(color,1.0);
}`;
