# -*- coding: utf-8 -*-
"""Read-only pixel analysis: emit separate draw, anatomy, ground and portrait bounds."""
import json
import statistics
from pathlib import Path
from PIL import Image
from index_character_art import inspect
ROOT=Path(__file__).resolve().parents[1]

def quantile(values,fraction):
    values=sorted(values)
    return values[min(len(values)-1,int((len(values)-1)*fraction))]

def cells(image,columns,rows,adaptive=True):
    alpha=image.getchannel('A')
    def separator(nominal,radius,vertical,low,high):
        scores=[]
        for at in range(max(1,nominal-radius),min((image.width if vertical else image.height)-1,nominal+radius)+1):
            score=sum(alpha.getpixel((at,p) if vertical else (p,at))>=96 for p in range(low,high))
            scores.append((score,abs(at-nominal),at))
        minimum=min(s[0] for s in scores)
        runs=[]
        for score,_,at in scores:
            if score!=minimum:continue
            if runs and runs[-1][-1]==at-1:runs[-1].append(at)
            else:runs.append([at])
        run=min(runs,key=lambda r:(abs((r[0]+r[-1])/2-nominal),-len(r)))
        return (run[0]+run[-1])//2
    y_edges=[0]
    for row in range(1,rows):
        nominal=row*image.height//rows
        y_edges.append(separator(nominal,image.height//rows//5,False,0,image.width) if adaptive else nominal)
    y_edges.append(image.height)
    result=[]
    for row in range(rows):
        top,bottom=y_edges[row:row+2]
        edges=[0]
        for column in range(1,columns):
            nominal=column*image.width//columns
            edges.append(separator(nominal,image.width//columns//3,True,top,bottom) if adaptive else nominal)
        edges.append(image.width)
        for column in range(columns):result.append((edges[column],top,edges[column+1],bottom))
    return result

def extract(image,rect):
    cx,cy,right,bottom=rect
    cell=image.crop(rect)
    frame=inspect(cell,0,0,1,1)
    x,y,w,h=frame['region'];x+=cx;y+=cy
    margin=min(x-cx,y-cy,right-x-w,bottom-y-h)
    x0=max(cx,x-3);y0=max(cy,y-3);x1=min(right,x+w+3);y1=min(bottom,y+h+3)
    frame['region']=[x0,y0,x1-x0,y1-y0]
    return frame,margin

def calibrate(image,frame,portrait=False,points_override=None):
    x,y,w,h=map(int,frame['region'])
    alpha=image.getchannel('A')
    points=points_override if points_override is not None else [(px,py) for py in range(h) for px in range(w) if alpha.getpixel((x+px,y+py))>=96]
    if not points:raise ValueError('Empty source rectangle')
    ys=[p[1] for p in points]
    rows=[0]*h
    for px,py in points:rows[py]+=1
    threshold=max(8,int(max(rows)*.15))
    head=next((py for py in range(h-2) if min(rows[py:py+3])>=threshold),min(ys))
    ground=quantile(ys,.998)
    height=max(20,ground-head)
    head_xs=[px for px,py in points if head<=py<head+height*.19]
    center=statistics.median(head_xs) if head_xs else w/2
    feet=[px for px,py in points if ground-height*.055<=py<=ground]
    foot_x=(quantile(feet,.12)+quantile(feet,.88))/2 if feet else center
    frame['pivot']=[round(foot_x,2),ground]
    frame['body_height']=height
    frame['scale_height']=height
    frame['bounds']=[0,0,w,h]
    def crop(cw,ch,top):
        cw=min(w,cw);ch=min(h-top,ch)
        left=max(0,min(w-cw,center-cw*.5))
        return [round(x+left,2),round(y+top,2),round(cw,2),round(ch,2)]
    frame['head']=crop(height*.35,height*.35,max(0,head-height*.025))
    frame['portrait']=crop(height*.7,height*.78,max(0,head-height*.025))
    if portrait:
        # Portrait-only art has no ground animation and uses the entire bust.
        frame['portrait']=[x,y,w,h]
        frame['head']=crop(min(w,h*.73),h*.7,0)
    return frame

def main():
    jobs=json.loads((ROOT/'art/visuals/prompts.json').read_text(encoding='utf-8'))
    result={};audit=[];npc=0
    for job in jobs:
        path=ROOT/'assets/visuals'/(job['key']+'.png')
        with Image.open(path) as source:
            image=source.convert('RGBA')
            frames=[]
            for index,rect in enumerate(cells(image,job['columns'],job['rows'],job['kind']=='battle')):
                frame,margin=extract(image,rect)
                audit.append({'asset':job['key'],'cell':index,'opaque_margin':margin})
                if job['kind']=='battle' and margin<3:raise ValueError(f"Regenerate clipped cell: {job['key']} {index} margin={margin}")
                frames.append(calibrate(image,frame,job['kind']=='residents'))
            texture='../visuals/'+job['key']+'.png'
            if job['kind']=='battle':
                result[job['character']]={'texture':texture,'height':frames[0]['body_height'],'frames':frames}
            else:
                for frame in frames:
                    result[f'npc_{npc:02}']={'texture':texture,'height':frame['body_height'],'frames':[frame],'portrait_only':True};npc+=1
    # Existing open-world fighters also receive anatomical scale and bounded portrait crops.
    for job in json.loads((ROOT/'art/open-world-assets.json').read_text(encoding='utf-8')):
        if not job['columns']:continue
        with Image.open(ROOT/job['target']) as source:
            image=source.convert('RGBA')
            for index,rect in enumerate(cells(image,job['columns'],job['rows'])):
                if job['key'].startswith('foes-'):key='enemy_%03d'%((int(job['key'][-2:])-1)*10+index+1)
                elif job['key'].startswith('heroes-'):key='jy%02d'%((int(job['key'][-1])-1)*8+index+1)
                elif job['key']=='mu-nianci':key='jy24'
                else:key='resident_'+str(index)
                frame,_=extract(image,rect)
                frame=calibrate(image,frame)
                result[key]={'texture':'../open_world/'+job['key']+'.png','height':frame['body_height'],'frames':[frame]}
    (ROOT/'data/visual_art.json').write_text(json.dumps(result,separators=(',',':'))+'\n',encoding='utf-8')
    (ROOT/'test-results/visual-art-audit.json').write_text(json.dumps({'generated_cells':audit,'characters':len(result),'civilian_designs':npc},indent=2),encoding='utf-8')
    print(f'Calibrated {len(result)} actors: {npc} civilian portraits and 60 newly padded combat frames.')
if __name__=='__main__':main()
