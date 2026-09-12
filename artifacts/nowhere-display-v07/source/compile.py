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
 feature='languagesystem DFLT dflt; languagesystem latn dflt; languagesystem cyrl dflt;\nfeature kern {\n'+'\n'.join(f'pos {a} {b} {v};' for (a,b),v in sorted(pairs.items()) if v)+'\n} kern;\n'
 feature+='feature pnum {\n'+'\n'.join(f'sub {cm[c]}.tnum by {cm[c]};' for c in nums)+'\n} pnum;\nfeature tnum {\n'+'\n'.join(f'sub {cm[c]} by {cm[c]}.tnum;' for c in nums)+'\n} tnum;\n'
 addOpenTypeFeaturesFromString(f,feature)
 for rec in f['name'].names:
  names={1:'Nowhere Display 07',2:style,3:f'NowhereDisplay07-{style}-0.700',4:f'Nowhere Display 07 {style}',5:'Version 0.700',6:f'NowhereDisplay07-{style}',16:'Nowhere Display 07',17:style}
  if rec.nameID in names:rec.string=names[rec.nameID].encode(rec.getEncoding())
 f['head'].fontRevision=.7
 for c, contours in OUTLINES.items():
  f['glyf'][cm[ord(c)]]=curve_glyph(contours)
  if c.isdigit():
   n=cm[ord(c)];shift=round((tabwidth-f['hmtx'][n][0])/2)
   f['glyf'][n+'.tnum']=curve_glyph(contours,shift)
 p=OUT/f'fonts/NowhereDisplay07-{style}.ttf';f.save(p);f.flavor='woff2';f.save(p.with_suffix('.woff2'))
 (OUT/f'source/{style}.fea').write_text(feature)
 return {'style':style,'changed_characters':list(changes),'safety_pair_adjustments':safety,'glyphs':len(f.getGlyphOrder()),'characters':len(cm),'tabular_advance':tabwidth}
if __name__=='__main__':
 results=[build(s) for s in ['Regular','Bold']];(OUT/'build.json').write_text(json.dumps(results,ensure_ascii=False,indent=2));print(json.dumps(results,ensure_ascii=False,indent=2))
