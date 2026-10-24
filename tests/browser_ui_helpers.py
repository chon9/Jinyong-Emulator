"""Drive visible Godot buttons by their rendered geometry; no game actions in JS."""
def press(page, text, prefix=True, last=False):
    buttons=page.evaluate('window.youxiaUI.buttons')
    found=[b for b in buttons if not b['disabled'] and (b['text'].startswith(text) if prefix else b['text']==text)]
    assert found, (text, [b['text'] for b in buttons])
    b=found[-1] if last else found[0]
    box=page.locator('#canvas').bounding_box()
    # Godot uses a fixed 1440x900 viewport with aspect-preserving stretch.
    scale=min(box['width']/1440,box['height']/900)
    offset_x=(box['width']-1440*scale)/2
    offset_y=(box['height']-900*scale)/2
    page.mouse.click(box['x']+offset_x+(b['x']+b['w']/2)*scale,box['y']+offset_y+(b['y']+b['h']/2)*scale)
    page.wait_for_timeout(220)

def open_tools(page):
    if not page.locator('#game-tools').is_visible(): page.locator('#tools-toggle').click()

def converse(page):
    if not any(b['y']==735 for b in page.evaluate('window.youxiaUI.buttons')): press(page,'交談 ·',last=True)
    found=[b for b in page.evaluate('window.youxiaUI.buttons') if b['y']==735 and not b['disabled']]
    assert found, page.evaluate('window.youxiaUI.buttons')
    press(page,found[0]['text'],prefix=False)
