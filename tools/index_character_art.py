"""Index generated sprite cells and ground pivots without modifying any pixels."""
import argparse
import json
from pathlib import Path
import statistics
from collections import deque
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
LAYOUTS = {
    'combat-a.png': ['swordsman', 'companion', 'healer', 'staff'],
    'combat-b.png': ['blade', 'elder', 'doctor', 'taoist'],
    'combat-c.png': ['monk', 'wanderer', 'boss', 'rogue'],
    'hero-variants.png': ['hero_dao', 'hero_staff', 'hero_palm', None],
    'rogue.png': ['rogue'],
}


def inspect(image, column, row, columns, rows):
    x0, x1 = column*image.width//columns, (column+1)*image.width//columns
    y0, y1 = row*image.height//rows, (row+1)*image.height//rows
    cell = image.crop((x0,y0,x1,y1))
    alpha = cell.getchannel('A')
    occupied = [i for i, a in enumerate(alpha.getdata()) if a >= 96]
    if not occupied:
        raise ValueError(f'Empty sprite cell {column}, {row}')
    # Ignore disconnected neighbouring boots/cloth at generated row boundaries.
    remaining=set(occupied); largest=[]
    while remaining:
        seed=remaining.pop(); queue=deque([seed]); component=[]
        while queue:
            point=queue.popleft(); component.append(point)
            x,y=point%cell.width,point//cell.width
            for nx,ny in [(x-1,y),(x+1,y),(x,y-1),(x,y+1)]:
                other=ny*cell.width+nx
                if 0<=nx<cell.width and 0<=ny<cell.height and other in remaining:
                    remaining.remove(other); queue.append(other)
        if len(component)>len(largest): largest=component
    xs = [i % cell.width for i in largest]
    ys = [i // cell.width for i in largest]
    left, top, right, bottom = min(xs), min(ys), max(xs)+1, max(ys)+1
    return {'region': [x0+left,y0+top,right-left,bottom-top], 'pivot': [cell.width/2-left,bottom-top],
            'bounds': [0,0,right-left,bottom-top], 'body_height': bottom-top}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--folder', type=Path, default=ROOT/'assets/characters')
    parser.add_argument('--output', type=Path, default=ROOT/'data/character_art.json')
    args = parser.parse_args()
    data = {'version':1, 'characters':{}, 'walk':[]}
    for filename, names in LAYOUTS.items():
        with Image.open(args.folder/filename) as source:
            image = source.convert('RGBA')
            for row, name in enumerate(names):
                if name is None:
                    continue
                frames = [inspect(image, col, row, 4, len(names)) for col in range(4)]
                data['characters'][name] = {'texture':filename, 'height':frames[0]['body_height'], 'frames':frames}
    with Image.open(args.folder/'hero-walk.png') as source:
        image = source.convert('RGBA')
        for row in range(3):
            data['walk'].append([inspect(image,col,row,4,3) for col in range(4)])
    data['walk_height'] = statistics.median(row[0]['body_height'] for row in data['walk'])
    args.output.parent.mkdir(parents=True,exist_ok=True)
    args.output.write_text(json.dumps(data,ensure_ascii=False,separators=(',',':')),encoding='utf-8')
    ui_regions = []
    with Image.open(ROOT/'assets/ui/skin.png') as source:
        image = source.convert('RGBA')
        for row in range(3):
            for col in range(4):
                # Generated decorative icons rise above the equal-grid boundary.
                # Panel regions follow their connected opaque body, not neighbours.
                left,right=col*image.width//4,(col+1)*image.width//4
                top,bottom=[0,360,680, image.height][row:row+2]
                alpha=image.getchannel('A')
                if row<2:
                    seed=((left+right)//2,(top+bottom)//2)
                    queue=deque([seed]); seen={seed}; points=[]
                    while queue:
                        x,y=queue.popleft()
                        if alpha.getpixel((x,y))<128: continue
                        points.append((x,y))
                        for nx,ny in [(x-1,y),(x+1,y),(x,y-1),(x,y+1)]:
                            if left<=nx<right and top<=ny<bottom and (nx,ny) not in seen:
                                seen.add((nx,ny)); queue.append((nx,ny))
                else:
                    points=[(x,y) for y in range(top,bottom) for x in range(left,right) if alpha.getpixel((x,y))>=128]
                xs,ys=zip(*points)
                ui_regions.append([min(xs),min(ys),max(xs)-min(xs)+1,max(ys)-min(ys)+1])
    (ROOT/'data/ui_skin.json').write_text(json.dumps(ui_regions,separators=(',',':')),encoding='utf-8')
    print(json.dumps({'characters':len(data['characters']),'battle_frames':sum(len(x['frames']) for x in data['characters'].values()),'walking_frames':sum(len(x) for x in data['walk'])}))


if __name__ == '__main__':
    main()
