"""Geometry conversion and inspection for Nowhere Display 0.5."""
from shapely.geometry import Polygon
from shapely.ops import unary_union
from fontTools.pens.ttGlyphPen import TTGlyphPen

def area(points):
    return sum(a[0]*b[1]-b[0]*a[1] for a,b in zip(points,points[1:]+points[:1]))/2

def shape(f,name):
    from fontTools.pens.basePen import BasePen
    class Flatten(BasePen):
        def __init__(self):super().__init__(f.getGlyphSet());self.paths=[];self.pts=[]
        def _moveTo(self,p):self.pts=[p]
        def _lineTo(self,p):self.pts.append(p)
        def _qCurveToOne(self,b,c):
            a=self.pts[-1]
            for i in range(1,33):
                t=i/32;self.pts.append(tuple((1-t)**2*a[k]+2*(1-t)*t*b[k]+t*t*c[k] for k in [0,1]))
        def _curveToOne(self,b,c,d):
            a=self.pts[-1]
            for i in range(1,65):
                t=i/64;self.pts.append(tuple((1-t)**3*a[k]+3*(1-t)**2*t*b[k]+3*(1-t)*t*t*c[k]+t**3*d[k] for k in [0,1]))
        def _closePath(self):self.paths.append(self.pts);self.pts=[]
        def _endPath(self):self._closePath()
    pen=Flatten();f.getGlyphSet()[name].draw(pen);outer=[];holes=[]
    for pts in pen.paths:
        p=Polygon(pts)
        assert p.is_valid, ('invalid contour',name)
        (outer if area(pts)<0 else holes).append(p)
    return unary_union(outer).difference(unary_union(holes))

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
