"""Nowhere Display 0.6: purpose-drawn continuous cubic outlines compiled to TrueType curves.
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
 OUTLINES.clear();bold=style=='Bold';t=142 if bold else 106;h=116 if bold else 92;w=650 if bold else 626;changes={}
 def put(c,width,out,holes=()):
  cs=[(*out,False)]+[(*p,True) for p in holes];g=geometry(cs);assert g.is_valid and not g.is_empty,c;OUTLINES[c]=cs;changes[c]=(width,g)
 put('0',w,oval(0,-8,w,736),[oval(t,h-8,w-2*t,736-2*h)])
 # A short, flat foot balances 1 without borrowing slab-serif details elsewhere.
 v=472 if bold else 450;x=230;head=145
 one=contour((0,567),(x-38,720),(x+t,720),(x+t,h),(v,h),(v,0),(38,0),(38,h),(x,h),(x,565),(65,474),(0,567));put('1',v,one)
 # Continuous top bowl, diagonal and flat foot of 2.
 two=contour((0,557),((46,667),(143,728),(w*.49,728)),((w*.82,728),(w,651),(w,526)),((w,422),(w*.86,363),(w*.71,293)),(t*1.40,h),(w,h),(w,0),(0,0),(0,h),((w*.23,257),(w*.44,359),(w*.62,443)),((w*.75,508),(w-t,534),(w-t,567)),((w-t,604),(w*.69,628),(w*.49,628)),((w*.30,628),(t*.96,583),(t*.82,513)),(0,557));put('2',w,two)
 # 3 has two continuous bowls and a short central return, without an angular notch.
 three=contour((13,625),((109,699),(210,728),(w*.49,728)),((w*.80,728),(w-10,658),(w-10,549)),((w-10,463),(w*.84,400),(w*.73,370)),((w*.91,340),(w,274),(w,185)),((w,61),(w*.79,-8),(w*.47,-8)),((w*.25,-8),(85,29),(0,100)),(70,183),((159,116),(w*.31,96),(w*.47,96)),((w*.69,96),(w-t,137),(w-t,199)),((w-t,266),(w*.68,310),(w*.47,310)),(w*.30,310),(w*.30,410),(w*.47,410),((w*.68,410),(w-t,456),(w-t,536)),((w-t,595),(w*.69,628),(w*.49,628)),((w*.33,628),(153,607),(79,543)),(13,625));put('3',w,three)
 # Closed four, shared stem weight and a large triangular counter.
 right=w-84;left=right-t;cross=256
 four=contour((left-20,720),(right,720),(right,cross),(w,cross),(w,cross-h),(right,cross-h),(right,0),(left,0),(left,cross-h),(0,cross-h),(0,cross),(left-20,720))
 hole=contour((t*.96,cross),(left,cross),(left,566),(t*.96,cross));put('4',w,four,[hole])
 five=contour((w-12,720),(w-12,720-h),(t+25,720-h),(t+10,440),((w*.38,456),(w*.43,462),(w*.51,462)),((w*.83,462),(w,376),(w,230)),((w,80),(w*.79,-8),(w*.48,-8)),((w*.26,-8),(97,26),(8,91)),(70,179),((154,124),(w*.32,96),(w*.48,96)),((w*.69,96),(w-t,146),(w-t,230)),((w-t,316),(w*.70,360),(w*.49,360)),((w*.35,360),(w*.25,341),(t*.87,321)),(0,354),(24,720),(w-12,720));put('5',w,five)
 # 6/9: identical reflected bowl construction; substantially taller counters.
 six=contour((w*.86,679),(w*.80,578),((w*.66,622),(w*.51,638),(w*.40,585)),((w*.27,526),(t+10,436),(t,367)),((w*.30,428),(w*.42,462),(w*.54,462)),((w*.82,462),(w,376),(w,231)),((w,87),(w*.80,-8),(w*.50,-8)),((w*.15,-8),(0,102),(0,307)),((0,476),(w*.14,615),(w*.33,689)),((w*.49,744),(w*.69,729),(w*.86,679)))
 sh=oval(t,96,w-2*t,270)
 put('6',w,six,[sh])
 def reflect(path):
  st,cmd=path;pt=lambda p:(w-p[0],720-p[1]);return (pt(st),[pt(c) if len(c)==2 else tuple(pt(p) for p in c) for c in cmd])
 put('9',w,reflect(six),[reflect(sh)])
 seven=contour((0,720),(w,720),(w,720-h),(w*.40,0),(w*.17,0),(w-t*1.07,720-h),(0,720-h),(0,720));put('7',w,seven)
 # 8: relaxed waist and two counters with the same curved vocabulary as 6/9.
 eight=contour((w*.50,728),((w*.79,728),(w-20,656),(w-20,549)),((w-20,469),(w*.84,409),(w*.73,374)),((w*.91,338),(w,270),(w,191)),((w,63),(w*.79,-8),(w*.50,-8)),((w*.21,-8),(0,63),(0,191)),((0,270),(w*.09,338),(w*.27,374)),((w*.16,409),(20,469),(20,549)),((20,656),(w*.21,728),(w*.50,728)))
 put('8',w,eight,[oval(t,92,w-2*t,232),oval(t+9,423,w-2*t-18,207)])
 sw=335;st=98 if bold else 78
 slash=contour((0,0),(st,0),(sw,720),(sw-st,720),(0,0));put('/',sw,slash)
 return changes
exec((Path(__file__).with_name('compile.py')).read_text())
