"""Regenerate the README screenshots from the demo dataset.

    python screenshots/capture.py            # needs: pip install playwright && playwright install chromium

Points headless Chromium at a running server (default http://127.0.0.1:8765,
override with the SERVER environment variable) in ?demo=1 mode, which never
reads or writes finance-data.json. Viewport 1400x900, dark theme (the demo's
default), one PNG per view into this folder. The browser UI language is forced
to English because native <input type="month"> follows the browser language,
not the page locale.
"""
import os
from pathlib import Path

from playwright.sync_api import sync_playwright

OUT = Path(__file__).resolve().parent
BASE = os.environ.get("SERVER", "http://127.0.0.1:8765") + "/?demo=1"
VIEWS = ["dashboard", "envelopes", "transactions", "forecast", "reports"]

with sync_playwright() as p:
    browser = p.chromium.launch(args=["--lang=en-GB"])
    page = browser.new_page(viewport={"width": 1400, "height": 900}, device_scale_factor=1,
                            color_scheme="dark", locale="en-GB")
    for view in VIEWS:
        page.goto(f"{BASE}&view={view}", wait_until="networkidle")
        page.wait_for_selector("#main .card, #main table", timeout=10000)
        page.wait_for_timeout(1200)      # let the charts animate in
        page.mouse.move(0, 0)            # no hover states in the shot
        target = OUT / f"{view}.png"
        page.screenshot(path=str(target), full_page=False)
        print("wrote", target.name, target.stat().st_size // 1024, "KB")
    browser.close()
