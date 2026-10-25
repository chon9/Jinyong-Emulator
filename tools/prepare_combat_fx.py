# -*- coding: utf-8 -*-
"""Copy selected owner-provided FX/audio unchanged, and register distinct styles."""
import argparse,json,hashlib,shutil
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
TEXTURES={'dragon':'阿杰-亢龍有悔-擊中01.png','finger':'阿杰-六脈神劍01.png','ice_blade':'冰剑.png','sword_rain':'神剑.png','fire':'015-Fire01.png','ice':'016-Ice01.png','thunder':'017-Thunder01.png','earth':'019-Earth01.png','wind':'020-Wind01.png','light':'021-Light01.png','dark':'022-Darkness01.png','aura':'025-Support02.png','shield':'026-Support03.png','seal':'027-Support04.png','state':'028-State01.png','staff':'011-Weapon06.png','sword':'008-Weapon03.png','blade':'010-Weapon05.png','lotus':'014-Heal03.png'}
SOUNDS={'sword_ready':'063-Swing02.ogg','sword_hit':'091-Attack03.ogg','blade_ready':'065-Swing04.ogg','blade_hit':'094-Attack06.ogg','staff_ready':'064-Swing03.ogg','staff_hit':'092-Attack04.ogg','palm_ready':'087-Action02.ogg','palm_hit':'098-Attack10.ogg','dragon_ready':'088-Action03.ogg','dragon_hit':'061-Thunderclap01.ogg','finger_ready':'100-Attack12.ogg','finger_hit':'102-Attack14.ogg','venom_ready':'019-Teleport02.ogg','venom_hit':'103-Attack15.ogg','ice_ready':'018-Teleport01.ogg','ice_hit':'101-Attack13.ogg','sound_ready':'108-Heal04.ogg','sound_hit':'107-Heal03.ogg','heal_ready':'106-Heal02.ogg','heal_hit':'110-Heal06.ogg','charge':'086-Action01.ogg','guard':'090-Attack02.ogg','seal':'109-Heal05.ogg'}
STYLES={
 'sword':('sword','sword','71d9f2','arc',1.0),
 'blade':('blade','blade','ffb45f','sweep',1.1),
 'staff':('staff','staff','8ad783','staff',1.05),
 'palm':('earth','palm','efcb7b','palm',1.15),
 'dragon':('dragon','dragon','ffc563','dragon',1.5),
 'finger':('finger','finger','b3efff','ray',1.25),
 'iron':('earth','blade','d7c7a1','crush',1.4),
 'twin':('sword','sword','f6bddd','twin',1.15),
 'nine':('sword_rain','sword','a2efff','rain',1.35),
 'bamboo':('staff','staff','b6f28a','bamboo',1.2),
 'reflect':('shield','finger','adc4ff','reflect',1.15),
 'music':('wind','sound','d4c2ff','music',1.15),
 'herbal':('lotus','heal','9cebb8','petal',1.1),
 'ice':('ice','ice','96ddff','ice',1.1),
 'venom':('dark','venom','bd8fef','poison',1.1),
 'fire':('fire','palm','ff8b64','fire',1.15),
 'gold_heal':('light','heal','ffe5a2','ray',1.1),
 'lotus':('lotus','heal','c8e5ff','lotus',1.2),
 'snake':('sword','sword','e8d67d','snake',1.2),
 'blood':('blade','blade','f2a0a0','sweep',1.15),
 'charge':('aura','charge','ffb96e','charge',1.0),
 'guard':('shield','guard','a2d5dc','shield',1.0),
 'sealed':('seal','seal','cdb4eb','seal',1.0),
 'dot':('state','venom','bc9dc7','poison',.8)}
OVERRIDES={'降龍十八掌':'dragon','降龍廿八掌':'dragon','天下無狗':'bamboo','打狗棒法':'bamboo','六脈神劍':'finger','乾坤大挪移':'reflect','斗轉星移':'reflect','玄鐵劍法':'iron','玉女素心劍':'twin','獨孤九劍':'nine','清音劍訣':'music','玉簫劍法':'music','七心海棠訣':'herbal','冰蠶寒掌':'ice','星宿毒術':'venom','白駝雪山掌':'venom','神龍掌法':'fire','一陽指':'gold_heal','慈航渡厄':'lotus','夢回拂穴':'lotus','金蛇劍法':'snake','胡家刀法':'blood','血刀刀法':'blood','清心回元':'herbal','回春拂穴':'herbal','金剛截脈':'staff'}
def main():
 parser=argparse.ArgumentParser();parser.add_argument('--source',type=Path,required=True);args=parser.parse_args()
 from PIL import Image
 assets=[];manifest=[];textures={}
 for name,source in TEXTURES.items():
  source=args.source/'Graphics/Animations'/source;target=ROOT/'assets/effects'/('fx_'+name+'.png')
  shutil.copyfile(source,target)
  with Image.open(target) as image:textures[name]={'path':'effects/'+target.name,'columns':5,'rows':(image.height+191)//192,'frames':5*((image.height+191)//192),'additive':image.mode=='RGB'}
  assets.append('effects/'+target.name);manifest.append({'target':target.relative_to(ROOT).as_posix(),'source':'Graphics/Animations/'+source.name,'sha256':hashlib.sha256(target.read_bytes()).hexdigest()})
 for name,source in SOUNDS.items():
  source=args.source/'Audio/SE'/source;target=ROOT/'assets/sfx'/('fx_'+name+'.ogg');shutil.copyfile(source,target)
  assets.append('sfx/'+target.name);manifest.append({'target':target.relative_to(ROOT).as_posix(),'source':'Audio/SE/'+source.name,'sha256':hashlib.sha256(target.read_bytes()).hexdigest()})
 styles={}
 for key,(texture,cue,color,shape,scale) in STYLES.items():
  start='fx_'+(cue if cue in ['charge','guard','seal'] else cue+'_ready')
  impact='' if cue in ['charge','guard','seal'] else 'fx_'+cue+'_hit'
  styles[key]={'texture':texture,'start':start,'impact':impact,'color':color,'shape':shape,'scale':scale}
 content=json.loads((ROOT/'data/open_world.json').read_text(encoding='utf-8'))
 signatures={name:OVERRIDES.get(name,{'刀':'blade','劍':'sword','棍':'staff','拳掌':'palm'}[art['weapon']]) for name,art in content['arts'].items()}
 signatures.update(OVERRIDES)
 data={'textures':textures,'styles':styles,'skills':signatures,'assets':assets}
 (ROOT/'data/combat_fx.json').write_text(json.dumps(data,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
 (ROOT/'art/combat-fx.json').write_text(json.dumps({'source':'Owner-provided Jinyong Heroes 5 resources; copied unchanged. No scripts, dialogue or saves imported.','files':manifest},ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
 print(f'{len(TEXTURES)} complete animation sheets, {len(SOUNDS)} distinct cues, {len(styles)} presentation styles')
if __name__=='__main__':main()
