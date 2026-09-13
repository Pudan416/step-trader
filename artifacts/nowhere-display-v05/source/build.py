"""Nowhere Display 0.5: purpose-drawn continuous cubic outlines compiled to TrueType curves.
Requires fonttools, shapely, brotli. Run this file to rebuild both weights.
"""
from pathlib import Path
import json, math
from shapely.geometry import Polygon,LineString
from shapely.ops import unary_union
from shapely.affinity import translate
from shapely import set_precision
from fontTools.ttLib import TTFont
from fontTools.feaLib.builder import addOpenTypeFeaturesFromString
from fontTools.pens.ttGlyphPen import TTGlyphPen
from fontTools.pens.cu2quPen import Cu2QuPen
from fontTools.pens.reverseContourPen import ReverseContourPen
from geometry import shape,glyph,bezier
OUT=Path(__file__).resolve().parents[1];SB=44;OUTLINES={}
def contour(start,*cmd):return (start,list(cmd))
def oval(x,y,w,h):
 k=.55228475;cx=x+w/2;cy=y+h/2;rx=w/2;ry=h/2
 return contour((x+w,cy),((x+w,cy+k*ry),(cx+k*rx,y+h),(cx,y+h)),((cx-k*rx,y+h),(x,cy+k*ry),(x,cy)),((x,cy-k*ry),(cx-k*rx,y),(cx,y)),((cx+k*rx,y),(x+w,cy-k*ry),(x+w,cy)))
def geometry(cs):
 result=[]
 for st,cmd,hole in cs:
  p=Polygon(bezier(st,cmd));assert p.is_valid,('invalid',st)
  result.append((p,hole))
 return unary_union([p for p,h in result if not h]).difference(unary_union([p for p,h in result if h]))
def curve_glyph(cs):
 pen=TTGlyphPen(None)
 for st,cmd,hole in cs:
  pts=bezier(st,cmd);area=sum(a[0]*b[1]-b[0]*a[1] for a,b in zip(pts,pts[1:]+pts[:1]))
  q=Cu2QuPen(pen,max_err=.5,reverse_direction=False)
  if (area>0)!=hole:q=ReverseContourPen(q)
  q.moveTo((st[0]+SB,st[1]))
  for c in cmd:
   if len(c)==2:q.lineTo((c[0]+SB,c[1]))
   else:q.curveTo(*[(p[0]+SB,p[1]) for p in c])
  q.closePath()
 return pen.glyph()
def redraw(style,f):
 OUTLINES.clear();bold=style=='Bold';extra=48 if bold else 0;t=144 if bold else 104;hair=112 if bold else 91;cap=150 if bold else 112;cm=f.getBestCmap();changes={}
 def put(c,w,outer,holes=(),extras=()):
  cs=[(*outer,False)]+[(*h,True) for h in holes]+[(*p,False) for p in extras];g=geometry(cs);assert g.is_valid and not g.is_empty,c
  changes[c]=(w,g);OUTLINES[c]=cs
 # e: uninterrupted outer aperture and an independent, spacious upper counter.
 w=560+extra;barY=238;barH=96 if bold else 82;edge=130 if bold else 101
 ec=contour((w,barY),(edge,barY),((edge+9,142),(w*.34,92),(w*.52,92)),((w*.69,92),(w*.78,116),(w*.84,145)),(w*.96,78),((w*.85,20),(w*.69,-8),(w*.51,-8)),((w*.19,-8),(0,84),(0,253)),((0,420),(w*.20,518),(w*.51,518)),((w*.83,518),(w,417),(w,278)),(w,barY))
 hole=contour((edge,barY+barH),(w-edge,barY+barH),((w-edge-10,401),(w*.67,426),(w*.51,426)),((w*.35,426),(edge+14,395),(edge,barY+barH)))
 for c in 'eе':put(c,w,ec,[hole])
 ds=100 if bold else 84;dots=[oval(w*.31-ds/2,616,ds,ds),oval(w*.69-ds/2,616,ds,ds)]
 put('ё',w,ec,[hole],dots)
 # Shoulder family: continuous external arch, separate internal return.
 def shoulder(w,asc=510):
  return contour((0,0),(0,asc),(t,asc),(t,449),((t+45,496),(w*.38,518),(w*.53,518)),((w*.86,518),(w,420),(w,280)),(w,0),(w-t,0),(w-t,281),((w-t,378),(w*.72,518-hair),(w*.54,518-hair)),((w*.33,518-hair),(t,363),(t,261)),(t,0),(0,0))
 w=555+extra
 put('n',w,shoulder(w));put('h',w,shoulder(w,720))
 mw=870+extra;mid=(mw-t)/2;innerTop=518-hair
 a1=(t+mid)/2;a2=(mid+t+mw-t)/2
 mc=contour((0,0),(0,510),(t,510),(t,448),((t+38,493),(a1-62,518),(a1,518)),((mid-23,518),(mid+26,492),(mid+t*.62,448)),((mid+t+31,491),(a2-68,518),(a2,518)),((mw-62,518),(mw,421),(mw,283)),(mw,0),(mw-t,0),(mw-t,289),((mw-t,377),(a2+66,innerTop),(a2,innerTop)),((mid+t+24,innerTop),(mid+t,363),(mid+t,273)),(mid+t,0),(mid,0),(mid,289),((mid,377),(a1+66,innerTop),(a1,innerTop)),((t+31,innerTop),(t,359),(t,268)),(t,0),(0,0))
 put('m',mw,mc)
 rw=340+extra
 rc=contour((0,0),(0,510),(t,510),(t,444),((t+51,497),(rw-53,524),(rw,514)),(rw,514-hair),((rw-69,426),(t,373),(t,270)),(t,0),(0,0));put('r',rw,rc)
 # Single-storey g. The stem flows directly into the descending bowl.
 w=580+extra;right=w-t;cx=w*.47
 gc=contour((right,510),(w,510),(w,-20),((w,-153),(w*.80,-218),(w*.51,-218)),((w*.29,-218),(w*.11,-170),(w*.035,-108)),(w*.15,-28),((w*.24,-78),(w*.37,-112),(w*.51,-112)),((w*.72,-112),(right,-78),(right,-9)),(right,62),((w*.73,12),(w*.63,-8),(cx,-8)),((w*.16,-8),(0,90),(0,255)),((0,421),(w*.17,518),(cx,518)),((w*.66,518),(w*.77,488),(right,441)),(right,510))
 gh=oval(t,95,w-2*t,318);put('g',w,gc,[gh])
 # Cyrillic k: purposeful straight terminals; relieved crotch, asymmetrical diagonals.
 w=510+extra;neck=238;arm=192 if bold else 139;leg=200 if bold else 148
 kc=contour((0,0),(0,510),(t,510),(t,304),(w-arm,510),(w,510),(t+57,neck+27),(w,0),(w-leg,0),(t,203),(t,0),(0,0));put('к',w,kc)
 # G: continuous open bowl and return; no pasted-on connector.
 w=770+extra;bar=128 if bold else 104;inset=cap
 gc=contour((w*.94,550),(w*.80,500),((w*.72,590),(w*.63,616),(w*.49,616)),((w*.25,616),(inset,524),(inset,360)),((inset,197),(w*.25,104),(w*.49,104)),((w*.67,104),(w*.80,154),(w-inset,218)),(w-inset,300),(w*.55,300),(w*.55,300+bar),(w,300+bar),(w,197),((w,73),(w*.71,-8),(w*.49,-8)),((w*.17,-8),(0,132),(0,360)),((0,588),(w*.18,728),(w*.49,728)),((w*.71,728),(w*.88,658),(w*.94,550)))
 put('G',w,gc)
 # Ampersand: a continuous outside with a clear right arm, two designed counters.
 w=690+extra
 ac=contour((w-12,0),(w-155,0),(w-214,68),((w-278,16),(w*.42,-10),(w*.31,-10)),((w*.09,-10),(0,69),(0,200)),((0,295),(63,359),(146,409)),((102,465),(78,504),(78,558)),((78,661),(151,728),(267,728)),((384,728),(450,660),(450,560)),((450,482),(403,426),(313,376)),(w-225,204),((w-186,251),(w-162,310),(w-148,370)),(w-30,370),((w-48,264),(w-81,184),(w-142,116)),(w-12,0))
 ah1=contour((235,455),((304,497),(337,522),(337,566)),((337,605),(311,629),(267,629)),((225,629),(197,603),(197,565)),((197,530),(211,493),(235,455)))
 ah2=contour((218,325),((152,284),(116,250),(116,204)),((116,137),(166,99),(239,99)),((305,99),(350,123),(396,158)),(218,325))
 if bold:
  ah1=contour((243,474),((300,505),(326,534),(326,566)),((326,596),(303,614),(268,614)),((235,614),(215,595),(215,566)),((215,538),(227,507),(243,474)))
  ah2=contour((219,309),((166,276),(141,245),(141,204)),((141,150),(178,124),(240,124)),((289,124),(329,139),(365,166)),(219,309))
 put('&',w,ac,[ah1,ah2])
 # @ is one spiral outline around an open white channel; only the a counter is a hole.
 w=900+extra;at=92 if bold else 77;it=110 if bold else 87;ix=220;iy=184;iw=390;stem=ix+iw;outerRight=w
 ac=contour((w*.68,25),((w*.56,-4),(w*.47,-14),(w*.39,-8)),((w*.15,-8),(0,130),(0,365)),((0,605),(w*.19,768),(w*.50,768)),((w*.82,768),(w,608),(w,377)),((w,218),(w*.87,145),(w*.76,145)),((w*.69,145),(stem-15,169),(stem-it*.45,216)),((stem-it-22,185),(ix+248,172),(ix+195,172)),((ix+74,172),(ix,256),(ix,390)),((ix,518),(ix+72,604),(ix+188,604)),((ix+239,604),(stem-it-32,583),(stem-it,548)),(stem-it,589),(stem,589),(stem,289),((stem,242),(stem+35,229),(w*.77,229)),((w*.87,229),(w-at,284),(w-at,377)),((w-at,562),(w*.75,768-at),(w*.50,768-at)),((w*.24,768-at),(at,575),(at,365)),((at,179),(w*.21,at-8),(w*.41,at-8)),((w*.51,at-8),(w*.59,at+4),(w*.68,at+30)),(w*.68,25))
 ah=oval(ix+it-10,iy+it,iw-2*it+10,306-it);put('@',w,ac,[ah])
 # f/t: horizontal terminal cuts, no angled wedge at the hook.
 w=355+extra;x=80
 fc=contour((x,0),(x,370),(0,370),(0,370+hair),(x,370+hair),(x,552),((x,673),(x+75,728),(w,728)),(w,728-hair),((x+t+28,728-hair),(x+t,599),(x+t,545)),(x+t,370+hair),(w,370+hair),(w,370),(x+t,370),(x+t,0),(x,0));put('f',w,fc)
 w=345+extra;x=90
 tc=contour((x,650),(x+t,650),(x+t,465),(w,465),(w,465-hair),(x+t,465-hair),(x+t,152),((x+t,106),(x+t+26,92),(w,106)),(w,8),((x+40,-36),(x,13),(x,139)),(x,465-hair),(0,465-hair),(0,465),(x,465),(x,650));put('t',w,tc)
 return changes
exec((Path(__file__).with_name('compile.py')).read_text())
