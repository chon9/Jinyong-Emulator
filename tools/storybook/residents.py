# -*- coding: utf-8 -*-
from . import residents_a, residents_b, residents_c, residents_d
from resident_profiles import SPECIAL as SPECIAL_ART, PRESENTATION

# Candidates are artwork choices, not generated occupations or dialogue.
ART = [
('跑堂', [1]), ('廚|灶', [2]), ('酒', [3]), ('茶', [4]),
('艄|舵|纜|船工|掌渡', [5,6]), ('渡船', [6]), ('魚', [7]),
('鐵匠|修鎖|兵器', [8,17]), ('學徒|掛牌', [9]),
('綢|布|染|衣袍|衣官', [10]), ('商|販|掌櫃', [0,11]),
('樵|柴|修枝|採石', [12]), ('獵|看林', [13]),
('農|牧|送飯|守墓', [14]), ('織|補衣|縫|繡|補鞋|做氈', [15]),
('女先生|教字|女塾', [16]), ('書吏|抄|舊稿|譜房|修繕', [17]),
('說書|看路', [18]), ('信使|驛使|送帖|鏢腳', [19]),
('採藥|採花', [20]), ('郎中|藥房|配藥|女醫|藥師', [21]),
('婆|接生', [22]), ('琴', [23]), ('知客僧|管拳|小僧', [24]),
('老僧|修書', [25]), ('道人|老道', [26]), ('女冠', [27]),
('師太', [28]), ('乞|補碗', [29]), ('女捕|女教習|女管事|女鏢|師姐', [30]),
('老兵|守關|守門', [31]),
]


def apply(content):
    import re
    cast = {}
    for module in [residents_a, residents_b, residents_c, residents_d]:
        for region, table in module.CAST.items():
            for row in table.strip().splitlines():
                fields = row.split('|')
                assert len(fields) == 9, (region, fields[0], len(fields))
                cast[(region, fields[0])] = [fields[1:5], fields[5:9]]
    assert len(cast) == 100
    used = {region: set() for region in content['regions']}
    for pid, index in SPECIAL_ART.items():
        npc = content['people'][pid]
        used[npc['region']].add(index)
        lines = residents_d.SPECIAL[pid]
        npc.update(pages=[{'speaker':pid,'text':lines[0]}, {'speaker':'hero','text':lines[1]}, {'speaker':pid,'text':lines[2]}],
                   text=lines[0], reply=lines[2], stories=[], story='')
    for pid, npc in content['people'].items():
        if not pid.startswith('local_'): continue
        job, first, question, reply = cast[(npc['region'], npc['scene'])][int(pid[-1])]
        preferred = next((candidates for pattern, candidates in ART if re.search(pattern, job)), [17,18])
        sex = PRESENTATION[preferred[0]]
        if re.search('女|姑娘|婦|娘|婆|師姐|師太', job): sex='F'
        neutral = [11,19,26,31,14,29,17,18,5,12,13,0,8,2,3,24,25] if sex=='M' else [15,10,16,20,27,28,30,22,1,6,7,9,23]
        candidates = preferred + neutral + list(range(32))
        index = next(i for i in candidates if i not in used[npc['region']])
        used[npc['region']].add(index)
        npc.update(role=job, art=f'actor_npc_{index:02}', text=first, reply=reply,
                   pages=[{'speaker':pid,'text':first}, {'speaker':'hero','text':question}, {'speaker':pid,'text':reply}],
                   stories=[], story='')
