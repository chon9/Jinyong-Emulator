"""Small authoring notation: the machinery connects scenes, never writes prose.

g = quest giver, p = player, w = the named local contact at this step,
x = named opponent, n = narration. Explicit jyXX speaker IDs are also supported.
Each speech is authored as an individual line, not interpolated from a premise.
"""


def beat(kind, at, goal, dialogue, **values):
    return dict(kind=kind, at=at, text=goal, dialogue=dialogue, **values)


def character(hid, title, voice, want, opening, beats, ending, after, join, **values):
    return dict(id=hid, title=title, voice=voice, want=want, opening=opening,
                beats=beats, ending=ending, after=after, join=join, **values)


def commission(qid, at, hook, opening, beats, ending, **values):
    return dict(id=qid, at=at, want=hook, opening=opening, beats=beats,
                ending=ending, **values)
