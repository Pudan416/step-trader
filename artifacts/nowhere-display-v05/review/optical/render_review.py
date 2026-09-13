from pathlib import Path
from PIL import Image,ImageDraw,ImageFont
from fontTools.ttLib import TTFont
R=Path(__file__).resolve().parents[2]; O=Path(__file__).resolve().parent
ui='/System/Library/Fonts/Helvetica.ttc'
for style in ['Regular','Bold']:
 p=R/'fonts'/f'NowhereDisplay05-{style}.ttf'
 f=lambda n:ImageFont.truetype(str(p),n)
 im=Image.new('RGB',(1680,1060),'#f3f0e9');d=ImageDraw.Draw(im)
 for i,c in enumerate('ёкgm&@eG'):
  x=20+(i%4)*415;y=45+(i//4)*500
  d.text((x,y),f'{c} / {style} / v0.5',font=ImageFont.truetype(ui,19),fill='#626860')
  for yy in [y+300,y+300-510*.30,y+300-720*.30]:d.line((x,yy,x+390,yy),fill='#c9c7bf')
  d.text((x+25,y+300),c,font=f(300),fill='#23322a',anchor='ls')
  d.text((x+10,y+340),c*3,font=f(48),fill='#23322a')
  d.text((x+10,y+410),c*5,font=f(24),fill='#23322a')
 im.save(O/f'focus-{style}.png')
 chars=[chr(c) for c in TTFont(p).getBestCmap() if not chr(c).isspace()]
 im=Image.new('RGB',(1560,((len(chars)+11)//12)*135+45),'#f3f0e9');d=ImageDraw.Draw(im)
 d.text((15,10),f'Nowhere Display 0.5 {style} — full encoded set',font=ImageFont.truetype(ui,20),fill='#23322a')
 for i,c in enumerate(chars):
  x=i%12*130;y=i//12*135+45
  d.text((x+8,y+4),f'U+{ord(c):04X}',font=ImageFont.truetype(ui,12),fill='#666666')
  d.text((x+10,y+85),c,font=f(74),fill='#23322a',anchor='ls')
 im.save(O/f'all-{style}.png')
 rows=['e ё е  eye ещё', 'gag gauge going','minimum morning','как крик окно','GOG GAGE GROUND','& @  hello@nowhere','n h m u  rn m', 'a b d p q o c e s','А Б В Д Л У Ф Я','а б в д л у ф я','0123456789  09:41']
 im=Image.new('RGB',(1500,len(rows)*120+70),'#f3f0e9');d=ImageDraw.Draw(im)
 for i,s in enumerate(rows):
  y=35+i*120;d.text((20,y),s,font=f(52),fill='#23322a');d.text((20,y+72),s,font=f(24),fill='#23322a')
 im.save(O/f'words-{style}.png')
