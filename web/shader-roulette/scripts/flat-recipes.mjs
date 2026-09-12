// Shader Park source recipes. Scalar math also produces the CPU distance functions.
// Each recipe is a closed silhouette in a unit disc. n=lobes, w=warp, h=hole, t=thickness.
export const recipes = {
  rosette: `
    let a = atan(y, x); let r = sqrt(x*x+y*y);
    let edge = .58 + (.10+w*.12)*cos(n*a+w*r*3) + .025*cos(2*n*a);
    let d = r-edge;
    setSDF(max(d, h*.65-r));`,
  spark: `
    let r = sqrt(x*x+y*y); let a = atan(y, x);
    let edge = .32 + .46*pow(.5+.5*cos(n*a+w*.7), 1.3+w*3);
    setSDF(r-edge);`,
  organism: `
    let d = sqrt(x*x+y*y)-.32;
    for(let i=0;i<5;i++) {
      let a = i*1.2566370614+w*2;
      let cx = cos(a)*(.24+.05*sin(i*n));
      let cy = sin(a)*(.27+.04*cos(i*n));
      let rx = .24+.065*sin(i*2+n);
      let ry = .28+.06*cos(i*3+n);
      let dx = (x-cx)/rx; let dy = (y-cy)/ry;
      let b = (sqrt(dx*dx+dy*dy)-1)*min(rx,ry);
      d = .5*(d+b-sqrt((d-b)*(d-b)+.006+w*.008));
    }
    setSDF(d);`,
  loop: `
    let qx = x + w*.20*sin(y*4);
    let qy = y*(1.05+w*.32);
    let power = 2 + (n-3)*.55;
    let r = pow(pow(abs(qx),power)+pow(abs(qy),power),1/power);
    let d = abs(r-.55)-t;
    setSDF(d);`,
  crescent: `
    let qy = y*(1.02+w*.3);
    let body = sqrt(x*x+qy*qy)-.74;
    let cx = x-(.23+w*.23); let cy=qy-h*.25;
    let cut = sqrt(cx*cx+cy*cy)-(.62+h*.25);
    setSDF(max(body,-cut));`,
  emblem: `
    let d=10;
    for(let i=0;i<8;i++) {
      // Short unused arms remain inside the central body, keeping the loop static.
      let active = step(i+.5,n);
      let a=i*6.28318530718/n;
      let qx=cos(a)*x+sin(a)*y;
      let qy=(0-sin(a))*x+cos(a)*y;
      let dx=abs(qx-.24*active)-(.16+.22*active);
      let dy=abs(qy)-(.07+t*.36);
      let bx=max(dx,0); let by=max(dy,0);
      let b=sqrt(bx*bx+by*by)+min(max(dx,dy),0)-w*.09;
      d=min(d,b);
    }
    let cut=sqrt(x*x+y*y)-(.10+h*.5);
    setSDF(max(d,-cut));`,
  fan: `
    let a=atan(y,x); let r=sqrt(x*x+y*y);
    let angle=1.45+w*.6;
    let scallop=.67+.07*cos(n*a*1.6);
    let d=max(r-scallop,(abs(a)-angle)*.4);
    setSDF(max(d,(.14+h*.35)-r));`,
  ribbon: `
    let d=10;
    for(let i=0;i<18;i++) {
      let u=i/18; let v=(i+1)/18;
      let ax=(u-.5)*1.24; let bx=(v-.5)*1.24;
      let ay=sin(u*6.28318530718+w*2)*(.20+w*.21);
      let by=sin(v*6.28318530718+w*2)*(.20+w*.21);
      let px=x-ax; let py=y-ay; let vx=bx-ax; let vy=by-ay;
      let k=clamp((px*vx+py*vy)/(vx*vx+vy*vy),0,1);
      let dx=px-vx*k; let dy=py-vy*k;
      d=min(d,sqrt(dx*dx+dy*dy)-t);
    }
    setSDF(d);`,
};
