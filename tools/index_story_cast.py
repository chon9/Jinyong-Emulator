"""Index the original generated busts. Only metadata is written, never pixels."""
import json
from pathlib import Path
from PIL import Image
from index_companions import actor_rects
from calibrate_visuals import calibrate
from storybook.supporting import CAST
ROOT=Path(__file__).resolve().parents[1]

def main():
    result={}
    for group,name in enumerate(['story-cast-a','story-cast-b']):
        with Image.open(ROOT/f'assets/supporting/{name}.png') as source:
            image=source.convert('RGBA')
            for index,(rect,points,foreign) in enumerate(actor_rects(image,4,2)):
                x,y,right,bottom=rect;w,h=right-x,bottom-y
                frame=dict(region=[x,y,w,h],pivot=[w/2,h],bounds=[0,0,w,h],body_height=h)
                local=[(p%image.width-x,p//image.width-y) for p in points]
                frame=calibrate(image,frame,portrait=True,points_override=local)
                key=CAST[group*8+index][0]
                result['story_'+key]=dict(texture=f'../supporting/{name}.png',height=frame['body_height'],frames=[frame],portrait_only=True)
                print(key,rect,'foreign',len(foreign))
    assert len(result)==16
    (ROOT/'data/support_art.json').write_text(json.dumps(result,separators=(',',':'))+'\n',encoding='utf-8')

if __name__=='__main__':main()
