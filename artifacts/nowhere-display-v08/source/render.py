from pathlib import Path
from PIL import Image,ImageDraw,ImageFont
R=Path(__file__).resolve().parents[1]
for st in ['Regular','Bold']:
 im=Image.new('RGB',(1400,900),'#f8f5eb');d=ImageDraw.Draw(im)
 for x,p,label in [(25,R/f'source/base-{st}.ttf','0.7'),(720,R/f'fonts/NowhereDisplay08-{st}.ttf','0.8')]:
  d.text((x,20),st+' / '+label,font=ImageFont.truetype('/System/Library/Fonts/Helvetica.ttc',20),fill='#777777')
  for y,txt,sz in [(60,'б',350),(400,'боб бобы небо',46),(510,'свобода любовь',44),(620,'б о 6',80),(750,'боб бобы небо свобода любовь',24)]:d.text((x,y),txt,font=ImageFont.truetype(str(p),sz),fill='#151515')
 im.save(R/f'review/{st}.png')
