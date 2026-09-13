"""Nowhere Display 0.7: purpose-drawn continuous cubic outlines compiled to TrueType curves.
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
def curve_glyph(cs,shift=0):
 pen=TTGlyphPen(None)
 for st,cmd,hole in cs:
  pts=bezier(st,cmd);area=sum(a[0]*b[1]-b[0]*a[1] for a,b in zip(pts,pts[1:]+pts[:1]))
  q=Cu2QuPen(pen,max_err=.5,reverse_direction=False)
  if (area>0)!=hole:q=ReverseContourPen(q)
  q.moveTo((st[0]+SB+shift,st[1]))
  for c in cmd:
   if len(c)==2:q.lineTo((c[0]+SB+shift,c[1]))
   else:q.curveTo(*[(p[0]+SB+shift,p[1]) for p in c])
  q.closePath()
 return pen.glyph()
def redraw(style,f):
 OUTLINES.clear();bold=style=='Bold';t=138 if bold else 102;hair=110 if bold else 88;w=604 if bold else 565
 # Continuous bowl and rising neck. Upper flag has a shallow lift and a flat vertical end.
 outer=contour((w*.93,735),(w*.93,735-hair),((w*.77,735-hair),(w*.59,650-hair),(w*.40,637-hair)),((w*.27,627-hair),(t+10,464),(t,397)),((w*.30,472),(w*.42,518),(w*.55,518)),((w*.83,518),(w,422),(w,258)),((w,91),(w*.80,-8),(w*.50,-8)),((w*.18,-8),(0,99),(0,299)),((0,470),(48,604),(w*.24,669)),((w*.43,735),(w*.70,699),(w*.93,735)))
 hole=oval(t,94,w-2*t,320)
 cs=[(*outer,False),(*hole,True)];g=geometry(cs);assert g.is_valid
 OUTLINES['б']=cs
 return {'б':(w,g)}
exec((Path(__file__).with_name('compile.py')).read_text())
