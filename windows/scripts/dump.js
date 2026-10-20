'use strict';
// Electron olmadan çalıştırıp çıktıyı kontrol etmek için: node scripts/dump.js [depo-klasörü]
const os = require('os');
const path = require('path');
const { Store } = require('../src/main/store');
const { refreshAll } = require('../src/main/sources');

(async () => {
  const dir = process.argv[2] || path.join(os.tmpdir(), 'ullage-dump');
  const store = new Store(dir);
  const t0 = Date.now();
  const r = await refreshAll(store);
  const f = (v) => (v == null ? '-' : v.toFixed(3));
  for (const [p, u] of Object.entries(r.usage)) {
    console.log(`== ${p} limit:${u.limitConfidence} token:${u.tokenConfidence}`);
    const w = u.win;
    if (w.five) console.log(`  5s left=${f(w.five.left)} reset=${w.five.reset ? new Date(w.five.reset).toISOString() : '-'}`);
    if (w.week) console.log(`  hf left=${f(w.week.left)} reset=${w.week.reset ? new Date(w.week.reset).toISOString() : '-'}`);
    for (const r2 of u.extra || []) console.log(`  row ${r2.title} left=${f(r2.left)}`);
    console.log(`  today: ${u.todayTokens ?? '-'}`);
    for (const n of u.notes) console.log(`  - ${n}`);
  }
  let total = { claude: 0, codex: 0, antigravity: 0 };
  for (const p of Object.keys(total)) total[p] = store.billableSince(p, 0);
  console.log('toplam (cache hariç):', JSON.stringify(total), 'olay sayısı:', Object.keys(store.data.events).length, 'süre ms:', Date.now() - t0);
  store.save(true);
})();
