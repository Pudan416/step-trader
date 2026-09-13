from pathlib import Path
import json,sys,itertools,hashlib
from fontTools.ttLib import TTFont
from shapely.affinity import translate
from geometry import shape
import uharfbuzz as hb
R=Path(__file__).resolve().parents[1];report={}
for style in ['Regular','Bold']:
 p=R/f'fonts/NowhereDisplay06-{style}.ttf';f=TTFont(p);base=TTFont(R/f'source/base-{style}.ttf');wf=TTFont(p.with_suffix('.woff2'));cm=f.getBestCmap();order=f.getGlyphOrder()
 changed=set(next(x['changed_characters'] for x in json.loads((R/'build.json').read_text()) if x['style']==style));changedNames={cm[ord(c)] for c in changed}
 shapes={n:shape(f,n) for n in order}
 assert cm==base.getBestCmap()==wf.getBestCmap()
 assert len(order)==173 and len(cm)==163
 for n in order:
  assert shapes[n].is_valid,n
  assert f['glyf'][n].getCoordinates(f['glyf'])==wf['glyf'][n].getCoordinates(wf['glyf']),n
  if n not in changedNames and not n.endswith('.tnum'):
   assert f['glyf'][n].getCoordinates(f['glyf'])==base['glyf'][n].getCoordinates(base['glyf']),('unexpected change',n)
   assert f['hmtx'][n]==base['hmtx'][n]
 expected={'0':2,'1':1,'2':1,'3':1,'4':2,'5':1,'6':2,'7':1,'8':3,'9':2,'/':1}
 for c,num in expected.items():
  gl=f['glyf'][cm[ord(c)]];assert gl.numberOfContours==num,(c,gl.numberOfContours)
  if c not in '147/':assert any(not x&1 for x in gl.getCoordinates(f['glyf'])[2]),('missing curves',c)
 for n in changedNames:
  gl=f['glyf'][n];gl.recalcBounds(f['glyf']);assert gl.yMin>=-240 and gl.yMax<=940
  aw,lsb=f['hmtx'][n];assert aw-gl.xMax>=35,(n,'right bearing')
 for c in '0123456789':
  n=cm[ord(c)];g=f['glyf'][n];g.recalcBounds(f['glyf']);assert -10<=g.yMin<=0 and 712<=g.yMax<=730,(c,g.yMin,g.yMax)
  a=f['hmtx'][n+'.tnum'][0];assert a==max(f['hmtx'][cm[ord(x)]][0] for x in '0123456789')
  shift=round((a-f['hmtx'][n][0])/2)
  assert shapes[n+'.tnum'].symmetric_difference(translate(shapes[n],xoff=shift)).area<.01,(c,'tabular outline mismatch')
 assert (f['glyf'][cm[ord('/')]].yMin,f['glyf'][cm[ord('/')]].yMax)==(0,720)
 font=hb.Font(hb.Face(p.read_bytes()));chars=[chr(c) for c in cm if not chr(c).isspace()];count=0;mingap=999
 for tab in [False,True]:
  for a,b in itertools.product(chars,repeat=2):
   if tab and a not in '0123456789' and b not in '0123456789':continue
   buf=hb.Buffer();buf.add_str(a+b);buf.guess_segment_properties();hb.shape(font,buf,{'kern':True,'tnum':tab});inf=buf.glyph_infos;pos=buf.glyph_positions
   assert len(inf)==2
   s1,s2=[shapes[order[x.codepoint]] for x in inf];shift=pos[0].x_advance+pos[1].x_offset-pos[0].x_offset;count+=1
   if s1.bounds[2]+30<shift+s2.bounds[0]:continue
   gap=s1.distance(translate(s2,xoff=shift,yoff=pos[0].y_advance+pos[1].y_offset-pos[0].y_offset));mingap=min(mingap,gap);assert gap>0,(style,a+b,gap)
 report[style]={'sha256':hashlib.sha256(p.read_bytes()).hexdigest(),'encoded_characters':len(cm),'glyphs':len(order),'changed':sorted(changed),'shaped_pairs_checked':count,'minimum_checked_near_gap':round(mingap,2),'valid_contours':True,'unchanged_glyphs_preserved':True,'woff2_outlines_identical':True,'curved_outline_checks':True}
 print(style,report[style],flush=True)
(R/'verification.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
