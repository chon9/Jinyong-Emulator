"""Index original generated companion animation PNGs without altering any pixels."""
import json
from collections import deque
from pathlib import Path
from PIL import Image
from calibrate_visuals import cells,extract,calibrate
ROOT=Path(__file__).resolve().parents[1]
def actor_rects(image,columns,rows):
    # Generated bodies need not sit exactly on an imaginary equal-width grid.
    # Follow whole connected figures instead of slicing a long bamboo staff.
    alpha=image.getchannel('A');width=image.width
    remaining={i for i,a in enumerate(alpha.getdata()) if a>=96};components=[]
    while remaining:
        seed=remaining.pop();queue=deque([seed]);points=[]
        while queue:
            point=queue.popleft();points.append(point);x,y=point%width,point//width
            for nx,ny in [(x-1,y),(x+1,y),(x,y-1),(x,y+1)]:
                other=ny*width+nx
                if 0<=nx<width and 0<=ny<image.height and other in remaining:remaining.remove(other);queue.append(other)
        if len(points)>500:components.append(points)
    components=sorted(components,key=len,reverse=True)[:columns*rows]
    if len(components)!=columns*rows:raise ValueError('Missing separate actor body')
    components.sort(key=lambda p:sum(i//width for i in p)/len(p))
    result=[]
    for row in range(rows):
        group=components[row*columns:(row+1)*columns]
        group.sort(key=lambda p:sum(i%width for i in p)/len(p))
        for points in group:
            xs=[i%width for i in points];ys=[i//width for i in points]
            rect=(max(0,min(xs)-3),max(0,min(ys)-3),min(width,max(xs)+4),min(image.height,max(ys)+4))
            foreign=[i for other in components if other is not points for i in other if rect[0]<=i%width<rect[2] and rect[1]<=i//width<rect[3]]
            result.append((rect,points,foreign))
    return result
def main():
    result={};audit=[]
    for job in json.loads((ROOT/'art/companions/prompts.json').read_text(encoding='utf-8')):
        print('Indexing '+job['key'],flush=True)
        with Image.open(ROOT/job['target']) as source:
            image=source.convert('RGBA');frames=[]
            for index,(rect,points,foreign) in enumerate(actor_rects(image,job['columns'],job['rows'])):
                x,y,right,bottom=rect;w,h=right-x,bottom-y
                frame={'region':[x,y,w,h],'pivot':[w/2,h],'bounds':[0,0,w,h],'body_height':h}
                margin=min(x,y,image.width-right,image.height-bottom)
                local=[(p%image.width-x,p//image.width-y) for p in points]
                frame=calibrate(image,frame,points_override=local)
                if foreign:
                    # Exclude only the neighboring connected figure. Empty alpha
                    # stays empty, and long weapons are preserved in full. Merge
                    # identical rows so most poses still require only a few quads.
                    strips=[];active={};own={};neighbor={}
                    for px,py in local:own.setdefault(py,set()).add(px)
                    for p in foreign:neighbor.setdefault(p//image.width-y,set()).add(p%image.width-x)
                    for sy in range(h):
                        forbidden=set(neighbor.get(sy,set()))
                        for px in list(forbidden):
                            for pad in [px-1,px+1]:
                                if 0<=pad<w and pad not in own.get(sy,set()):forbidden.add(pad)
                        intervals=[];lo=0
                        for px in sorted(forbidden):
                            if px>lo:intervals.append((lo,px-lo))
                            lo=px+1
                        if lo<w:intervals.append((lo,w-lo))
                        next_active={}
                        for lo,sw in intervals:
                            key=(lo,sw)
                            if key in active:strip=active[key];strip[3]+=1
                            else:strip=[lo,sy,sw,1];strips.append(strip)
                            next_active[key]=strip
                        active=next_active
                    frame['draw_regions']=strips
                audit.append({'sheet':job['key'],'cell':index,'margin':margin,'height':frame['body_height']})
                if margin<2:raise ValueError(f"Clipped actor in {job['key']} cell {index}")
                frames.append(frame)
            for row,hid in enumerate(job['characters']):
                poses=frames[row*4:row*4+4]
                result[hid]={'texture':'../companions/'+job['key']+'.png','height':poses[0]['body_height'],'frames':poses}
    assert len(result)==41 and all(len(a['frames'])==4 for a in result.values())
    (ROOT/'data/companion_art.json').write_text(json.dumps(result,separators=(',',':'))+'\n',encoding='utf-8')
    (ROOT/'test-results/companion-art-audit.json').write_text(json.dumps(audit,indent=2),encoding='utf-8')
    print('Indexed 41 companions and 164 distinct action cells, each with independent body/foot bounds.')
if __name__=='__main__':main()
