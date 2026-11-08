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
                p.evaluate("type=>Object.assign(data.recurring[0],{type,active:false,schedule:'custom-months',months:[1,4,12],tag:'Unlisted',notes:'Copy notes',skippedDates:['2030-01-01'],overrides:{'2030-04-01':{amount:1}},fromAccountId:'a',toAccountId:'b',fromEnvelopeId:'e',toEnvelopeId:'f'})",kind)
                p.evaluate('render()');before=self.state()
                p.locator('[data-dup-rec="r"]').click();p.get_by_role('button',name='Cancel',exact=True).click();self.assertEqual(self.state(),before)
                p.locator('[data-dup-rec="r"]').click();p.locator('#r_start').fill('2030-01-01');p.locator('#r_save').click()
                self.assertTrue(p.evaluate("""() => {const [a,b]=data.recurring;return a.id!==b.id && b.lastAppliedDate==='2029-12-31' && !b.skippedDates && !b.overrides && b.active===false && b.type===a.type && b.tag===a.tag && b.notes===a.notes && JSON.stringify(b.months)===JSON.stringify(a.months)}"""))
                p.evaluate('performUndo()');self.assertEqual(self.state(),before)

    def test_occurrences_dialog_changes_one_date_only(self):
        p=self.page;before=self.state()
        dates=p.evaluate('upcomingOccurrenceDates(data.recurring[0],3)')
        # one date gets its own amount, the next is skipped; the template is untouched
        p.locator('[data-occ-rec="r"]').click()
        p.locator(f'[data-occ-amt="{dates[0]}"]').fill('75');p.locator(f'[data-occ-skip="{dates[1]}"]').click();p.locator('#occSave').click()
        self.assertEqual(p.evaluate('JSON.stringify([data.recurring[0].amount,data.recurring[0].overrides,data.recurring[0].skippedDates])'),
                         f'[50,{{"{dates[0]}":{{"amount":75}}}},["{dates[1]}"]]')
        self.assertEqual(p.evaluate('firstPendingOccurrence(data.recurring[0])'),dates[0])
        self.assertIn('this time',p.locator('#main table tbody tr').first.inner_text())
        self.assertTrue(p.evaluate(f"""() => {{const fc=forecastAccountBalances(['a'],120,{{includeAllowances:false}});
            const i=fc.dates.indexOf('{dates[0]}'),j=fc.dates.indexOf('{dates[1]}');
            return i>0 && j>0 && Math.abs(fc.total[i-1]-fc.total[i]-75)<0.005 && Math.abs(fc.total[j-1]-fc.total[j])<0.005;}}"""),
            'the forecast books the custom amount on its date and nothing on the skipped one')
        p.evaluate('performUndo()');self.assertEqual(self.state(),before)
        # back to the template amount removes the entry, unskip removes the date; an unchanged form takes no snapshot
        p.locator('[data-occ-rec="r"]').click();p.locator(f'[data-occ-amt="{dates[0]}"]').fill('75');p.locator(f'[data-occ-skip="{dates[1]}"]').click();p.locator('#occSave').click()
        p.locator('[data-occ-rec="r"]').click();p.locator(f'[data-occ-amt="{dates[0]}"]').fill('50');p.locator(f'[data-occ-skip="{dates[1]}"]').click();p.locator('#occSave').click()
        self.assertEqual(self.state(),before)
        undo_len=p.evaluate('undoStack.length')
        p.locator('[data-occ-rec="r"]').click();p.locator('#occSave').click()
        self.assertEqual(p.evaluate('undoStack.length'),undo_len)
        # a non-evaluating amount refuses the save and leaves the budget untouched
        p.locator('[data-occ-rec="r"]').click();p.locator(f'[data-occ-amt="{dates[0]}"]').fill('12+');p.locator('#occSave').click()
        self.assertEqual(self.state(),before);p.evaluate('closeModal()')

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

    def test_quick_add_param_opens_form_once_and_offers_another(self):
        p=self.page
        for kind in ('income','transfer-account','expense'):
            p.goto(BASE+'/?demo=1&view=transactions&add='+kind)
            p.wait_for_function('document.getElementById("modalBg").classList.contains("open")')
            self.assertEqual(p.locator('#t_type').input_value(),kind)
            self.assertEqual(p.evaluate('document.activeElement.id'),'t_amt')
            self.assertNotIn('add=',p.url);self.assertIn('view=transactions',p.url)
        # The expense starts on the last hand-entered expense's account, not "(none)".
        want=p.evaluate("sortTxsDesc(data.transactions.filter(t=>t.type==='expense'&&t.accountId&&!t.fromRecurringId&&t.date<=todayISO()))[0].accountId")
        self.assertEqual(p.locator('#t_acc').input_value(),want)
        n=p.evaluate('data.transactions.length')
        p.locator('#t_amt').fill('12.5');p.locator('#t_save').click()
        self.assertEqual(p.evaluate('data.transactions.length'),n+1)
        p.locator('.toast-action',has_text='Add another').click()
        p.wait_for_function('document.getElementById("modalBg").classList.contains("open")')
        self.assertEqual(p.locator('#t_type').input_value(),'expense')
        # An ordinary add carries no "Add another".
        p.evaluate('closeModal();quickTx("expense")');p.locator('#t_amt').fill('3');p.locator('#t_save').click()
        self.assertFalse(p.evaluate("(t=>t.classList.contains('show')&&t.textContent.includes('Add another'))(document.getElementById('toast'))"))
        p.goto(BASE+'/?demo=1&add=bogus');p.wait_for_function('data !== null')
        self.assertFalse(p.evaluate('document.getElementById("modalBg").classList.contains("open")'))

    def test_bank_statement_reconciles_auto_logs_and_queues(self):
        """Decision #75: a statement with a different closing balance books the sure line, queues the rest, and never repeats."""
        p = self.page
        p.evaluate("""() => {
          data=emptyData();
          data.accounts=[{id:'eb',name:'Bank',type:'checking',openingBalance:1000,includeInNetWorth:true}];
          data.envelopes=['Groceries','Health','Cash'].map((n,i)=>({id:'e'+i,name:n,budgetAmount:0,cadence:'monthly',rolloverPolicy:'rollover'}));
          data.transactions=[['2024-01-04',41],['2024-01-18',55],['2024-02-02',47],['2024-02-16',36],['2024-03-01',20]]
            .map((x,i)=>({id:'h'+i,date:x[0],type:'expense',amount:x[1],accountId:'eb',envelopeId:'e0',payee:'Corner Market',notes:''}));
          activeView='reconcile';render();undoStack.length=0;redoStack.length=0;
        }""")
        csv = ("Date,Description,Amount,Balance\n2024-03-01,CORNER MARKET 12,-20.00,801.00\n"
               "2024-03-04,CORNER MARKET 12,-30.00,771.00\n2024-03-06,DENTIST CLINIC,-120.00,651.00\n")
        def check_statement():
            p.evaluate("bankImportStart('eb')")
            p.locator('#bk_file').set_input_files({'name': 's.csv', 'mimeType': 'text/csv', 'buffer': csv.encode()})
            p.wait_for_function('document.getElementById("bk_bal") && document.getElementById("bk_bal").value==="651.00"')
            self.assertEqual(p.locator('#bk_asof').input_value(), '2024-03-06')
            p.locator('#bk_go').click()
            p.wait_for_function('activeView==="reconcile" && !document.getElementById("modalBg").classList.contains("open")')
        check_statement()
        # The 30.00 line is a Corner Market the history is sure about: booked, flagged, tied to its line; the dentist waits.
        self.assertEqual(p.evaluate("data.transactions.filter(t=>t.bankAuto).map(t=>[t.amount,t.envelopeId,t.payee,t.source])"), [[30, 'e0', 'Corner Market', 'statement']])
        self.assertEqual(p.evaluate("data.bankQueue.map(q=>[q.status,q.amount,q.desc])"), [['open', -120, 'DENTIST CLINIC']])
        self.assertEqual(p.evaluate("bankStatus(data.accounts[0]).diff"), -120)
        self.assertEqual(p.evaluate('undoStack.length'), 1, 'one undo step for the whole run')
        self.assertIn('DENTIST CLINIC', p.locator('#main').inner_text())
        # Reconcile by hand, splitting the payment over two envelopes.
        p.locator('[data-bank-resolve]').click()
        p.wait_for_function('document.getElementById("modalBg").classList.contains("open")')
        self.assertEqual(p.locator('#t_amt').input_value(), '120')
        p.locator('#t_split_on').click()
        rows = p.locator('#t_split_rows [data-split-row]')
        rows.nth(0).locator('.t-split-env').select_option('e1'); rows.nth(0).locator('.t-split-amt').fill('90')
        rows.nth(1).locator('.t-split-env').select_option('e2'); rows.nth(1).locator('.t-split-amt').fill('30')
        p.locator('#t_save').click()
        self.assertEqual(p.evaluate("data.bankQueue.length"), 0)
        self.assertEqual(p.evaluate("(()=>{const t=data.transactions.find(x=>x.bankDesc==='DENTIST CLINIC');return [t.splits.map(s=>s.amount),!!t.bankRef,!!t.bankAuto]})()"), [[90, 30], True, False])
        self.assertTrue(p.evaluate("bankStatus(data.accounts[0]).ok"), 'the app now matches the bank to the cent')
        # The same statement again changes nothing; deleting an auto-booked line does not bring it back.
        count = p.evaluate('data.transactions.length')
        check_statement()
        self.assertEqual(p.evaluate('data.transactions.length'), count)
        self.assertTrue(p.evaluate("data.accounts[0].bank.lastRun.balanced"))
        p.evaluate("confirm=()=>true;deleteTransaction(data.transactions.find(t=>t.bankAuto).id)")
        check_statement()
        self.assertEqual(p.evaluate("data.transactions.filter(t=>t.bankAuto).length"), 0)
        self.assertEqual(p.evaluate("data.bankQueue.map(q=>q.status)"), ['dismissed'])
        # Undo walks back through the steps without leaving a half-applied state.
        p.evaluate("performUndo();performUndo();performUndo()")        # the third check, the delete, the second check
        self.assertEqual(p.evaluate("[data.transactions.filter(t=>t.bankAuto).length,data.bankQueue.length,bankStatus(data.accounts[0]).ok]"), [1, 0, True])
        p.evaluate("performUndo()")                                      # the hand reconciliation
        self.assertEqual(p.evaluate("[data.bankQueue.map(q=>q.status),bankStatus(data.accounts[0]).diff]"), [['open'], -120])
        p.evaluate("performUndo()")                                      # the first check
        self.assertEqual(p.evaluate("[data.transactions.filter(t=>t.bankAuto).length,data.bankQueue.length,data.accounts[0].bank===undefined]"), [0, 0, True])

    def test_comparison_window_limits_which_lines_are_compared(self):
        """Decision #75: 'Compare lines from' leaves older lines (and the drift before them) out; what the window explains still adds up."""
        p = self.page
        p.evaluate("""() => {
          data=emptyData();
          data.accounts=[{id:'eb',name:'Bank',type:'checking',openingBalance:1000,includeInNetWorth:true}];
          data.envelopes=[{id:'e0',name:'Groceries',budgetAmount:0,cadence:'monthly',rolloverPolicy:'rollover'}];
          data.transactions=[['2024-01-04',41],['2024-01-18',55],['2024-02-02',47],['2024-02-16',36],['2024-03-01',20]]
            .map((x,i)=>({id:'h'+i,date:x[0],type:'expense',amount:x[1],accountId:'eb',envelopeId:'e0',payee:'Corner Market',notes:''}));
          activeView='reconcile';render();undoStack.length=0;redoStack.length=0;
        }""")
        csv = ("Date,Description,Amount,Balance\n2024-03-01,CORNER MARKET 12,-20.00,801.00\n"
               "2024-03-04,CORNER MARKET 12,-30.00,771.00\n2024-03-06,DENTIST CLINIC,-120.00,651.00\n")
        p.evaluate("bankImportStart('eb')")
        p.locator('#bk_file').set_input_files({'name': 's.csv', 'mimeType': 'text/csv', 'buffer': csv.encode()})
        p.wait_for_function('document.getElementById("bk_bal") && document.getElementById("bk_bal").value==="651.00"')
        self.assertRegex(p.locator('#bk_from').input_value(), r'^\d{4}-\d{2}-\d{2}$')
        p.locator('#bk_from').fill('2024-03-05')
        p.locator('#bk_from').dispatch_event('change')
        p.wait_for_function('document.querySelector(".modal").innerText.includes("1 statement line to compare from")')
        self.assertRegex(p.locator('.modal').inner_text(), r'bank 771[.,]00.*app 801[.,]00')      # the browser's locale decides the separator
        p.locator('#bk_go').click()
        p.wait_for_function('activeView==="reconcile" && !document.getElementById("modalBg").classList.contains("open")')
        self.assertEqual(p.evaluate("data.transactions.filter(t=>t.bankAuto).length"), 0, 'the 03-04 line is before the window: not booked')
        self.assertEqual(p.evaluate("data.bankQueue.map(q=>q.desc)"), ['DENTIST CLINIC'])
        self.assertEqual(p.evaluate("(()=>{const r=data.accounts[0].bank.lastRun;return [r.from,r.startGap,r.unexplained]})()"), ['2024-03-05', -30, 0])
        self.assertIn('Lines compared from', p.locator('#main').inner_text())

    def test_bank_buttons_work_in_a_window_that_swallows_browser_dialogs(self):
        """Playwright (like an embedded browser) auto-cancels confirm(); Dismiss and Stop must not depend on it. Both stay undoable."""
        p = self.page
        p.evaluate("""() => {
          data=emptyData();
          data.accounts=[{id:'eb',name:'Bank',type:'checking',openingBalance:0,includeInNetWorth:true,bank:{balance:10,asOf:'2024-03-06'}}];
          data.bankQueue=[{id:'q1',accountId:'eb',date:'2024-03-04',amount:-5,desc:'SOME SHOP',ref:'eb|x|0',status:'open',sug:{conf:0,payee:'',envelopeId:'',tag:'',why:'',rec:''}}];
          activeView='reconcile';render();undoStack.length=0;redoStack.length=0;
        }""")
        p.locator('[data-bank-dismiss="q1"]').click()
        self.assertEqual(p.evaluate("data.bankQueue[0].status"), 'dismissed')
        p.evaluate("performUndo()")
        self.assertEqual(p.evaluate("data.bankQueue[0].status"), 'open')
        p.locator('[data-bank-dismiss="q1"]').click()
        p.locator('[data-bank-reopen="q1"]').click() if p.locator('[data-bank-reopen="q1"]').is_visible() else p.locator('details.archived-list summary').click()
        p.locator('[data-bank-reopen="q1"]').click()
        self.assertEqual(p.evaluate("data.bankQueue[0].status"), 'open')
        p.locator('[data-bank-stop="eb"]').click()
        self.assertEqual(p.evaluate("data.accounts[0].bank"), None)
        p.evaluate("performUndo()")
        self.assertEqual(p.evaluate("data.accounts[0].bank.balance"), 10)

    def test_remote_fetch_button_follows_the_servers_status(self):
        """Decision #77: when the server offers /fetch, the button asks the server, follows its status and loads the result when done."""
        import json as _json
        p = self.page
        box = {'cur': {'state': 'idle', 'message': '', 'at': None}, 'posts': 0, 'post_status': 202}
        def handler(route):
            req = route.request
            if req.method == 'POST':
                box['posts'] += 1
                self.assertEqual(req.headers.get('x-requested-with'), 'pocket-envelopes')
                if box['post_status'] == 429:
                    return route.fulfill(status=429, content_type='application/json', body=_json.dumps({'error': 'too soon', 'retry_after': 120}))
                box['cur'] = {'state': 'starting', 'message': '', 'at': None}
                return route.fulfill(status=202, content_type='application/json', body=_json.dumps({'state': 'starting', 'status': box['cur']}))
            route.fulfill(status=200, content_type='application/json', body=_json.dumps({'enabled': True, 'status': box['cur']}))
        p.route('**/fetch', handler)
        p.evaluate("""() => { demoMode=false; bankFetchPollMs=200; window.bankFetchReload=()=>{window.__reloaded=true};
          data=emptyData(); data.accounts=[{id:'eb',name:'Bank',type:'checking',openingBalance:0,includeInNetWorth:true}];
          activeView='reconcile'; render(); }""")
        self.assertEqual(p.locator('#bankFetchBtn').count(), 0, 'before the probe: no server route known, no link set, no button')
        p.evaluate("bankFetchProbe()")
        p.wait_for_selector('#bankFetchBtn')
        self.assertEqual(p.locator('#bankFetchBtn').evaluate("e => e.tagName"), 'BUTTON')
        self.assertEqual(p.locator('#bankFetchStatus').inner_text(), '')
        # too soon: told, nothing starts
        box['post_status'] = 429
        p.locator('#bankFetchBtn').click()
        p.wait_for_function('document.body.innerText.includes("too soon")')
        box['post_status'] = 202
        p.locator('#bankFetchBtn').click()
        p.wait_for_function('document.getElementById("bankFetchBtn").disabled')
        self.assertIn('Asked the PC', p.locator('#bankFetchStatus').inner_text())
        box['cur'] = {'state': 'waiting-approval', 'message': '', 'at': None}
        p.wait_for_function('document.getElementById("bankFetchStatus").innerText.includes("Approve the login on your phone")')
        # With unsaved changes in this tab the page must NOT reload under the user: it says so instead.
        p.evaluate("dirty=true")
        box['cur'] = {'state': 'done', 'message': '', 'at': '2026-11-08T10:00:00+02:00', 'summary': {'booked': 2, 'queued': 3}}
        p.wait_for_function('document.body.innerText.includes("unsaved changes in this tab")')
        self.assertFalse(p.evaluate("!!window.__reloaded"))
        # Clean tab: the saved result is loaded.
        p.evaluate("dirty=false; bankFetch.status={state:'comparing',message:'',at:null}; bankFetchPoll()")
        p.wait_for_function('window.__reloaded === true')
        self.assertIn('2 booked automatically, 3 waiting', p.locator('#bankFetchStatus').inner_text())
        self.assertFalse(p.locator('#bankFetchBtn').is_disabled(), 'free to start another run once it is done')
        self.assertEqual(box['posts'], 2)

    def test_available_balance_is_shown_and_survives_a_compare(self):
        """The bank's available balance (statement figure less card holds) comes from the downloader, is shown next to the ledger balance and kept across runs."""
        p = self.page
        p.evaluate("""() => {
          data=emptyData();
          data.accounts=[{id:'eb',name:'Bank',type:'checking',openingBalance:1000,includeInNetWorth:true}];
          data.envelopes=[{id:'e0',name:'Groceries',budgetAmount:0,cadence:'monthly',rolloverPolicy:'rollover'}];
          data.transactions=[['2024-01-04',41],['2024-01-18',55],['2024-02-02',47],['2024-02-16',36],['2024-03-01',20]]
            .map((x,i)=>({id:'h'+i,date:x[0],type:'expense',amount:x[1],accountId:'eb',envelopeId:'e0',payee:'Corner Market',notes:''}));
          activeView='reconcile';render();undoStack.length=0;redoStack.length=0;
        }""")
        # Handed over BEFORE the account is tracked: kept for the next Compare.
        self.assertTrue(p.evaluate("bankSetAvailable('eb', 3902.30, 332.41)"))
        self.assertFalse(p.evaluate("bankSetAvailable('nope', 1, 0)"))
        self.assertFalse(p.evaluate("bankSetAvailable('eb', NaN, 0)"))
        self.assertIsNone(p.evaluate("data.accounts[0].bank || null"))
        csv = "Date,Description,Amount,Balance\n2024-03-01,CORNER MARKET 12,-20.00,801.00\n2024-03-06,DENTIST CLINIC,-120.00,681.00\n"
        p.evaluate("bankImportStart('eb')")
        p.locator('#bk_file').set_input_files({'name': 's.csv', 'mimeType': 'text/csv', 'buffer': csv.encode()})
        p.wait_for_function('document.getElementById("bk_bal") && document.getElementById("bk_bal").value==="681.00"')
        p.locator('#bk_go').click()
        p.wait_for_function('activeView==="reconcile" && !document.getElementById("modalBg").classList.contains("open")')
        self.assertEqual(p.evaluate("(()=>{const a=data.accounts[0].bank.available;return [a.amount,a.holds,typeof a.at]})()"), [3902.3, 332.41, 'string'])
        text = p.locator('#main').inner_text()
        self.assertRegex(text, r'available 3[.,]?902[.,]30')      # 3.902,30 in a Greek browser, 3,902.30 in an English one
        self.assertRegex(text, r'332[.,]41\W{0,3}on hold')        # the currency sign sits between the amount and the words
        # Already tracked: recorded at once, and a later Compare keeps it.
        self.assertTrue(p.evaluate("bankSetAvailable('eb', 3800, 100)"))
        self.assertEqual(p.evaluate("data.accounts[0].bank.available.amount"), 3800)
        p.evaluate("bankImportStart('eb')")
        p.locator('#bk_file').set_input_files({'name': 's.csv', 'mimeType': 'text/csv', 'buffer': csv.encode()})
        p.wait_for_function('document.getElementById("bk_bal") && document.getElementById("bk_bal").value==="681.00"')
        p.locator('#bk_go').click()
        p.wait_for_function('activeView==="reconcile" && !document.getElementById("modalBg").classList.contains("open")')
        self.assertEqual(p.evaluate("data.accounts[0].bank.available.amount"), 3800, 'a Compare without a fresh figure keeps the last one')

    def test_lines_dated_tomorrow_are_booked_today(self):
        """The bank dates weekend card payments to its next working day; the app books them today, never in the future."""
        p = self.page
        today, tomorrow = p.evaluate("[todayISO(), isoDate(addDays(new Date(), 1))]")
        p.evaluate("""() => {
          data=emptyData();
          data.accounts=[{id:'eb',name:'Bank',type:'checking',openingBalance:1000,includeInNetWorth:true}];
          data.envelopes=[{id:'e0',name:'Groceries',budgetAmount:0,cadence:'monthly',rolloverPolicy:'rollover'}];
          data.transactions=[['2024-01-04',41],['2024-01-18',55],['2024-02-02',47],['2024-02-16',36]]
            .map((x,i)=>({id:'h'+i,date:x[0],type:'expense',amount:x[1],accountId:'eb',envelopeId:'e0',payee:'Corner Market',notes:''}));
          activeView='reconcile';render();undoStack.length=0;redoStack.length=0;
        }""")
        # 1000 - 179 history = 821; the bank has two more lines, both dated tomorrow.
        csv = (f"Date,Description,Amount,Balance\n{today},OPENING,0.01,821.01\n{today},OPENING BACK,-0.01,821.00\n"
               f"{tomorrow},CORNER MARKET 12,-30.00,791.00\n{tomorrow},DENTIST CLINIC,-120.00,671.00\n")
        p.evaluate("bankImportStart('eb')")
        p.locator('#bk_file').set_input_files({'name': 's.csv', 'mimeType': 'text/csv', 'buffer': csv.encode()})
        p.wait_for_function('document.getElementById("bk_bal") && document.getElementById("bk_bal").value==="671.00"')
        p.locator('#bk_from').fill(today); p.locator('#bk_from').dispatch_event('change')
        p.wait_for_function(f'document.getElementById("bk_from").value === "{today}"')
        p.locator('#bk_go').click()
        p.wait_for_function('activeView==="reconcile" && !document.getElementById("modalBg").classList.contains("open")')
        auto = p.evaluate("data.transactions.filter(t=>t.bankAuto).map(t=>[t.payee,t.date,t.notes])")
        self.assertEqual(auto, [['Corner Market', today, f'Added from the bank statement (bank date {tomorrow})']])
        # The queued line keeps the bank's date; both ways of booking it use today.
        self.assertEqual(p.evaluate("data.bankQueue.filter(q=>q.desc==='DENTIST CLINIC').map(q=>q.date)"), [tomorrow])
        p.locator('[data-bank-resolve]').first.click()
        p.wait_for_function('document.getElementById("modalBg").classList.contains("open")')
        self.assertEqual(p.locator('#t_date').input_value(), today)
        p.evaluate("closeModal()")
        p.evaluate("bankUseGuess(data.bankQueue.find(q=>q.desc==='DENTIST CLINIC').id)")
        self.assertEqual(p.evaluate("data.transactions.filter(t=>t.bankDesc==='DENTIST CLINIC').map(t=>t.date)"), [today])
        self.assertEqual(p.evaluate(f"data.transactions.filter(t=>t.date>'{today}').length"), 0, 'nothing from the bank lands in the future')

    def test_held_card_payments_are_pending_until_settled(self):
        """Decision #78: held payments become pending entries (app follows the available balance), settle on their statement line, and released ones are flagged."""
        p = self.page
        today = p.evaluate("todayISO()")
        p.evaluate("""() => {
          data=emptyData();
          data.accounts=[{id:'eb',name:'Bank',type:'checking',openingBalance:1000,includeInNetWorth:true}];
          data.envelopes=[{id:'e0',name:'Groceries',budgetAmount:0,cadence:'monthly',rolloverPolicy:'rollover'}];
          data.transactions=[['2024-01-04',41],['2024-01-18',55],['2024-02-02',47],['2024-02-16',36]]
            .map((x,i)=>({id:'h'+i,date:x[0],type:'expense',amount:x[1],accountId:'eb',envelopeId:'e0',payee:'Corner Market',notes:''}));
          activeView='reconcile';render();undoStack.length=0;redoStack.length=0;
        }""")
        # The statement agrees with the app (821); two card payments are held on top: the bank's available is 821 - 42 = 779.
        csv = f"Date,Description,Amount,Balance\n{today},OPENING,0.01,821.01\n{today},OPENING BACK,-0.01,821.00\n"
        def check(csv_text, holds, available):
            p.evaluate(f"bankSetHolds('eb', {holds}); bankSetAvailable('eb', {available}, {821 - available})")
            p.evaluate("bankImportStart('eb')")
            p.locator('#bk_file').set_input_files({'name': 's.csv', 'mimeType': 'text/csv', 'buffer': csv_text.encode()})
            p.wait_for_function('document.getElementById("bk_bal") && document.getElementById("bk_bal").value !== ""')
            p.locator('#bk_go').click()
            p.wait_for_function('activeView==="reconcile" && !document.getElementById("modalBg").classList.contains("open")')
        holds1 = f"[{{date:'{today}',amount:-30,desc:'CORNER MARKET 12'}},{{date:'{today}',amount:-12,desc:'NEW KIOSK'}}]"
        check(csv, holds1, 779)
        self.assertEqual(p.evaluate("data.transactions.filter(t=>t.bankPending).map(t=>[t.payee,t.amount,!!t.bankHoldRef,!!t.bankRef])"),
                         [['Corner Market', 30, True, False]], 'the known one is booked as pending')
        self.assertEqual(p.evaluate("data.bankQueue.filter(q=>q.status==='open').map(q=>[q.desc,!!q.hold])"), [['NEW KIOSK', True]])
        self.assertTrue(p.evaluate("bankStatus(data.accounts[0]).ok"), 'pending entries stay out of the statement comparison')
        # Decide the kiosk by hand: it is booked as pending too, and the app now equals the available balance.
        p.evaluate("bankUseGuess(data.bankQueue.find(q=>q.desc==='NEW KIOSK').id)") if p.evaluate("!!(data.bankQueue.find(q=>q.desc==='NEW KIOSK').sug||{}).payee") else p.evaluate("""() => {
          const q=data.bankQueue.find(q=>q.desc==='NEW KIOSK'); bankResolve(q.id); }""")
        if p.evaluate("document.getElementById('modalBg').classList.contains('open')"):
            p.locator('#t_save').click()
        self.assertEqual(p.evaluate("data.transactions.filter(t=>t.bankPending).length"), 2)
        self.assertEqual(p.evaluate("bankStatus(data.accounts[0]).availDiff"), 0, 'the app today equals the bank\'s available balance')
        self.assertIn('same', p.locator('#main').inner_text())
        # Next run: the Corner Market payment settles (statement line), the kiosk hold disappears without a line.
        csv2 = csv + f"{today},CORNER MARKET 12,-30.00,791.00\n"
        check(csv2, "[]", 791)
        settled = p.evaluate("data.transactions.find(t=>t.payee==='Corner Market'&&t.amount===30)")
        self.assertTrue(settled.get('bankRef') and not settled.get('bankPending'), 'settled: an ordinary statement entry now')
        self.assertTrue(p.evaluate("bankStatus(data.accounts[0]).ok"))
        self.assertEqual(p.evaluate("data.transactions.filter(t=>t.bankHoldGone).length"), 1, 'the kiosk hold is flagged, not deleted')
        self.assertIn('no longer shows', p.locator('#main').inner_text())
        p.locator('[data-bank-hold-delete]').click()
        self.assertEqual(p.evaluate("data.transactions.filter(t=>t.bankPending).length"), 0)
        p.evaluate("performUndo()")
        p.locator('[data-bank-hold-keep]').click()
        self.assertEqual(p.evaluate("data.transactions.filter(t=>t.bankHoldGone||t.bankPending).length"), 0, 'kept: an ordinary entry')

    def test_two_bank_files_make_one_app_account(self):
        """Decision #75: an app account that is the sum of two bank accounts takes two files, adds their balances, drops moves between them."""
        p = self.page
        p.evaluate("""() => {
          data=emptyData();
          data.accounts=[{id:'eb',name:'Bank',type:'checking',openingBalance:1000,includeInNetWorth:true}];
          data.envelopes=[{id:'e0',name:'Groceries',budgetAmount:0,cadence:'monthly',rolloverPolicy:'rollover'}];
          data.transactions=[['2024-01-04',41],['2024-01-18',55],['2024-02-02',47],['2024-02-16',36],['2024-03-01',20]]
            .map((x,i)=>({id:'h'+i,date:x[0],type:'expense',amount:x[1],accountId:'eb',envelopeId:'e0',payee:'Corner Market',notes:''}));
          activeView='reconcile';render();undoStack.length=0;redoStack.length=0;
        }""")
        main_csv = ("Date,Description,Amount,Balance\n2024-03-01,CORNER MARKET 12,-20.00,801.00\n"
                    "2024-03-04,CORNER MARKET 12,-30.00,771.00\n2024-03-05,TRANSFER TO SAVINGS,-100.00,671.00\n")
        second_csv = "Date,Description,Amount,Balance\n2024-03-05,FROM MAIN,100.00,100.00\n2024-03-06,DENTIST CLINIC,-40.00,60.00\n"
        p.evaluate("bankImportStart('eb')")
        p.locator('#bk_file').set_input_files([
            {'name': 'main.csv', 'mimeType': 'text/csv', 'buffer': main_csv.encode()},
            {'name': 'second.csv', 'mimeType': 'text/csv', 'buffer': second_csv.encode()}])
        p.wait_for_function('document.getElementById("bk_bal") && document.getElementById("bk_bal").value==="731.00"')
        self.assertEqual(p.locator('#bk_asof').input_value(), '2024-03-06')
        self.assertEqual(p.locator('.bank-src').count(), 2)
        self.assertIn('1 move between these accounts', p.locator('.modal').inner_text())
        self.assertTrue(p.locator('#bk_internal').is_checked())
        # Adding the same file again must not double its lines.
        p.locator('#bk_file').set_input_files({'name': 'main.csv', 'mimeType': 'text/csv', 'buffer': main_csv.encode()})
        p.wait_for_timeout(300)
        self.assertEqual(p.locator('.bank-src').count(), 2)
        p.locator('#bk_go').click()
        p.wait_for_function('activeView==="reconcile" && !document.getElementById("modalBg").classList.contains("open")')
        self.assertEqual(p.evaluate("data.transactions.filter(t=>t.bankAuto).map(t=>[t.amount,t.payee])"), [[30, 'Corner Market']])
        self.assertEqual(p.evaluate("data.bankQueue.map(q=>[q.amount,q.desc])"), [[-40, 'DENTIST CLINIC']])
        self.assertEqual(p.evaluate("data.accounts[0].bank.lastRun.internalCount"), 1)
        self.assertEqual(p.evaluate("bankStatus(data.accounts[0]).diff"), -40)

    def test_statement_helper_link_shows_a_button_only_for_a_custom_scheme(self):
        """Decision #76: Settings -> Statement helper link; the Reconcile page offers the button only for a custom scheme."""
        p = self.page
        p.evaluate("activeView='reconcile';render()")
        self.assertEqual(p.locator('#bankFetchBtn').count(), 0)
        p.evaluate("activeView='settings';render()")
        field = p.locator('#s_stlink')
        field.fill('https://example.com/'); field.dispatch_event('change')
        self.assertEqual(p.evaluate("data.settings.statementLink"), None, 'a web address is refused')
        field = p.locator('#s_stlink')
        field.fill('statement-fetch:'); field.dispatch_event('change')
        self.assertEqual(p.evaluate("data.settings.statementLink"), 'statement-fetch:')
        p.evaluate("activeView='reconcile';render()")
        self.assertEqual(p.locator('#bankFetchBtn').count(), 1)
        # A real link (the browser hands it to the operating system); a quote in the setting cannot break out of the attribute.
        self.assertEqual(p.locator('#bankFetchBtn').evaluate("e => [e.tagName, e.getAttribute('href')]"), ['A', 'statement-fetch:'])

    def test_scenarios_compare_apply_and_undo(self):
        p=self.page
        nxt="monthKeyAdd(monthKeyOf(todayISO()),1)"
        p.evaluate("forecastState.accountIds=['a'];activeView='scenarios';render()")
        p.locator('[data-sc-act="new"]').first.click()
        p.locator('[data-sc-act="add-env"]').click()
        p.locator('[data-sc-act="add-rec"]').click()
        p.evaluate(f"data.scenarios[0].recSkips[0].from={nxt};render()")
        table=p.locator('#main table').first.inner_text()
        self.assertIn('Scenario 1',table);self.assertIn('low vs plan',table.lower())
        self.assertEqual(p.locator('#scChart').count(),1)
        # A pause of the envelope's month plus a skipped bill can only raise the low.
        p.locator('[data-sc-f="pause"]').check()
        self.assertGreater(p.evaluate("(()=>{const s=scenarioResults();return s.each.get(data.scenarios[0].id).lo.min-s.baseline.lo.min})()"),0)
        # Apply lists the change, writes it, and one Undo takes it back.
        undo=p.evaluate('undoStack.length')
        p.locator('[data-sc-act="apply"]').click()
        p.wait_for_function('document.getElementById("modalBg").classList.contains("open")')
        self.assertIn('pause its spending',p.locator('.sc-plan').inner_text())
        p.locator('#sc_confirm').click()
        self.assertEqual(p.evaluate(f"data.envelopes[0].skipMonths[{nxt}]"),'all')
        self.assertTrue(p.evaluate("data.recurring[0].skippedDates.length>0"))
        self.assertEqual(p.evaluate('undoStack.length'),undo+1)
        self.assertIn('funding and spending paused',p.locator('#main').inner_text())
        # Fund the month leaves the skipped envelope out for that month.
        p.evaluate(f"closeModal();refillEnvelopes()");
        p.wait_for_function('document.getElementById("modalBg").classList.contains("open")')
        p.locator('#rf_date').fill(p.evaluate(f"{nxt}+'-02'"))
        self.assertEqual(p.locator('[data-rf-amt="e"]').input_value(),'0.00')
        self.assertIn('funding skipped',p.locator('#rf_body').inner_text())
        p.evaluate('closeModal();performUndo()')
        self.assertIsNone(p.evaluate("data.envelopes[0].skipMonths??null"))
        self.assertIsNone(p.evaluate("data.recurring[0].skippedDates??null"))
        # Unapply after a reload-proof apply: apply again, then take back only what it wrote.
        p.evaluate(f"data.envelopes[0].skipMonths={{[{nxt}]:'fund'}};render()")   # a value the scenario will upgrade
        p.locator('[data-sc-act="apply"]').click()
        p.wait_for_function('document.getElementById("modalBg").classList.contains("open")')
        p.locator('#sc_confirm').click()
        self.assertEqual(p.evaluate(f"data.envelopes[0].skipMonths[{nxt}]"),'all')
        p.locator('[data-sc-act="unapply"]').click()
        p.wait_for_function('document.getElementById("modalBg").classList.contains("open")')
        self.assertIn('back to funding skipped',p.locator('.sc-plan').inner_text())
        p.locator('#sc_confirm').click()
        self.assertEqual(p.evaluate(f"data.envelopes[0].skipMonths[{nxt}]"),'fund')   # restored, not deleted
        self.assertIsNone(p.evaluate("data.recurring[0].skippedDates??null"))
        self.assertTrue(p.evaluate("data.scenarios[0].active&&!data.scenarios[0].appliedOn&&!data.scenarios[0].applied"))
        self.assertEqual(p.locator('[data-sc-act="apply"]').count(),1)

    def test_sign_in_proxy_shows_sign_in_not_unreachable(self):
        p=self.page
        for fulfil in ({'status':401,'body':'{}'},
                       {'status':302,'headers':{'Location':'https://sign-in.invalid/login'}}):
            p.unroute('**/data')
            p.route('**/data',(lambda f:lambda route:route.fulfill(**f))(fulfil))
            p.goto(BASE+'/?add=expense');p.wait_for_function('loadState === "signin"')
            self.assertIn('Sign in again',p.locator('#main').inner_text())
            self.assertFalse(p.evaluate('document.getElementById("modalBg").classList.contains("open")'))


if __name__ == '__main__':
    unittest.main(verbosity=2)
