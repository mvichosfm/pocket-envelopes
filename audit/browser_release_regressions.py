"""Release-blocker regressions against a disposable server, never a real budget."""
import os
import unittest
from urllib.parse import urlparse

from playwright.sync_api import sync_playwright

assert os.environ.get('POCKET_AUDIT_SCRATCH') == '1', 'Use audit/run_browser.py'
BASE = os.environ['SERVER']
assert urlparse(BASE).hostname == '127.0.0.1'

SEED = """() => {
  data=emptyData();
  data.accounts=[{id:'a',name:'Checking',type:'checking',openingBalance:1000,includeInNetWorth:true},
    {id:'b',name:'Investment',type:'investment',isInvestment:true,openingBalance:100,includeInNetWorth:true}];
  data.envelopes=[{id:'e',name:'Groceries',openingBalance:300,budgetAmount:100,cadence:'monthly',rolloverPolicy:'rollover'},
    {id:'f',name:'Reserve',openingBalance:50,budgetAmount:0,cadence:'monthly',rolloverPolicy:'rollover',isReserve:true}];
  const start=isoDate(new Date(new Date().getFullYear(),new Date().getMonth()-2,1));
  data.recurring=[{id:'r',name:'Paid bill',type:'expense',amount:50,accountId:'a',envelopeId:'e',schedule:'monthly',
    startDate:start,lastAppliedDate:todayISO().slice(0,7)+'-01',active:true}];
  data.transactions=[0,1,2].map(i=>({id:'paid_'+i,type:'expense',amount:50,accountId:'a',envelopeId:'e',fromRecurringId:'r',
    date:isoDate(new Date(new Date().getFullYear(),new Date().getMonth()-i,1))}));
  activeView='recurring';render();undoStack.length=0;redoStack.length=0;
}"""


class ReleaseRegressions(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.pw = sync_playwright().start()
        engine = os.environ.get('BROWSER_ENGINE', 'chromium')
        kwargs = {'timeout': 20000}
        if engine == 'chromium':
            kwargs['channel'] = os.environ.get('BROWSER_CHANNEL')
        cls.browser = getattr(cls.pw, engine).launch(**kwargs)

    @classmethod
    def tearDownClass(cls):
        cls.browser.close()
        cls.pw.stop()

    def setUp(self):
        self.context = self.browser.new_context(service_workers='block')
        self.page = self.context.new_page()
        self.page.set_default_timeout(8000)
        self.errors = []
        self.page.on('pageerror', lambda error: self.errors.append(str(error)))
        self.page.goto(BASE + '/?demo=1')
        self.page.wait_for_function('data !== null')
        self.page.evaluate(SEED)

    def tearDown(self):
        self.context.close()
        self.assertEqual(self.errors, [])

    def state(self):
        return self.page.evaluate('JSON.stringify(data)')

    def reset(self):
        self.page.evaluate('closeModal()')
        self.page.evaluate(SEED)

    def test_recurring_edits_preserve_paid_history(self):
        for field, value in [('r_name', 'Renamed'), ('r_notes', 'New note'), ('r_amt', '60'),
                             ('r_start', '2025-01-01'), ('r_sched', 'weekly')]:
            with self.subTest(field=field):
                self.reset()
                before = self.page.evaluate('({date:data.recurring[0].lastAppliedDate,txs:JSON.stringify(data.transactions)})')
                self.page.locator('[data-edit-rec="r"]').click()
                if field == 'r_sched': self.page.locator('#'+field).select_option(value)
                else: self.page.locator('#'+field).fill(value)
                self.page.locator('#r_save').click()
                self.assertEqual(self.page.evaluate('data.recurring[0].lastAppliedDate'), before['date'])
                self.assertEqual(self.page.evaluate('JSON.stringify(data.transactions)'), before['txs'])
                self.assertTrue(self.page.evaluate('dueRecurringOccurrences().every(o=>o.date>data.recurring[0].lastAppliedDate)'))

    def test_unchanged_forms_leave_budget_and_undo_untouched(self):
        for opener, save in [('editAccount("a")', 'f_save'), ('editEnvelope("e")', 'f_save'), ('editRecurring("r")', 'r_save')]:
            with self.subTest(opener=opener):
                self.reset(); before = self.state()
                self.page.evaluate(opener); self.page.locator('#'+save).click()
                self.assertEqual(self.state(), before)
                self.assertEqual(self.page.evaluate('undoStack.length'), 0)

    def test_invalid_forms_and_cancel_do_not_mutate_or_snapshot(self):
        for opener, field in [('editAccount("a")','f_open'), ('editAccount("a")','f_current'), ('editEnvelope("e")','f_bud')]:
            with self.subTest(opener=opener):
                self.reset(); before = self.state()
                self.page.evaluate(opener)
                self.page.locator('#f_name').fill('Rejected rename')
                self.page.locator('#'+field).fill('100+')
                if field == 'f_bud':
                    # A proposed balance adjustment must not snapshot before budget validation.
                    self.page.locator('#f_adjust').fill('200')
                    self.page.locator('#f_reserve').check()
                self.page.locator('#f_save').click()
                self.assertEqual(self.state(), before)
                self.assertEqual(self.page.evaluate('undoStack.length'), 0)
                self.page.get_by_role('button',name='Cancel',exact=True).click()
                self.assertEqual(self.state(), before)

    def test_successful_mutations_undo_and_redo_exactly_once(self):
        for action in ['move','value','account','recurring','pause','reserve','adjustment','add-account','add-envelope','add-recurring']:
            with self.subTest(action=action):
                self.reset(); before = self.state()
                p = self.page
                if action=='move':
                    p.evaluate('transferEnvelopes("e")'); p.locator('#tr_to').select_option('f'); p.locator('#tr_amt').fill('25'); p.locator('#tr_save').click()
                elif action=='value':
                    p.evaluate('updateInvestmentValue("b")'); p.locator('#iv_value').fill('120'); p.locator('#iv_save').click()
                elif action in ('account','add-account'):
                    p.evaluate('editAccount("a")' if action=='account' else 'editAccount()')
                    p.locator('#f_name').fill('New account'); p.locator('#f_open').fill('1200'); p.locator('#f_save').click()
                elif action in ('recurring','add-recurring'):
                    p.evaluate('editRecurring("r")' if action=='recurring' else 'editRecurring()')
                    p.locator('#r_name').fill('New recurring');p.locator('#r_amt').fill('60');p.locator('#r_save').click()
                elif action=='pause': p.locator('[data-toggle-rec="r"]').click()
                else:
                    p.evaluate('editEnvelope()' if action=='add-envelope' else 'editEnvelope("e")')
                    p.locator('#f_name').fill('New envelope')
                    if action=='reserve': p.locator('#f_reserve').check()
                    if action=='adjustment': p.locator('#f_adjust').fill('200')
                    p.locator('#f_save').click()
                after = self.state()
                self.assertNotEqual(after, before)
                self.assertEqual(p.evaluate('undoStack.length'), 1)
                p.evaluate('performUndo()'); self.assertEqual(self.state(), before)
                p.evaluate('performRedo()'); self.assertEqual(self.state(), after)

    def test_undo_move_retains_preceding_purchase(self):
        p = self.page
        p.evaluate("pushUndo('Earlier purchase');data.transactions.push({id:'earlier',type:'expense',amount:10,accountId:'a',envelopeId:'e',date:todayISO()});render()")
        before = self.state()
        p.evaluate('transferEnvelopes("e")'); p.locator('#tr_to').select_option('f'); p.locator('#tr_amt').fill('25'); p.locator('#tr_save').click()
        p.evaluate('performUndo()'); self.assertEqual(self.state(), before)

    def test_recurring_requires_valid_dates_and_months(self):
        for start,end,schedule,months in [('', '', 'monthly', ''), ('2026-09-01','2026-08-31','monthly',''), ('2026-09-01','','custom-months','0,13')]:
            with self.subTest(start=start,end=end,schedule=schedule):
                self.reset(); before = self.state(); p = self.page
                p.evaluate('editRecurring()');p.locator('#r_name').fill('Invalid');p.locator('#r_amt').fill('20')
                p.locator('#r_start').fill(start);p.locator('#r_end').fill(end);p.locator('#r_sched').select_option(schedule)
                if schedule=='custom-months':p.locator('#r_months').fill(months)
                p.locator('#r_save').click();self.assertEqual(self.state(),before);self.assertEqual(p.evaluate('undoStack.length'),0)
        self.assertFalse(self.page.evaluate('validISODate("2026-02-30")'))

    def test_malformed_history_requires_explicit_repair(self):
        p=self.page;p.evaluate('data.recurring[0].lastAppliedDate="NaN-NaN-NaN";render()');before=self.state()
        p.locator('[data-edit-rec="r"]').click();p.locator('#r_save').click()
        self.assertEqual(self.state(),before);self.assertEqual(p.evaluate('undoStack.length'),0)
        p.locator('#r_history').fill('2026-09-01');p.locator('#r_save').click()
        self.assertEqual(p.evaluate('data.recurring[0].lastAppliedDate'),'2026-09-01')
        self.assertTrue(p.evaluate('validISODate(data.recurring[0].lastAppliedDate)'))
        p.evaluate('performUndo()');self.assertEqual(self.state(),before)

    def test_duplicate_keeps_settings_but_has_independent_history(self):
        for kind in ('expense','income','transfer-account','transfer-envelope'):
            with self.subTest(kind=kind):
                self.reset();p=self.page
                p.evaluate("type=>Object.assign(data.recurring[0],{type,active:false,schedule:'custom-months',months:[1,4,12],tag:'Unlisted',notes:'Copy notes',skippedDates:['2030-01-01'],fromAccountId:'a',toAccountId:'b',fromEnvelopeId:'e',toEnvelopeId:'f'})",kind)
                p.evaluate('render()');before=self.state()
                p.locator('[data-dup-rec="r"]').click();p.get_by_role('button',name='Cancel',exact=True).click();self.assertEqual(self.state(),before)
                p.locator('[data-dup-rec="r"]').click();p.locator('#r_start').fill('2030-01-01');p.locator('#r_save').click()
                self.assertTrue(p.evaluate("""() => {const [a,b]=data.recurring;return a.id!==b.id && b.lastAppliedDate==='2029-12-31' && !b.skippedDates && b.active===false && b.type===a.type && b.tag===a.tag && b.notes===a.notes && JSON.stringify(b.months)===JSON.stringify(a.months)}"""))
                p.evaluate('performUndo()');self.assertEqual(self.state(),before)

    def test_invalid_locale_rejected_and_saved_locale_falls_back(self):
        p=self.page;p.evaluate('activeView="settings";render()');before=self.state()
        p.locator('#s_loc').fill('el_GR');p.locator('#s_loc').press('Tab')
        self.assertEqual(self.state(),before);self.assertEqual(p.locator('#s_loc').get_attribute('aria-invalid'),'true')
        p.set_viewport_size({'width':320,'height':900})
        self.assertTrue(p.evaluate('document.documentElement.scrollWidth<=document.documentElement.clientWidth+1'))
        p.evaluate('demoMode=false');self.assertTrue(p.evaluate('writeFile()'))
        self.assertNotEqual(p.request.get(BASE+'/data').json()['settings']['locale'],'el_GR')
        p.locator('#s_loc').fill(' el-GR ');p.locator('#s_loc').press('Tab')
        self.assertEqual(p.evaluate('data.settings.locale'),'el-GR')
        # Simulate importing an older file already containing the invalid locale.
        p.evaluate("data.settings.locale='el_GR';data=safeParseData(JSON.stringify(data),'legacy fixture')")
        self.assertTrue(p.evaluate('writeFile()'));p.goto(BASE);p.wait_for_function('loadState === "loaded"')
        for view in ('dashboard','transactions','forecast','reports','networth','settings'):
            p.evaluate('(v)=>{activeView=v;render()}',view)
            self.assertTrue(p.locator('#main').inner_text())

    def test_dismissed_undo_action_cannot_take_keyboard_focus(self):
        p=self.page;p.evaluate("toast('Temporary',20,'success',{label:'Undo',onClick:performUndo})")
        p.wait_for_function('getComputedStyle(document.querySelector("#toast")).opacity === "0"')
        p.locator('.toast-action').focus()
        self.assertFalse(p.evaluate('document.activeElement.classList.contains("toast-action")'))
        p.evaluate("toast('New action',10000,'info',{label:'Action',onClick:()=>{}})")
        p.locator('.toast-action').focus();self.assertTrue(p.evaluate('document.activeElement.classList.contains("toast-action")'))

    def test_focus_survives_row_edit_and_deleted_trigger(self):
        p=self.page;p.locator('[data-edit-rec="r"]').click();p.locator('#r_amt').fill('60');p.locator('#r_save').click()
        self.assertEqual(p.evaluate('document.activeElement.dataset.editRec'),'r')
        p.on('dialog',lambda dialog:dialog.accept());p.locator('[data-del-rec="r"]').click()
        self.assertEqual(p.evaluate('document.activeElement.tagName'),'H2')

    def test_settings_labels_and_blocked_storage(self):
        p=self.page;p.evaluate('activeView="settings";render()')
        self.assertTrue(p.evaluate("['s_curr','s_loc','s_fcfloor','s_taglimit','s_theme'].every(id=>document.getElementById(id).labels.length===1)"))
        p.evaluate("""() => {const get=Storage.prototype.getItem;Storage.prototype.getItem=()=>{throw new DOMException('Blocked','SecurityError')};try{activeView='forecast';render()}finally{Storage.prototype.getItem=get}}""")
        self.assertTrue(p.evaluate('!!currentChart'))


if __name__ == '__main__':
    unittest.main(verbosity=2)
