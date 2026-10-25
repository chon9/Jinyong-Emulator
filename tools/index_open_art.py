"""Read sprite alpha and emit source rectangles; never modify generated pixels."""
import hashlib,json
from pathlib import Path
from PIL import Image
from index_character_art import inspect
ROOT=Path(__file__).resolve().parents[1]
def main():
    result={}; hashes={}
    jobs=json.loads((ROOT/'art/open-world-assets.json').read_text())
    for job in jobs:
        if not job['columns']:continue
        with Image.open(ROOT/job['target']) as source:
            image=source.convert('RGBA')
            for index in range(job['columns']*job['rows']):
                if job['key'].startswith('foes-'): key='enemy_%03d'%((int(job['key'][-2:])-1)*10+index+1)
                elif job['key'].startswith('heroes-'):key='jy%02d'%((int(job['key'][-1])-1)*8+index+1)
                elif job['key']=='mu-nianci':key='jy24'
                else:key='resident_'+str(index)
                frame=inspect(image,index%job['columns'],index//job['columns'],job['columns'],job['rows'])
                result[key]={'texture':'../open_world/'+job['key']+'.png','height':frame['body_height'],'frames':[frame]}
                x,y,w,h=frame['region']
                # A read-only hash verifies that all enemy source cells differ.
                hashes[key]=hashlib.sha256(image.crop((x,y,x+w,y+h)).tobytes()).hexdigest()
    assert len({v for k,v in hashes.items() if k.startswith('enemy_')})==100
    (ROOT/'data/open_art.json').write_text(json.dumps(result,separators=(',',':'))+'\n')
    (ROOT/'test-results/open-art-audit.json').write_text(json.dumps({'cells':len(result),'enemy_unique_hashes':100,'hashes':hashes},indent=2)+'\n')
    print('Indexed %d distinct sprite cells; all 100 enemy image cells have different hashes.'%len(result))
if __name__=='__main__':main()
