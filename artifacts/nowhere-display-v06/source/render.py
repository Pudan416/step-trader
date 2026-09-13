from pathlib import Path
from PIL import Image,ImageDraw,ImageFont
R=Path(__file__).resolve().parents[1]
for st in ['Regular','Bold']:
 im=Image.new('RGB',(1660,1170),'#f8f5eb');d=ImageDraw.Draw(im)
 rows=[('12/09/26',82),('0123456789',90),('0 6 8 9',110),('01/11/26  23:59',58),('1 2 3 4 5 7',86)]
 for i,(txt,sz) in enumerate(rows):
  y=40+i*220
  for x,p,label in [(25,R/f'source/base-{st}.ttf','0.5'),(850,R/f'fonts/NowhereDisplay06-{st}.ttf','0.6')]:
   d.text((x,y),st+' / '+label,font=ImageFont.truetype('/System/Library/Fonts/Helvetica.ttc',19),fill='#777777')
   d.text((x,y+36),txt,font=ImageFont.truetype(str(p),sz),fill='#151515')
   d.text((x,y+160),txt,font=ImageFont.truetype(str(p),24),fill='#151515')
 im.save(R/f'review/{st}.png')
