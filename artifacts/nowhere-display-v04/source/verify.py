"""Observable regression checks, evaluated against both old and revised fonts."""
from pathlib import Path
import json,hashlib
from fontTools.ttLib import TTFont
from shapely.geometry import Polygon
from geometry import shape
OUT=Path(__file__).resolve().parents[1]
def inspect(p):
 f=TTFont(p);cm=f.getBestCmap();g=lambda c:shape(f,cm[ord(c)])
 parts=lambda s:[s] if s.geom_type=='Polygon' else list(s.geoms)
 holes=lambda s:[Polygon(h) for a in parts(s) for h in a.interiors]
 def flat(c):
  s=g(c);y=s.bounds[1];longest=0
  for a in parts(s):
   ps=list(a.exterior.coords)
   for p,q in zip(ps,ps[1:]):
    if p[1]==q[1]==y:longest=max(longest,abs(p[0]-q[0]))
  return longest
 ee=max(parts(g('ё')),key=lambda a:a.area)
 checks={'Cyrillic U differs from Y':not g('У').equals(g('Y')),'yo body equals lowercase e':ee.equals(g('е')),'Cyrillic k at x-height':g('к').bounds[3]==510,'question mark has two components':len(parts(g('?')))==2,'ampersand has two counters':len(holes(g('&')))==2,'at sign has one counter':len(holes(g('@')))==1,'left double quote separated':len(parts(g('“')))==2,'right double quote separated':len(parts(g('”')))==2,'numero components separated':len(parts(g('№')))==3,'period is round':g('.').bounds[2]-g('.').bounds[0]==g('.').bounds[3]-g('.').bounds[1],'n apex aligned':g('n').bounds[3]==518,'m apex aligned':g('m').bounds[3]==518,'u baseline aligned':g('u').bounds[1]==-8,'phi has descender':g('ф').bounds[1]<=-160}
 for c in 'UJg':checks[c+' has no long bottom clipping edge']=flat(c)<60
 if f['OS/2'].usWeightClass==700:
  checks['e counter height at least 90 units']=min(h.bounds[3]-h.bounds[1] for h in holes(g('е')))>=90
  for c in 'въыь':checks[c+' counter height at least 105 units']=min(h.bounds[3]-h.bounds[1] for h in holes(g(c)))>=105
 return f,checks
report=[]
for style in ['Regular','Bold']:
 f,checks=inspect(OUT/f'fonts/NowhereDisplay04-{style}.ttf');old,before=inspect(OUT/f'source/base-{style}.ttf')
 assert all(checks.values()),{k:v for k,v in checks.items() if not v}
 cm=f.getBestCmap();assert cm==old.getBestCmap() and len(cm)==163
 changed=set(next(r['changed_characters'] for r in json.loads((OUT/'build.json').read_text()) if r['style']==style))
 for cp,n in cm.items():
  if chr(cp) not in changed:assert f['glyf'][n].getCoordinates(f['glyf'])==old['glyf'][n].getCoordinates(old['glyf']) and f['hmtx'][n]==old['hmtx'][n]
 wf=TTFont(OUT/f'fonts/NowhereDisplay04-{style}.woff2')
 for tag in ['cmap','GPOS','GSUB','hmtx']:assert f.getTableData(tag)==wf.getTableData(tag),tag
 for n in f.getGlyphOrder():assert f['glyf'][n].getCoordinates(f['glyf'])==wf['glyf'][n].getCoordinates(wf['glyf'])
 a=json.loads((OUT/'review/full/audit.json').read_text())['styles'][style]
 assert a['sha256']==hashlib.sha256((OUT/f'fonts/NowhereDisplay04-{style}.ttf').read_bytes()).hexdigest(),'stale audit'
 assert all(g['valid'] and not g['invalid_contours'] for g in a['glyphs'].values())
 assert all(not p['collisions'] for p in a['pairs'].values())
 report.append({'style':style,'passed_checks':list(checks),'base_03_failed_checks':[k for k,v in before.items() if not v],'unchanged_outlines_and_metrics_preserved':True,'TTF_WOFF2_match':True,'current_audit_no_invalid_contours_or_pair_collisions':True,'pair_checks':sum(p['tested'] for p in a['pairs'].values())})
(OUT/'verification.json').write_text(json.dumps(report,ensure_ascii=False,indent=2))
for r in report:print(r['style'],len(r['passed_checks']),'checks pass;',len(r['base_03_failed_checks']),'checks reproduce defects in 0.3;',r['pair_checks'],'pairs without collisions')
