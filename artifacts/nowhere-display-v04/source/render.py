from pathlib import Path
from PIL import Image,ImageDraw,ImageFont
ROOT=Path(__file__).resolve().parents[1];ui=ROOT.parents[1]/'StepsTrader/Fonts/Onest-Regular.ttf'
rows=['У Y УТРО','е ё к ф','U J u g j','n m h r','Л Д л д','? & @','G Q f t','.:… “ ” №','e в ъ ы ь','qj gj jj Qj','NOWHERE','minimum']
for style in ['Regular','Bold']:
 im=Image.new('RGB',(1600,120+len(rows)*165),'#eeeae1');d=ImageDraw.Draw(im)
 d.text((30,20),f'{style}: BEFORE 0.3 / AFTER 0.4',font=ImageFont.truetype(str(ui),24),fill='#657064')
 for i,s in enumerate(rows):
  y=85+i*165
  for x,p in [(30,ROOT/'source'/f'base-{style}.ttf'),(830,ROOT/'fonts'/f'NowhereDisplay04-{style}.ttf')]:
   d.text((x,y),s,font=ImageFont.truetype(str(p),68),fill='#29342e')
   d.text((x,y+95),s,font=ImageFont.truetype(str(p),24),fill='#29342e')
 im.save(ROOT/f'review/{style}.png')
