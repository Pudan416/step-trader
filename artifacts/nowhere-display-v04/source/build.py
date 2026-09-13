"""Nowhere Display 0.4. Optical redraw of audited components; base 0.3 retained.
Run with fonttools, shapely, brotli. No external font outlines used.
"""
from pathlib import Path
import math,json
from shapely.geometry import Polygon,LineString,box
from shapely import set_precision
from shapely.ops import unary_union
from shapely.affinity import translate,scale
from fontTools.ttLib import TTFont
from fontTools.feaLib.builder import addOpenTypeFeaturesFromString
from geometry import shape,glyph,ellipse,bezier,fit
OUT=Path(__file__).resolve().parents[1]
SB=44

def path(start,commands):return Polygon(bezier(start,commands))
def stroke(start,commands,t):return LineString(bezier(start,commands)).buffer(t/2,cap_style=2,join_style=1)
def outer(g):return unary_union([Polygon(p.exterior) for p in ([g] if g.geom_type=='Polygon' else g.geoms)])
def counters(g):return [Polygon(r) for p in ([g] if g.geom_type=='Polygon' else g.geoms) for r in p.interiors]
def smooth(g,r=5):return g.buffer(r,join_style=1).buffer(-r,join_style=1)

def redraw(style,f):
 bold=style=='Bold';extra=48 if bold else 0;t=150 if bold else 108;cap=158 if bold else 118;thin=118 if bold else 92
 cm=f.getBestCmap();changes={}
 def old(c):return translate(shape(f,cm[ord(c)]),xoff=-SB)
 def put(c,g,w=None):
  if w is None:w=f['hmtx'][cm[ord(c)]][0]-2*SB
  assert g.is_valid and not g.is_empty,c
  changes[c]=(w,g)
 def uform(w,h,st):
  b=st-8;cy=260 if h>600 else 218
  return path((0,h),[(st,h),(st,cy),((st,b+65),(w*.29,b),(w/2,b)),((w*.71,b),(w-st,b+65),(w-st,cy)),(w-st,h),(w,h),(w,cy),((w,62),(w*.77,-8),(w/2,-8)),((w*.23,-8),(0,62),(0,cy)),(0,h)])
 put('U',uform(700+extra,720,cap))
 w=580+extra
 put('J',stroke((cap/2,208),[((cap/2,30),(w-cap/2,30),(w-cap/2,208)),(w-cap/2,720)],cap))
 # Fit J's top and round overshoot deliberately; no clipping rectangles.
 put('J',fit(changes['J'][1],w,-8,720))
 def shoulder(w):
  # Independent inner/outer curves keep the apex at the common 518 overshoot.
  return path((0,0),[(0,510),(t,510),(t,461),((t+37,496),(w*.40,518),(w*.54,518)),((w*.86,518),(w,431),(w,279)),(w,0),(w-t,0),(w-t,275),((w-t,365),(w*.71,518-thin),(w*.53,518-thin)),((w*.30,518-thin),(t,370),(t,276)),(t,0),(0,0)])
 w=555+extra;n=shoulder(w);put('n',n);put('h',n.union(box(0,0,t,720)))
 mw=870+extra;part=(mw+t)/2;put('m',unary_union([shoulder(part),translate(shoulder(part),xoff=part-t)]))
 # Lowercase u uses the same round family, with its terminal on the baseline.
 put('u',uform(w,510,t).union(box(w-t,0,w,270)))
 rw=340+extra
 put('r',path((0,0),[(0,510),(t,510),(t,459),((t+48,509),(rw-55,526),(rw,513)),(rw,513-thin),((rw-50,420),(t,425),(t,280)),(t,0),(0,0)]))
 # Descenders and terminals are single continuous strokes, with no lower clipping.
 w=580+extra;st=t;body=old('g').intersection(box(-100,0,1000,1000))
 tail=stroke((w-st/2,275),[(w-st/2,-40),((w-st/2,-210),(w*.37,-242),(st*.65,-132))],st)
 tail=fit(tail,w-st*.12,-218,330)
 put('g',body.union(tail))
 # A compact j hook reduces the left overhang while preserving its dot.
 jw=260+extra;dot=ellipse(jw-t,616,t,114)
 jbody=stroke((jw-t/2,510),[(jw-t/2,-68),((jw-t/2,-183),(jw*.44,-211),(t*.45,-144))],t)
 put('j',jbody.union(dot),jw)
 # Continuous f and t terminals.
 fw=355+extra
 fbody=stroke((76+t/2,0),[(76+t/2,554),((76+t/2,657),(fw-83,702),(fw-22,653))],t)
 put('f',fbody.union(box(0,370,350+extra,370+thin)),fw)
 tw=345+extra
 tbody=stroke((100+t/2,650),[(100+t/2,151),((100+t/2,35),(tw-65,25),(tw-16,69))],t)
 put('t',tbody.union(box(0,370,tw,370+thin)),tw)
 # Cyrillic U: right diagonal continues down-left; distinct from Latin Y.
 uw=755+extra
 cyru=stroke((uw-64,720),[(uw*.40,122),((uw*.34,23),(uw*.21,-3),(uw*.09,30))],cap)
 cyru=cyru.union(stroke((60,720),[(uw*.49,322)],cap))
 put('У',fit(cyru,uw,-8,720))
 kw=510+extra
 put('к',box(0,0,t,510).union(stroke((kw-44,510),[(t*.72,242),(kw-38,0)],t)).intersection(box(0,0,kw+8,510)),kw)
 # One continuous top-left join for both cases of Cyrillic L and D.
 def el(w,h,st):
  return Polygon([(0,0),(st,0),(w*.46,h-st),(w-st,h-st),(w-st,0),(w,0),(w,h),(w*.39,h)])
 for c,w,h,st in [('Л',745+extra,720,cap),('л',round(745*.78)+extra,510,t)]:put(c,el(w,h,st),w)
 for c,base,w,h,st in [('Д','Л',825+extra,720,cap),('д','л',round(825*.78)+extra,510,t)]:
  g=translate(changes[base][1],xoff=40 if h==720 else 31)
  foot=105 if h==720 else 84;put(c,unary_union([g,box(0,0,w,st*.88),box(0,-foot,st*.85,st*.65),box(w-st*.85,-foot,w,st*.65)]),w)
 # Rebuild lowercase e counter and aperture with optical room in both weights.
 ew=560+extra;edge=145 if bold else 108;bar=94 if bold else 88
 e=ellipse(0,-8,ew,526).difference(ellipse(edge,edge-8,ew-2*edge,526-2*edge))
 e=e.difference(box(ew*.62,118,ew+10,258))
 e=e.union(box(edge*.75,232,ew,232+bar))
 # Upper opening is explicitly drawn: Bold doesn't inherit a squeezed automatic expansion.
 upper=path((edge,232+bar),[((edge+20,400),(ew*.35,422),(ew/2,422)),((ew*.70,422),(ew-edge-20,400),(ew-edge,232+bar)),(edge,232+bar)])
 e=e.difference(upper)
 put('e',e,ew);put('е',e,ew)
 dotsize=122 if bold else 100
 put('ё',e.union(ellipse(ew*.30-dotsize/2,612,dotsize,dotsize)).union(ellipse(ew*.70-dotsize/2,612,dotsize,dotsize)),ew)
 # Expand dense Cyrillic counters; keep outside silhouettes and original advances.
 if bold:
  for c in 'въыьбБВЬЪЫ':
   g=old(c);hs=counters(g)
   if not hs:continue
   opened=[]
   for hole in hs:
    b=hole.bounds;target=112 if c.islower() else 130
    opened.append(scale(hole,xfact=1.04,yfact=max(1,target/(b[3]-b[1])),origin='centroid'))
   put(c,outer(g).difference(unary_union(opened)))
  for c in 'AА':
   g=old(c);h=counters(g)[0]
   put(c,outer(g).difference(scale(h,xfact=1.40,yfact=1.55,origin='centroid')))
 # Cyrillic phi gets a real ascender/descender and optical counters.
 pw=round(865*.78)+extra;ph=ellipse(0,0,pw,510).difference(ellipse(116 if bold else 86,92,pw-2*(116 if bold else 86),326))
 put('ф',ph.union(box(pw/2-t/2,-180,pw/2+t/2,710)),pw)
 # Smooth question mark, with precisely two connected components.
 qw=490+extra;qt=140 if bold else 108
 hook=stroke((qt*.6,601),[((qt*.92,745),(qw-qt*.65,748),(qw-qt*.60,604)),((qw-qt*.58,525),(qw*.5,506),(qw*.5,432)),(qw*.5,230)],qt)
 hook=fit(hook,qw,230,728)
 put('?',hook.union(ellipse(qw/2-qt/2,-2,qt,qt)),qw)
 # Ampersand: clean outside, exactly two intentional counters, continuous waist.
 ag=old('&');hs=sorted([h for h in counters(ag) if h.area>1000],key=lambda h:h.centroid.y)
 outside=smooth(outer(ag),20)
 put('&',outside.difference(unary_union(hs)))
 # Open @ ring with a continuous exit from its inner stem, separated from outer ring.
 aw=900+extra;at=106 if bold else 88
 ring=ellipse(0,-8,aw,776).difference(ellipse(at,at-8,aw-2*at,776-2*at))
 ring=ring.difference(box(aw*.69,-20,aw+20,214))
 iw=440;ix=210+(extra/2);iy=180;it=106 if bold else 86
 inner=ellipse(ix,iy,iw,420).difference(ellipse(ix+it,iy+it,iw-2*it,420-2*it))
 stemx=ix+iw-it/2
 exitstroke=stroke((stemx,590),[(stemx,300),((stemx,235),(aw-at/2,225),(aw-at/2,355))],it)
 put('@',unary_union([ring,inner,exitstroke]),aw)
 # G: continuous lower-right connection instead of a protruding rectangle.
 gw=770+extra;gt=cap
 gg=ellipse(0,-8,gw,736).difference(ellipse(gt,gt-8,gw-2*gt,736-2*gt))
 gg=gg.difference(box(gw*.66,205,gw+10,525))
 bar=box(gw*.56,300,gw,300+110+(22 if bold else 0))
 join=path((gw,300),[(gw,215),((gw-18,160),(gw-70,115),(gw-gt,100)),(gw-gt,300),(gw,300)])
 put('G',unary_union([gg,bar,join]),gw)
 qg=old('Q');ow=780+extra
 oval=old('O');tail=stroke((ow*.64,155),[((ow*.69,122),(ow*.86,-22),(ow+5,-92))],124 if bold else 100)
 put('Q',oval.union(tail),ow)
 # Common punctuation dots: weight changes diameter, never squash each whole glyph.
 ds=148 if bold else 118;dot=ellipse(0,-2,ds,ds)
 for c in '.:…!':
  if c=='.':put(c,dot,ds)
  elif c==':':put(c,dot.union(translate(dot,yoff=360)),ds)
  elif c=='…':put(c,unary_union([translate(dot,xoff=i*(ds+88)) for i in range(3)]),3*ds+176)
  else:put(c,dot.union(box((ds-t)/2,220,(ds+t)/2,720)),ds)
 comma=dot.union(stroke((ds*.70,ds*.40),[(ds*.17,-120)],80 if bold else 68))
 put(',',comma,ds+24);put(';',comma.union(translate(dot,yoff=360)),ds+24)
 apost=translate(comma,yoff=615);left=translate(scale(comma,xfact=-1,yfact=-1,origin=(ds/2,0)),yoff=615)
 for c,g in [('’',apost),('‘',left)]:put(c,g,ds+20)
 for c,g in [('”',apost),('“',left)]:
  offset=ds+64;put(c,g.union(translate(g,xoff=offset)),2*ds+84)
 put("'",box(0,515,95+(32 if bold else 0),720),95+(32 if bold else 0))
 sw=95+(32 if bold else 0);put('"',box(0,515,sw,720).union(box(sw+70,515,2*sw+70,720)),2*sw+70)
 # Number and percent symbols: room between separate parts even at Bold.
 nw=1110+extra;nn=old('N');nr=ellipse(780+extra,442,295,278).difference(ellipse(780+extra+72,514,151,134))
 put('№',nn.union(nr).union(box(780+extra,316,1075+extra,384)),nw)
 pct=old('%');hs=counters(pct)
 put('%',outer(pct).difference(unary_union([scale(h,xfact=1.32 if bold else 1,yfact=1.32 if bold else 1,origin='centroid') for h in hs])))
 # Normalize Cyrillic Z round overshoot while retaining its wider proportions.
 for c in 'Зз':
  w=f['hmtx'][cm[ord(c)]][0]-2*SB;put(c,fit(old(c),w,-8,728 if c=='З' else 518),w)
 return changes

def build(style):
 f=TTFont(OUT/'source'/f'base-{style}.ttf');cm=f.getBestCmap();changes=redraw(style,f)
 for c,(w,g) in changes.items():
  g=set_precision(translate(g,xoff=SB),1);f['glyf'][cm[ord(c)]]=glyph(g);f['hmtx'][cm[ord(c)]]=(round(w+2*SB),round(g.bounds[0]))
 # Work on the compiled, integer-coordinate outlines for spacing and safety.
 shapes={n:shape(f,n) for n in f.getGlyphOrder()};pairs={}
 for lookup in f['GPOS'].table.LookupList.Lookup:
  for st in lookup.SubTable:
   for a,ps in zip(st.Coverage.glyphs,st.PairSet):
    for rec in ps.PairValueRecord:pairs[(a,rec.SecondGlyph)]=rec.Value1.XAdvance
 chars=[c for c in cm if not chr(c).isspace()];changed={cm[ord(c)] for c in changes}
 # Refit affected alphabet pairs against profiles that include descenders and accents.
 letters=[c for c in chars if chr(c).isalpha()];profiles={}
 for c in letters:
  g=shapes[cm[c]];profile={}
  for y in range(-240,921,12):
   cut=g.intersection(LineString([(-500,y),(2200,y)]))
   if not cut.is_empty:profile[y]=(cut.bounds[0],cut.bounds[2])
  profiles[c]=profile
 for a in letters:
  for b in letters:
   an,bn=cm[a],cm[b]
   if an not in changed and bn not in changed:continue
   common=profiles[a].keys()&profiles[b].keys()
   if common:
    gap=min(f['hmtx'][an][0]-profiles[a][y][1]+profiles[b][y][0] for y in common)
    pairs[(an,bn)]=max(-75,min(120,round((82-gap)/2)*2))
 # Exact geometry safety applies to ALL encoded pairs, including punctuation.
 safety=0
 for a in chars:
  for b in chars:
   an,bn=cm[a],cm[b];s1=shapes[an];s2=shapes[bn];adv=f['hmtx'][an][0];v=pairs.get((an,bn),0)
   if s1.bounds[2]+26 < adv+v+s2.bounds[0]:continue
   moved=translate(s2,xoff=adv+v)
   if s1.distance(moved)<24:
    original=v
    for delta in range(2,302,2):
     if s1.distance(translate(s2,xoff=adv+v+delta))>=24:v+=delta;break
    else:raise AssertionError(('spacing',an,bn))
    pairs[(an,bn)]=v;safety+=v!=original
 # Refresh existing tabular alternate glyphs without duplicating glyph order.
 nums=[ord(c) for c in '0123456789'];tabwidth=max(f['hmtx'][cm[c]][0] for c in nums)
 for cp in nums:
  n=cm[cp];adv,_=f['hmtx'][n];g=translate(shapes[n],xoff=round((tabwidth-adv)/2));f['glyf'][n+'.tnum']=glyph(g);f['hmtx'][n+'.tnum']=(tabwidth,round(g.bounds[0]))
 feature='languagesystem DFLT dflt; languagesystem latn dflt; languagesystem cyrl dflt;\nfeature kern {\n'+'\n'.join(f'pos {a} {b} {v};' for (a,b),v in sorted(pairs.items()) if v)+'\n} kern;\n'
 feature+='feature pnum {\n'+'\n'.join(f'sub {cm[c]}.tnum by {cm[c]};' for c in nums)+'\n} pnum;\nfeature tnum {\n'+'\n'.join(f'sub {cm[c]} by {cm[c]}.tnum;' for c in nums)+'\n} tnum;\n'
 addOpenTypeFeaturesFromString(f,feature)
 for rec in f['name'].names:
  names={1:'Nowhere Display 04',2:style,3:f'NowhereDisplay04-{style}-0.400',4:f'Nowhere Display 04 {style}',5:'Version 0.400',6:f'NowhereDisplay04-{style}',16:'Nowhere Display 04',17:style}
  if rec.nameID in names:rec.string=names[rec.nameID].encode(rec.getEncoding())
 f['head'].fontRevision=.4
 p=OUT/f'fonts/NowhereDisplay04-{style}.ttf';f.save(p);f.flavor='woff2';f.save(p.with_suffix('.woff2'))
 (OUT/f'source/{style}.fea').write_text(feature)
 return {'style':style,'changed_characters':list(changes),'safety_pair_adjustments':safety,'glyphs':len(f.getGlyphOrder()),'characters':len(cm),'tabular_advance':tabwidth}
if __name__=='__main__':
 results=[build(s) for s in ['Regular','Bold']];(OUT/'build.json').write_text(json.dumps(results,ensure_ascii=False,indent=2));print(json.dumps(results,ensure_ascii=False,indent=2))
