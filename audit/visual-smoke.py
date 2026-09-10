"""Optional browser checks for the visual refresh. Requires Playwright, like
screenshots/capture.py. Start serve.py, then run: python audit/visual-smoke.py
Uses synthetic demo data exclusively and blocks every /data request.
Set BROWSER_CHANNEL=msedge or chrome to use an installed browser.
"""
import os
import re
from urllib.parse import urlparse

from playwright.sync_api import sync_playwright

base = os.environ.get('SERVER', 'http://127.0.0.1:8765').rstrip('/')
assert urlparse(base).hostname in ('127.0.0.1', 'localhost'), 'Use a local test server'
checks = []


def check(name, ok):
    assert ok, name
    checks.append(name)


with sync_playwright() as pw:
    browser = pw.chromium.launch(channel=os.environ.get('BROWSER_CHANNEL'))
    page = browser.new_page(viewport={'width': 390, 'height': 844}, locale='en-GB')
    errors, data_requests = [], []
    page.on('pageerror', lambda e: errors.append(str(e)))

    def block_data(route):
        data_requests.append(route.request.url)
        route.abort()

    page.route(re.compile(r'/data(?:\?.*)?$'), block_data)
    page.goto(base + '/?demo=1')
    page.wait_for_selector('.cash-hero')
    page.evaluate('() => { activeView="forecast"; render(); }')
    check('Phone forecast settings start collapsed',
          page.locator('[data-fc-panel][open]').count() == 0)

    # All views, both themes, desktop/tablet/phone and small-phone widths.
    for theme in ('dark', 'light'):
        page.evaluate('(theme) => { data.settings.theme=theme; applyTheme(); }', theme)
        for width in (1440, 768, 390, 320):
            page.set_viewport_size({'width': width, 'height': 900})
            for view in ('dashboard', 'envelopes', 'transactions', 'forecast', 'reports',
                         'accounts', 'recurring', 'networth', 'settings', 'help'):
                page.evaluate('(v) => { activeView=v; render(); }', view)
                page.evaluate('() => new Promise(r => requestAnimationFrame(() => requestAnimationFrame(r)))')
                check(f'No page overflow: {theme}, {width}px, {view}', page.evaluate(
                    '() => document.documentElement.scrollWidth <= document.documentElement.clientWidth + 1'))

    page.set_viewport_size({'width': 390, 'height': 844})
    page.evaluate('() => { activeView="transactions"; render(); }')
    check('Bulk actions hidden without selection', not page.locator('#txBulk').is_visible())
    page.locator('[data-sel-tx]').first.check()
    check('Bulk actions appear on selection', page.locator('#txBulk').is_visible())
    page.locator('#bulkClear').click()
    check('Bulk actions hide after clearing', not page.locator('#txBulk').is_visible())
    page.locator('#txFilterToggle').click()
    page.locator('#txTypeFilter').select_option('expense')
    check('Filter count updates', page.locator('#txFilterToggle').inner_text() == 'Filters (1)')
    page.locator('#txFilterToggle').click()
    check('Collapsed filter stays active', page.evaluate('() => txFilter.type === "expense"'))
    page.locator('#addTx').click()
    page.wait_for_function('document.activeElement.id === "t_amt"')
    page.locator('#t_save').click()
    check('Required amount error beside field', page.locator('#t_amt').get_attribute('aria-invalid') == 'true')
    page.locator('#t_amt').fill('12+')
    page.locator('#t_save').click()
    check('Invalid arithmetic stays in form', 'valid amount' in page.locator('#t_amt_error').inner_text())
    page.locator('#t_amt').fill('50+12')
    check('Editing clears error', page.locator('#t_amt_error').count() == 0)
    page.locator('#t_acc').select_option(index=1)
    page.locator('#t_env').select_option(index=1)
    page.locator('#t_payee').fill('Visual smoke test')
    page.locator('.tx-notes summary').click()
    page.locator('#t_notes').fill('Note retained')
    page.locator('#t_save').click()
    check('Calculation and note saved', page.evaluate(
        '() => data.transactions.at(-1).amount === 62 && data.transactions.at(-1).notes === "Note retained"'))
    check('Filter preserved through save', page.evaluate('() => txFilter.type === "expense"'))
    check('Focus returns to Add', page.evaluate('() => document.activeElement.id === "addTx"'))
    page.locator('[data-edit-tx]').first.click()
    check('Saved notes reopen expanded', page.locator('.tx-notes').get_attribute('open') is not None)
    page.keyboard.press('Escape')

    # Split validation and valid saving use the existing bookkeeping path.
    page.evaluate('() => quickTx("expense", {})')
    page.locator('#t_amt').fill('100')
    page.locator('#t_split_on').click()
    page.locator('#t_save').click()
    check('Incomplete split refused', page.locator('.t-split-env').first.get_attribute('aria-invalid') == 'true')
    page.locator('.t-split-env').nth(0).select_option(index=1)
    page.locator('.t-split-env').nth(1).select_option(index=2)
    page.locator('.t-split-amt').nth(0).fill('40')
    page.locator('.t-split-amt').nth(1).fill('50')
    page.locator('#t_save').click()
    check('Unbalanced split refused', page.locator('.field-error').count() > 0)
    page.locator('.t-split-amt').nth(1).fill('60')
    page.locator('#t_save').click()
    check('Balanced split saved', page.evaluate('() => data.transactions.at(-1).splits.reduce((s,x)=>s+x.amount,0) === 100'))
    page.evaluate('() => quickTx("transfer-account", {})')
    page.locator('#t_amt').fill('10')
    page.locator('#t_save').click()
    check('Same-account transfer refused', page.locator('#t_tacc').get_attribute('aria-invalid') == 'true')
    page.locator('#t_tacc').select_option(index=1)
    page.locator('#t_save').click()
    check('Valid transfer saved', page.evaluate('() => data.transactions.at(-1).type === "transfer-account"'))
    page.evaluate('() => quickTx("expense", {})')
    page.set_viewport_size({'width': 390, 'height': 450})
    box = page.locator('#t_save').bounding_box()
    check('Footer visible in short viewport', box['y'] >= 0 and box['y'] + box['height'] <= 450)
    page.keyboard.press('Escape')
    page.set_viewport_size({'width': 390, 'height': 844})
    page.locator('#mobileMore').click()
    page.locator('[data-more-view="reports"]').click()
    check('More opens Reports', page.evaluate('() => activeView === "reports"'))
    check('More marks active secondary view', page.locator('#mobileMore').get_attribute('aria-current') == 'true')

    page.evaluate('() => { activeView="forecast"; render(); }')
    page.locator('[data-fc-panel="assumptions"]').evaluate('(d) => d.open=true')
    page.locator('#fcAllow').check()
    page.locator('[data-fc-h="7"]').click()
    check('Forecast sections survive horizon changes', page.locator('[data-fc-panel="assumptions"]').get_attribute('open') is not None)
    page.locator('input[name="fcLines"][value="spendable"]').check()
    check('Spendable mode disables redundant overlay', page.locator('#fcSpend').is_disabled())
    page.evaluate('() => { forecastState.accountIds=[]; activeView="dashboard"; render(); }')
    check('Empty selection is respected', 'Select accounts' in page.locator('.cash-hero').inner_text())
    page.evaluate('''() => {
      data=demoData(); forecastState.accountIds=null; forecastState.days=7;
      forecastState.chartLines='individual'; forecastState.includeAllowances=false; render();
    }''')
    check('Dashboard low matches exact horizon independently of chart lines', page.evaluate('''() => {
      const ids=activeAccounts().filter(a=>!a.isInvestment && a.includeInNetWorth!==false).map(a=>a.id);
      return document.getElementById('dashSpendableLow').textContent ===
        fmt(spendableLow(forecastAccountBalances(ids,7,{includeAllowances:false})).min);
    }'''))
    page.evaluate('''() => {
      data.accounts=[{id:'cash',name:'Cash',type:'checking',openingBalance:1000,includeInNetWorth:true}];
      data.envelopes=[{id:'food',name:'Food',openingBalance:300,budgetAmount:0,cadence:'monthly'}];
      data.transactions=[];
      data.recurring=[{id:'bill',name:'Due bill',type:'expense',amount:100,accountId:'cash',schedule:'once',startDate:todayISO(),active:true}];
      forecastState.accountIds=['cash']; render();
    }''')
    check('Actual cash differs correctly from pending-bill projection', page.evaluate('''() =>
      document.getElementById('dashSpendableToday').textContent===fmt(700) &&
      document.getElementById('dashSpendableLow').textContent===fmt(600)'''))
    check('No runtime errors', not errors)
    check('Demo never requested the real data API', not data_requests)
    browser.close()

print(f'{len(checks)} visual smoke checks passed (80 responsive/theme combinations).')
