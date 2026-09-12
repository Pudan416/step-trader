// Compact, bounded surfaces. Shader Park compiles the same contour definitions used by CPU QA.
export const membranes = {
  aeolian: `
    let r=sqrt(x*x+y*y); let a=atan(y,x);
    let edge=.62+.13*sin(n*a+r*w*6)+.035*cos((n+1)*a);
    let outside=r-edge;
    let opening=r-(.13+h*.45);
    setSDF(max(outside,-opening));`,
  mantle: `
    let qx=x*(1+w*.2); let qy=y*(1-w*.2);
    let r=sqrt(qx*qx+qy*qy); let a=atan(qy,qx);
    let edge=.64+.075*cos(a*(n+5))+.04*sin(3*a+w*4);
    setSDF(r-edge);`,
  obsidian: `
    let qx=x+y*.18; let qy=y-x*.12;
    let shape=pow(pow(abs(qx),4)+pow(abs(qy),4),.25)-.53;
    let cx=x-(.18+w*.3); let cy=y-(.1-h*.4);
    let cut=sqrt(cx*cx+cy*cy)-(.20+h*.35);
    setSDF(max(shape,-cut));`,
  elytra: `
    let a=atan(y,x); let r=sqrt(x*x+y*y);
    let edge=.39+.33*pow(abs(cos(a)),.7)+.06*sin(n*a+w*3)*sin(a)*sin(a);
    let d=r-edge;
    let cut=sqrt(x*x+(y+.20)*(y+.20))-(.11+h*.25);
    setSDF(max(d,-cut));`,
};
