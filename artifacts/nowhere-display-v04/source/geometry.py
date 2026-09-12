"""Nowhere Display 0.3: targeted optical corrections; unchanged base glyphs retained.
Requires fonttools, shapely, brotli. Run from any directory.
"""
from pathlib import Path
import math, json, copy
from shapely.geometry import Polygon, LineString
from shapely.ops import unary_union
from shapely.affinity import translate, scale
from fontTools.ttLib import TTFont
from fontTools.pens.ttGlyphPen import TTGlyphPen
from fontTools.feaLib.builder import addOpenTypeFeaturesFromString
OUT=Path(__file__).resolve().parents[1]
SB=44

def area(points):
    return sum(a[0]*b[1]-b[0]*a[1] for a,b in zip(points,points[1:]+points[:1]))/2

def shape(f,name):
    g=f['glyf'][name]
    if not g.numberOfContours:return Polygon()
    coords,ends,flags=g.getCoordinates(f['glyf']);start=0;outer=[];holes=[]
    assert all(flag&1 for flag in flags), 'Baseline uses straight-segment contours'
    for end in ends:
        pts=[tuple(p) for p in coords[start:end+1]];start=end+1
        (outer if area(pts)<0 else holes).append(Polygon(pts))
    return unary_union(outer).difference(unary_union(holes))

def ellipse(x,y,w,h):
    # Same slightly squared family of curves as v0.2, with no join seams.
    pts=[]
    for i in range(192):
        a=i*math.tau/192;c=math.cos(a);s=math.sin(a)
        pts.append((x+w/2+w/2*math.copysign(abs(c)**(2/2.22),c),y+h/2+h/2*math.copysign(abs(s)**(2/2.22),s)))
    return Polygon(pts)

def bezier(start,commands):
    pts=[start]
    for cmd in commands:
        if len(cmd)==2:pts.append(cmd)
        else:
            a=pts[-1];b,c,d=cmd
            for i in range(1,65):
                t=i/64
                pts.append(tuple((1-t)**3*a[k]+3*(1-t)**2*t*b[k]+3*(1-t)*t*t*c[k]+t**3*d[k] for k in [0,1]))
    return pts

def fit(g,w,lo=0,hi=720):
    x0,y0,x1,y1=g.bounds
    return translate(scale(translate(g,-x0,-y0),xfact=w/(x1-x0),yfact=(hi-lo)/(y1-y0),origin=(0,0)),yoff=lo)

def corrected(style,f,cm):
    bold=style=='Bold';t=154 if bold else 112;extra=48 if bold else 0;result={}
    # One continuous centerline: the top arc and diagonal have matching tangents.
    pts=bezier((75,600),[((170,738),(522,748),(540,575)),((558,500),(464,461),(412,408)),(70,t/2),(600,t/2)])
    result['2']=(600+extra,fit(LineString(pts).buffer(t/2,cap_style=2,join_style=2),600+extra))
    # Closed four with a single flat apex and a deliberate triangular counter.
    w=655+extra;right=w-110;left=right-t;top=295 if bold else 285;bottom=top-t
    outer=Polygon([(left-20,720),(right,720),(right,top),(w,top),(w,bottom),(right,bottom),(right,0),(left,0),(left,bottom),(0,bottom),(0,top)])
    hole=Polygon([(t*1.38,top),(left,720-t*1.1),(left,top)])
    result['4']=(w,outer.difference(hole))
    # A single outer contour and a separately drawn oval counter remove the ring/arc seam.
    inset=160 if bold else 122;terminal=575 if bold else 606
    pts=bezier((465,710),[((218,790),(0,600),(0,300)),((0,105),(85,-8),(309,-8)),((505,-8),(625,85),(625,235)),((625,400),(509,459),(343,459)),((244,459),(inset+35,423),(inset,370)),((inset+29,520),(260,650),(435,terminal)),(465,710)])
    outer=fit(Polygon(pts),625+extra,-8,728)
    counter=ellipse(148 if bold else 116,112 if bold else 100,377 if bold else 393,218 if bold else 242)
    six=outer.difference(counter);result['6']=(625+extra,six)
    result['9']=(625+extra,translate(scale(six,xfact=-1,yfact=-1,origin=(0,0)),625+extra,720))
    # Match the normal round overshoot instead of the unusually tall old three.
    old=translate(shape(f,cm[ord('3')]),xoff=-SB)
    x0,y0,x1,y1=old.bounds
    result['3']=(605+extra,translate(scale(translate(old,yoff=-y0),xfact=1,yfact=736/(y1-y0),origin=(0,0)),yoff=-8))
    if bold:
        old=translate(shape(f,cm[ord('8')]),xoff=-SB)
        outer=unary_union([Polygon(p.exterior) for p in ([old] if old.geom_type=='Polygon' else old.geoms)])
        # Vertical hairlines are lighter than stems; counter height gets explicit room.
        lower=ellipse(154,104,378,184);upper=ellipse(170,446,345,171)
        result['8']=(688,outer.difference(unary_union([lower,upper])))
    # The lowercase l gets a short curved foot; uppercase I remains unchanged.
    stem=156 if bold else 108;w=stem+100
    pts=bezier((0,720),[(stem,720),(stem,150),((stem,79),(stem+17,72),(w,72)),(w,0),(stem+24,0),((38,0),(0,50),(0,151)),(0,720)])
    result['l']=(w,Polygon(pts))
    # Open the upper ampersand counter while retaining its original outside silhouette.
    old=translate(shape(f,cm[ord('&')]),xoff=-SB);polys=[old] if old.geom_type=='Polygon' else list(old.geoms)
    holes=[Polygon(r) for p in polys for r in p.interiors if Polygon(r).area>1000]
    upper=max(holes,key=lambda h:h.centroid.y)
    opened=scale(upper,xfact=1.14 if bold else 1.07,yfact=1.32 if bold else 1.12,origin='centroid')
    result['&']=(705+extra,old.difference(opened))
    return result

def glyph(g):
    from shapely.geometry.polygon import orient
    pen=TTGlyphPen(None)
    for p in ([g] if g.geom_type=='Polygon' else g.geoms):
        p=orient(p,sign=-1)
        for ring in [p.exterior,*p.interiors]:
            pts=list(ring.coords)[:-1];pen.moveTo(pts[0])
            for pt in pts[1:]:pen.lineTo(pt)
            pen.closePath()
    return pen.glyph()

def build(style):
    f=TTFont(OUT/'source'/f'base-{style}.ttf');cm=f.getBestCmap();changes=corrected(style,f,cm)
    for char,(w,g) in changes.items():
        assert g.is_valid and g.geom_type=='Polygon',(char,g.geom_type)
        g=translate(g,xoff=SB)
        f['glyf'][cm[ord(char)]]=glyph(g)
        f['hmtx'][cm[ord(char)]]=(round(w+2*SB),round(g.bounds[0]))
    # Retain existing alphabet kerning, then add numerical contexts.
    pairs={}
    for lookup in f['GPOS'].table.LookupList.Lookup:
        assert lookup.LookupType==2
        for st in lookup.SubTable:
            assert st.Format==1
            for a,ps in zip(st.Coverage.glyphs,st.PairSet):
                for rec in ps.PairValueRecord:pairs[(a,rec.SecondGlyph)]=rec.Value1.XAdvance
    shapes={c:shape(f,g) for c,g in cm.items() if not chr(c).isspace()}
    def correction(a,b,target,low,high):
        g1,g2=shapes[a],shapes[b];gaps=[]
        for y in range(30,710,15):
            scan=LineString([(-500,y),(2000,y)]);left=g1.intersection(scan);right=g2.intersection(scan)
            if not left.is_empty and not right.is_empty:gaps.append(f['hmtx'][cm[a]][0]-left.bounds[2]+right.bounds[0])
        if not gaps:return 0
        return max(low,min(high,round((target-min(gaps))/2)*2))
    letters=[c for c in cm if chr(c).isalpha()]
    for a in letters:
        for b in letters:
            if ord('l') in [a,b]:pairs[(cm[a],cm[b])]=correction(a,b,82,-85,25)
    nums=[ord(c) for c in '0123456789'];marks=[ord(c) for c in '/:.,-–']
    count=0
    for a in nums+marks:
        for b in nums+marks:
            if a not in nums and b not in nums:continue
            v=correction(a,b,82 if style=='Bold' else 76,-32,20)
            if v:pairs[(cm[a],cm[b])]=v;count+=bool(v)
    order=list(f.getGlyphOrder());tabwidth=max(f['hmtx'][cm[c]][0] for c in nums)
    for cp in nums:
        name=cm[cp];alt=name+'.tnum';advance,lsb=f['hmtx'][name];shift=round((tabwidth-advance)/2)
        g=translate(shapes[cp],xoff=shift);f['glyf'][alt]=glyph(g);f['hmtx'][alt]=(tabwidth,round(g.bounds[0]));order.append(alt)
    f.setGlyphOrder(order)
    feature='languagesystem DFLT dflt; languagesystem latn dflt; languagesystem cyrl dflt;\nfeature kern {\n'+'\n'.join(f'pos {a} {b} {v};' for (a,b),v in sorted(pairs.items()) if v)+'\n} kern;\n'
    feature+='feature pnum {\n'+'\n'.join(f'sub {cm[c]}.tnum by {cm[c]};' for c in nums)+'\n} pnum;\n'
    feature+='feature tnum {\n'+'\n'.join(f'sub {cm[c]} by {cm[c]}.tnum;' for c in nums)+'\n} tnum;\n'
    addOpenTypeFeaturesFromString(f,feature)
    for record in f['name'].names:
        replacements={1:'Nowhere Display 03',2:style,3:f'NowhereDisplay03-{style}-0.300',4:f'Nowhere Display 03 {style}',5:'Version 0.300',6:f'NowhereDisplay03-{style}',16:'Nowhere Display 03',17:style}
        if record.nameID in replacements:record.string=replacements[record.nameID].encode(record.getEncoding())
    f['head'].fontRevision=.3
    path=OUT/'fonts'/f'NowhereDisplay03-{style}.ttf';f.save(path)
    f.flavor='woff2';f.save(path.with_suffix('.woff2'))
    (OUT/'source'/f'{style}.fea').write_text(feature)
    return {'style':style,'changed_characters':list(changes),'numerical_kerning_pairs':count,'tabular_advance':tabwidth,'characters':len(cm),'glyphs':len(order)}

if __name__=='__main__':
    report=[build(s) for s in ['Regular','Bold']]
    (OUT/'build.json').write_text(json.dumps(report,indent=2)+'\n');print(json.dumps(report,indent=2))
