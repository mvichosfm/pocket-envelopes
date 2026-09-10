"""Browser-to-disk smoke checks. Run only through audit/run_browser.py."""
import os
from urllib.parse import urlparse

from playwright.sync_api import sync_playwright

assert os.environ.get("POCKET_AUDIT_SCRATCH") == "1", "Use audit/run_browser.py"
base = os.environ["SERVER"]
assert urlparse(base).hostname == "127.0.0.1"

with sync_playwright() as pw:
    browser = pw.chromium.launch(channel=os.environ.get("BROWSER_CHANNEL"))
    context = browser.new_context(service_workers="block")
    errors = []
    first = context.new_page()
    first.on("pageerror", lambda error: errors.append(str(error)))
    initial = context.request.get(base + "/data")
    assert initial.headers.get("x-data-new") == "1", "Refuse to test an existing budget"
    first.goto(base)
    first.locator("#welNew").click()
    first.wait_for_function("data !== null && !dirty && !saveInFlight")
    second = context.new_page()
    second.on("pageerror", lambda error: errors.append(str(error)))
    second.goto(base)
    second.wait_for_function("loadState === 'loaded'")
    # Both tabs have the same ETag. Only the first edit should reach disk.
    assert first.evaluate("""async () => {
      data.accounts.push({id:'audit_a',name:'Synthetic A',type:'checking',openingBalance:100});
      saveDirty(); return await writeFile();
    }""")
    assert not second.evaluate("""async () => {
      data.accounts.push({id:'audit_b',name:'Synthetic B',type:'checking',openingBalance:200});
      saveDirty(); return await writeFile();
    }""")
    second.locator("#cf_force").wait_for(state="visible")
    assert context.request.get(base + "/data").json()["accounts"][0]["id"] == "audit_a"
    assert second.evaluate("dirty && conflictPending")
    second.locator("#cf_force").click()
    second.wait_for_function("!dirty && !saveInFlight && !conflictPending")
    first.reload()
    first.wait_for_function("loadState === 'loaded'")
    assert first.evaluate("data.accounts[0].id") == "audit_b"
    # Restore through the same browser-backup function used in Settings.
    assert first.evaluate("""async () => {
      const backup = listBackups()[0];
      if (!backup) throw Error('No daily backup');
      restoreBackup(backup.date);
      return await writeFile();
    }""")
    first.reload()
    first.wait_for_function("loadState === 'loaded'")
    assert first.evaluate("data.accounts.length") == 0
    assert context.request.get(base + "/data").json()["accounts"] == []

    damaged = context.new_page()
    damaged.on("pageerror", lambda error: errors.append(str(error)))
    damaged.route("**/data", lambda route: route.fulfill(status=200, body="{broken", content_type="application/json"))
    damaged.goto(base)
    damaged.wait_for_function("loadState === 'failed' && document.getElementById('main').textContent.length > 0")
    assert damaged.locator("#welNew").count() == 0
    assert not errors, errors
    browser.close()

print("Browser persistence passed: create, save, conflict, explicit overwrite, reload, backup restore, corrupt-load guard.")
