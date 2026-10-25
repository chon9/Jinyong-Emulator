"""Verify sect teacher travel and paid training through the shipped web UI."""
import argparse
import functools
import http.server
import os
import threading
from pathlib import Path

from playwright.sync_api import sync_playwright
from browser_audio_test import QuietHandler
from browser_ui_helpers import press

ROOT = Path(__file__).resolve().parents[1]
DESTINATIONS = [
    ("華山", "華山派", "正氣堂"),
    ("武當", "武當派", "演武場"),
    ("少林", "少林派", "羅漢堂"),
    ("全真", "全真教", "重陽宮"),
    ("古墓", "全真教", "古墓"),
]


def run(url):
    server = None
    if not url:
        server = http.server.ThreadingHTTPServer(
            ("127.0.0.1", 0),
            functools.partial(QuietHandler, directory=str(ROOT / "sites/youxia-web/dist")),
        )
        threading.Thread(target=server.serve_forever, daemon=True).start()
        url = f"http://127.0.0.1:{server.server_port}"
    errors = []
    try:
        with sync_playwright() as p:
            chrome = sorted((Path(os.environ["LOCALAPPDATA"]) / "ms-playwright").glob("chromium-*/chrome-win/chrome.exe"))[-1]
            browser = p.chromium.launch(headless=True, executable_path=str(chrome), args=["--enable-unsafe-swiftshader", "--use-angle=swiftshader"])
            for sect, region, scene in DESTINATIONS:
                context = browser.new_context(viewport={"width": 1440, "height": 900})
                page = context.new_page()
                page.on("pageerror", lambda e: errors.append(str(e)))
                page.on("console", lambda m: errors.append(m.text) if m.type == "error" or m.text.startswith(("ERROR:", "SCRIPT ERROR:")) else None)
                page.goto(url)
                page.get_by_role("button", name="進入江湖").click()
                page.wait_for_function("document.documentElement.dataset.gameReady==='true'", timeout=180000)
                page.locator("#canvas").focus()
                page.keyboard.press("k")
                page.wait_for_timeout(250)
                press(page, "前往師父", prefix=False)
                status = page.evaluate("youxiaChapterStatus")
                assert (status["region"], status["scene"], status["page"]) == ("嘉興鎮", "演武坪", "武學"), status
                press(page, "拜入" + sect, prefix=False)
                press(page, "前往師父", prefix=False)
                status = page.evaluate("youxiaChapterStatus")
                assert (status["region"], status["scene"], status["page"]) == (region, scene, "武學"), status
                press(page, "消點進修")
                assert "提升至 2 重" in page.evaluate("youxiaChapterStatus.notice")
                print(f"PASS: {sect} -> {region}/{scene}, learning stays open and paid training succeeds", flush=True)
                if sect == "華山" and server:
                    page.screenshot(path=str(ROOT / "test-results/teacher-huashan.png"))
                # The destination and membership must survive the player's next visit.
                page.reload()
                page.get_by_role("button", name="進入江湖").click()
                page.wait_for_function("document.documentElement.dataset.gameReady==='true'", timeout=180000)
                status = page.evaluate("youxiaChapterStatus")
                assert (status["region"], status["scene"]) == (region, scene), status
                page.locator("#canvas").focus()
                page.keyboard.press("k")
                page.wait_for_timeout(250)
                press(page, "前往師父", prefix=False)
                assert page.evaluate("youxiaChapterStatus.scene") == scene
                context.close()
            assert not errors, errors
            browser.close()
    finally:
        if server:
            server.shutdown()
            server.server_close()


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--url")
    run(parser.parse_args().url)
