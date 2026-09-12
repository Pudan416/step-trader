import { SURFACE_GLSL } from './surface.generated.ts';
import { MEMBRANE_GLSL } from './membranes.generated.ts';

export const SCULPTURE_FRAGMENT_SHADER = `#version 300 es
precision highp float;
precision highp int;
in vec2 v_uv;
out vec4 outColor;
uniform vec2 u_resolution;
uniform float u_time;
uniform float u_seed;
uniform int u_material;
uniform int u_geometry;
uniform vec3 u_palette0;
uniform vec3 u_palette1;
uniform vec3 u_palette2;
uniform vec3 u_palette3;
uniform vec4 u_params0;
uniform vec4 u_params1;
uniform vec4 u_motion;
uniform vec4 u_surface;
uniform float u_etching;
uniform vec4 u_points[129];
#define TAU 6.28318530718
#define section u_surface.x
#define folds u_surface.y
#define twist u_surface.z
#define time u_time
float add(float a,float b){return min(a,b);}
${SURFACE_GLSL}
#undef section
#undef folds
#undef twist
#undef time
#define n u_params0.z
#define w u_params0.w
#define h u_params1.x
${MEMBRANE_GLSL}
#undef n
#undef w
#undef h

vec3 srgb(vec3 c){return mix(12.92*c,1.055*pow(max(c,vec3(0.0)),vec3(1.0/2.4))-.055,step(vec3(.0031308),c));}
float hash(vec2 p){return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453);}
vec3 shade(vec3 n,vec2 p,float side,float along,float height){
  vec3 light=normalize(vec3(-.5,.65,1.1));
  float diffuse=max(dot(n,light),0.0);
  vec3 reflected=reflect(vec3(0,0,-1),n);
  float studio=pow(.5+.5*sin(reflected.x*3.6+reflected.y*2.2+.8),9.0);
  float softbox=pow(max(dot(reflected,normalize(vec3(-.4,.6,1.0))),0.0),22.0);
  float edge=pow(1.0-n.z,2.0);
  float tone=.5+.5*sin(along*TAU*2.0+u_seed*.008);
  vec3 base=mix(u_palette3,u_palette2,.15+.18*tone);
  vec3 c;
  if(u_material==4){
    float reflection=.12+.8*studio+.38*softbox;
    c=mix(u_palette1,base,reflection)+u_palette2*softbox*.75;
    c+=base*.12*diffuse+u_palette2*edge*.22;
  }else if(u_material==2){
    vec3 spectrum=.5+.5*cos(vec3(0.0,2.1,4.2)+n.x*3.5+n.y*2.3+along*3.0+u_seed*.003);
    c=mix(base,spectrum,.32)*(.23+.64*diffuse);
    c+=u_palette2*(studio*.36+softbox*.58+edge*.18);
  }else if(u_material==1){
    c=mix(u_palette1,base,.15+.7*edge)+u_palette2*(softbox*.72+studio*.26);
    c+=u_palette3*(.1+.32*pow(abs(side),4.0));
  }else{
    c=base*(.22+.67*diffuse)+u_palette2*softbox*.22+u_palette3*edge*.15;
  }
  // Fine longitudinal engraving belongs to the surface, not to the background.
  float grooves=.5+.5*sin(side*(45.0+u_etching*110.0)+along*18.0);
  c*=1.0-u_etching*.20*grooves;
  c+=u_palette2*u_etching*.09*pow(grooves,8.0);
  return c;
}
float membraneDistance(vec2 p){
  if(u_geometry==8)return membrane_aeolian(vec3(p,0));
  if(u_geometry==9)return membrane_mantle(vec3(p,0));
  if(u_geometry==10)return membrane_obsidian(vec3(p,0));
  return membrane_elytra(vec3(p,0));
}
float membraneHeight(vec2 p){
  float r=length(p),a=atan(p.y,p.x),f=u_params0.z;
  float phase=u_seed*.002+u_time*.12;
  if(u_geometry==8)return .16*sin(a*f+r*(10.0+u_params0.w*14.0)+phase)*(1.0-r*.7)+.09*cos(a*2.0);
  if(u_geometry==9)return .22*sqrt(max(1.0-r*r*1.7,.001))+.052*sin(a*(f+5.0)+r*4.0+phase)*smoothstep(.08,.6,r);
  if(u_geometry==10){
    float facet=max(abs(p.x*.8+p.y*.5),abs(p.y*.85-p.x*.22));
    return .28-facet*.4+.08*sin(p.x*4.0+p.y*3.0+phase);
  }
  return .16*cos(p.x*5.0+p.y*3.0+phase)+.06*sin(a*f+r*8.0)*smoothstep(.1,.7,r);
}
void main(){
  vec2 p=(v_uv*2.0-1.0)*u_resolution/min(u_resolution.x,u_resolution.y);
  float angle=u_params0.y+sin(u_time*u_motion.x)*u_motion.z;
  float ca=cos(angle),sa=sin(angle);
  p=mat2(ca,-sa,sa,ca)*p;
  p/=u_params0.x*(1.0+sin(u_time*u_motion.x+u_motion.w)*u_motion.y);
  float pixel=2.5/min(u_resolution.x,u_resolution.y);
  if(u_geometry>=8){
    float d=membraneDistance(p),aa=max(fwidth(d),.001);
    float mask=1.0-smoothstep(-aa,aa,d);
    // A rolled edge closes the surface and gives the silhouette a continuous highlight.
    float edgeWidth=.038;
    float edgeRoll=.035*smoothstep(-edgeWidth,0.0,d);
    float e=.0025;
    vec2 deltaX=vec2(e,0),deltaY=vec2(0,e);
    float dx=(membraneHeight(p+deltaX)-membraneHeight(p-deltaX))/(2.0*e);
    float dy=(membraneHeight(p+deltaY)-membraneHeight(p-deltaY))/(2.0*e);
    vec2 edgeGradient=vec2(membraneDistance(p+deltaX)-membraneDistance(p-deltaX),membraneDistance(p+deltaY)-membraneDistance(p-deltaY))/(2.0*e);
    vec2 grad=vec2(dx,dy)-edgeGradient*edgeRoll/edgeWidth;
    vec3 normal=normalize(vec3(-grad,1.0));
    float along=atan(p.y,p.x)/TAU+.5;
    vec3 ink=shade(normal,p,length(p)*1.6-1.0,along,membraneHeight(p));
    ink+=u_palette2*.10*exp(-abs(d)*95.0);
    vec3 color=srgb(mix(u_palette0,ink,mask));
    outColor=vec4(clamp(color,0.0,1.0),1.0);return;
  }
  float bestDepth=-100.0,side=0.0,along=0.0,width=.1,alpha=0.0,shadow=0.0;
  vec2 tangent=vec2(1,0),normalAcross=vec2(0,1); float slopeAlong=0.0;
  for(int i=0;i<128;i++){
    vec4 a=u_points[i],b=u_points[i+1];
    float margin=max(a.z,b.z)+pixel;
    if(any(lessThan(p,min(a.xy,b.xy)-margin))||any(greaterThan(p,max(a.xy,b.xy)+margin)))continue;
    vec2 ab=b.xy-a.xy;
    float len2=max(dot(ab,ab),.0000001);
    float f=clamp(dot(p-a.xy,ab)/len2,0.0,1.0);
    vec4 point=mix(a,b,f);
    vec2 delta=p-point.xy;
    float dist=length(delta),d=dist-point.z;
    shadow=max(shadow,exp(-max(d,0.0)*45.0)*.22);
    if(d>pixel)continue;
    vec2 tan=ab/sqrt(len2),across=vec2(-tan.y,tan.x);
    float direction=dot(delta,across)<0.0?-1.0:1.0;
    float q=clamp(direction*dist/point.z,-.999,.999);
    float arc=(float(i)+f)/128.0;
    float z=point.w+sweepProfile(vec3(q,arc,0))*point.z*u_surface.w;
    float coverage=1.0-smoothstep(-pixel,pixel,d);
    if(z>bestDepth){bestDepth=z;side=q;along=arc;width=point.z;tangent=tan;normalAcross=dist>.00001?delta/dist*direction:across;alpha=coverage;slopeAlong=f>.001&&f<.999?(b.w-a.w)/sqrt(len2):0.0;}
  }
  vec3 color=u_palette0;
  if(bestDepth>-99.0){
    float e=.006;
    float left=sweepProfile(vec3(clamp(side-e,-.999,.999),along,0));
    float right=sweepProfile(vec3(clamp(side+e,-.999,.999),along,0));
    float slope=(right-left)/(2.0*e)*u_surface.w;
    vec2 grad=normalAcross*slope+tangent*slopeAlong;
    vec3 normal=normalize(vec3(-grad,1.0));
    vec3 ink=shade(normal,p,side,along,bestDepth);
    color=mix(color,ink,alpha);
  }
  color=srgb(color);
  float grain=(hash(gl_FragCoord.xy+u_seed)-.5)*.004;
  outColor=vec4(clamp(color+grain,0.0,1.0),1.0);
}`;
