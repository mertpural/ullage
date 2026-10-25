'use strict';
// Küçük birim testleri: node scripts/test.js
const assert = require('assert');
const os = require('os');
const path = require('path');
const fs = require('fs');
const { pbFields, parseQuota } = require('../src/main/providers/antigravity');
const { Store, dayKey } = require('../src/main/store');
const { windows } = require('../src/main/sources');
const { loginState } = require('../src/main/providers/claude');

// protobuf: alan 1 = varint 150, alan 2 = "hi"
const f = pbFields(Buffer.from([0x08, 0x96, 0x01, 0x12, 0x02, 0x68, 0x69]));
assert.strictEqual(f[0][0], 1); assert.strictEqual(f[0][2], 150);
assert.strictEqual(f[1][0], 2); assert.strictEqual(Buffer.from(f[1][2]).toString(), 'hi');

// Antigravity kota yanıtı
const rows = parseQuota({ response: { groups: [{ displayName: 'Gemini Models', buckets: [
  { window: 'weekly', bucketId: 'gemini-weekly', remainingFraction: 0.9, resetTime: '2026-10-23T22:41:14Z' },
  { window: '5h', bucketId: 'gemini-5h', remainingFraction: 1 }] }] } });
assert.strictEqual(rows.length, 2); assert.strictEqual(rows[0].title, 'Gemini · Haftalık'); assert.strictEqual(rows[1].title, 'Gemini · 5 saatlik');

// 5 saatlik / haftalık seçimi (havuzlu sağlayıcıda en kısıtlayıcı)
const w = windows({ extra: [{ title: 'A · 5 saatlik', left: 0.8 }, { title: 'B · 5 saatlik', left: 0.3 }, { title: 'A · Haftalık', left: 0.5 }] });
assert.strictEqual(w.five.left, 0.3); assert.strictEqual(w.week.left, 0.5);

// depo: tekrar eleme (en büyük değer) ve günlük toplam
const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'ullage-test-'));
const st = new Store(dir);
const now = Date.now();
st.upsert('claude', 'm1|r1', now, 'x', 10, 5, 0, 100);
st.upsert('claude', 'm1|r1', now, 'x', 10, 20, 0, 100); // aynı mesaj, büyüyen çıktı
st.upsert('claude', 'm2|r2', now - 86400000, 'x', 1, 1, 1, 0);
assert.strictEqual(st.billableSince('claude', 0), 10 + 20 + 3);
assert.deepStrictEqual(st.dailyTotals('claude', 2), [3, 30]);
assert.strictEqual(dayKey(new Date(2026, 0, 5).getTime()), '2026-01-05');
const agg = st.aggregate();
assert.ok(agg.daily.length >= 1);
assert.strictEqual(st.cacheReadSince('claude', 0), 100); // aynı mesajın tekrarı elenmiş, tek 100 sayılır

// Claude giriş durumu: dört durum ayrı ayrı tanınmalı
const future = Date.now() + 3600e3, past = Date.now() - 3600e3;
assert.strictEqual(loginState(undefined), 'no-file');
assert.strictEqual(loginState({ mcpOAuth: {} }), 'signed-out');           // yalnızca MCP girişi var
assert.strictEqual(loginState({ claudeAiOauth: { accessToken: 't', expiresAt: past } }), 'expired');
assert.strictEqual(loginState({ claudeAiOauth: { accessToken: 't', expiresAt: future } }), 'ok');
assert.strictEqual(loginState({ claudeAiOauth: { accessToken: 't' } }), 'ok'); // süre alanı yoksa süresiz say

// Ayarlar dosyası BOM'lu da okunmalı
const { Settings } = require('../src/main/settings');
const sdir = fs.mkdtempSync(path.join(os.tmpdir(), 'ullage-settings-'));
fs.writeFileSync(path.join(sdir, 'settings.json'), '﻿{"widget":true}');
assert.strictEqual(new Settings(sdir).v.widget, true);

// ---- Claude Code komutuyla ölçüm: çıktı ayrıştırma
const cliprobe = require('../src/main/cliprobe');
const rlEvent = '{"type":"rate_limit_event","rate_limit_info":{"status":"allowed","resetsAt":1792936800,"rateLimitType":"five_hour","unifiedWindows":{"five_hour":{"utilization":0.69,"resetsAt":1792936800,"status":"allowed"},"seven_day":{"utilization":0.26,"resetsAt":1793188800,"status":"allowed"}}}}';
const probed = cliprobe.parseOutput('{"type":"system","subtype":"init"}\r\n' + rlEvent + '\r\n{"type":"result","subtype":"success"}\r\n'); // CRLF
assert.ok(probed.seen);
assert.ok(Math.abs(probed.limits.five - 0.31) < 1e-9 && Math.abs(probed.limits.week - 0.74) < 1e-9); // kalan = 1 - utilization
assert.strictEqual(probed.limits.fiveReset, 1792936800000); assert.strictEqual(probed.limits.weekReset, 1793188800000); // saniye -> ms
assert.strictEqual(probed.limits.src, 'probe');
// Eski Claude Code: olay var ama yüzde yok (gerçek 2.1.218 çıktısı böyleydi)
const oldCli = cliprobe.parseOutput('{"type":"rate_limit_event","rate_limit_info":{"status":"allowed","resetsAt":1792936800,"rateLimitType":"five_hour","overageStatus":"rejected"}}\n');
assert.ok(oldCli.seen); assert.strictEqual(oldCli.limits, null);
assert.deepStrictEqual(cliprobe.parseOutput('düz yazı\n{bozuk json rate_limit_event'), { seen: false, limits: null });

// ---- Claude Code durum satırı: ayrıştırma, kurulum, kaldırma
const statusline = require('../src/main/statusline');
const sl = statusline.parseStatus({ rate_limits: { five_hour: { used_percentage: 34, resets_at: 1792936800 }, seven_day: { used_percentage: 22.5, resets_at: '2026-10-28T11:59:59.765Z' } } }, 1000);
assert.ok(Math.abs(sl.five - 0.66) < 1e-9 && Math.abs(sl.week - 0.775) < 1e-9);
assert.strictEqual(sl.fiveReset, 1792936800000); assert.strictEqual(sl.weekReset, Date.parse('2026-10-28T11:59:59.765Z')); assert.strictEqual(sl.at, 1000);
assert.strictEqual(statusline.parseStatus({ cwd: 'x' }, 1), null);
const tmpRoot = fs.mkdtempSync(path.join(os.tmpdir(), 'ullage-sl-'));
const slDir = path.join(tmpRoot, 'Ullage test'); // yolda boşluk
const slSettings = path.join(tmpRoot, 'claude', 'settings.json');
fs.mkdirSync(path.dirname(slSettings), { recursive: true });
fs.writeFileSync(slSettings, '{"theme":"dark"}');
assert.strictEqual(statusline.install(slDir, slSettings), null);
const afterInstall = JSON.parse(fs.readFileSync(slSettings, 'utf8'));
assert.strictEqual(afterInstall.theme, 'dark');
assert.strictEqual(afterInstall.statusLine.type, 'command'); assert.strictEqual(afterInstall.statusLine.padding, 0);
assert.ok(afterInstall.statusLine.command.includes('"' + slDir.replace(/\\/g, '/') + '/statusline.ps1"')); // tırnaklı, düz eğik çizgili yol
assert.strictEqual(fs.readFileSync(slSettings + '.ullage-yedek', 'utf8'), '{"theme":"dark"}'); // yedek özgün hâl
assert.ok(fs.existsSync(path.join(slDir, 'statusline.ps1')));
assert.ok(statusline.state(slDir, slSettings).installed);
statusline.uninstall(slDir, slSettings);
assert.deepStrictEqual(JSON.parse(fs.readFileSync(slSettings, 'utf8')), { theme: 'dark' }); // yalnızca bizimki kalktı
// başka bir durum satırı varsa dokunulmaz
fs.writeFileSync(slSettings, '{"statusLine":{"type":"command","command":"baska.cmd"}}');
assert.ok(statusline.install(slDir, slSettings).includes('Başka bir durum satırı'));
assert.ok(statusline.state(slDir, slSettings).other);
statusline.uninstall(slDir, slSettings);
assert.strictEqual(JSON.parse(fs.readFileSync(slSettings, 'utf8')).statusLine.command, 'baska.cmd');

// ---- claude komutunu bulma: PATH'te yoksa Claude Desktop'ın kendi claude.exe'si
const claudebin = require('../src/main/claudebin');
const cbRoot = fs.mkdtempSync(path.join(os.tmpdir(), 'ullage-bin-'));
const mk = (...p) => { const f = path.join(cbRoot, ...p); fs.mkdirSync(path.dirname(f), { recursive: true }); fs.writeFileSync(f, ''); return f; };
assert.ok(claudebin.cmpVersion('2.1.10', '2.1.5') > 0 && claudebin.cmpVersion('2.1.5', '2.1.10') < 0 && claudebin.cmpVersion('2.1', '2.1.0') === 0); // sayısal, metin sırası değil
const noPath = { PATH: path.join(cbRoot, 'bos'), PATHEXT: '.EXE;.CMD' };
assert.strictEqual(claudebin.resolve({ ...noPath, APPDATA: path.join(cbRoot, 'a'), LOCALAPPDATA: path.join(cbRoot, 'l') }), null); // hiçbir yerde yok
// Mağaza (MSIX) yolu: %LOCALAPPDATA%\Claude-Data\<paket>\claude-code\<sürüm>\<karma>\claude.exe, en yüksek sürüm seçilir
mk('l', 'Claude-Data', 'claude_pkg', 'claude-code', '2.1.5', 'aaa', 'claude.exe');
const newest = mk('l', 'Claude-Data', 'claude_pkg', 'claude-code', '2.1.10', 'bbb', 'claude.exe');
assert.strictEqual(claudebin.desktopBundled({ ...noPath, LOCALAPPDATA: path.join(cbRoot, 'l') }), newest);
// Klasik yol: %APPDATA%\Claude\claude-code\<sürüm>\claude.exe
const roaming = mk('r', 'Claude', 'claude-code', '2.1.99', 'claude.exe');
assert.strictEqual(claudebin.desktopBundled({ ...noPath, APPDATA: path.join(cbRoot, 'r', 'Claude', '..') , LOCALAPPDATA: path.join(cbRoot, 'yok') }), roaming);
const found = claudebin.resolve({ ...noPath, LOCALAPPDATA: path.join(cbRoot, 'l') });
assert.strictEqual(found.kind, 'desktop'); assert.strictEqual(found.file, newest); assert.strictEqual(found.shell, false);
// PATH'te claude varsa o tercih edilir
mk('bin', 'claude.cmd');
assert.strictEqual(claudebin.resolve({ PATH: path.join(cbRoot, 'bin'), PATHEXT: '.EXE;.CMD', LOCALAPPDATA: path.join(cbRoot, 'l') }).kind, 'path');
// komut satırı: kabukta boş değer ve boşluklu argüman tırnaklı, doğrudan çalıştırmada dizi olarak
assert.strictEqual(claudebin.spec({ file: 'claude', shell: true }, ['-p', '.', '--tools', '', 'a b'])[0], 'claude -p "." --tools "" "a b"');
assert.deepStrictEqual(claudebin.spec({ file: 'C:\\x y\\claude.exe', shell: false }, ['-p', ''])[1], ['-p', '']);

// ---- ölçüm koşulları (maybeProbe): yalnızca yeni kullanım varsa, en sık 5 dakikada bir
const claudeMod = require('../src/main/providers/claude');
const pst = new Store(fs.mkdtempSync(path.join(os.tmpdir(), 'ullage-probe-')));
let probeCalls = 0;
cliprobe.measure = async () => { probeCalls++; return { seen: true, limits: { five: 0.5, week: 0.8, fiveReset: 1, weekReset: 2, src: 'probe' } }; };
const T = Date.now(), MIN = 60000;
pst.upsert('claude', 'a|b', T - MIN, 'x', 1, 1, 0, 0); // 1 dk önce yerel kullanım
const staleResult = { ok: true, at: T - 30 * MIN };    // 30 dk önceki değer
(async () => {
  let r = await claudeMod.maybeProbe(pst, staleResult, T);
  assert.ok(r && r.ok && r.src === 'probe' && probeCalls === 1); assert.strictEqual(pst.kv('claudeLast').src, 'probe');
  assert.strictEqual(await claudeMod.maybeProbe(pst, staleResult, T + MIN), null); assert.strictEqual(probeCalls, 1);          // 5 dk dolmadı
  assert.strictEqual(await claudeMod.maybeProbe(pst, staleResult, T + 6 * MIN), null); assert.strictEqual(probeCalls, 1);      // yeni kullanım yok
  pst.upsert('claude', 'c|d', T + 7 * MIN, 'x', 1, 1, 0, 0);
  // Eşik 90 sn: 65 saniyelik değer yeni kullanım olsa da taze sayılır, 100 saniyelik değer aday olur (sıklığı yalnızca 5 dk sınırı belirler)
  const valueAt = T + 7 * MIN - 5000; // c|d olayından 5 sn önceki değer
  assert.strictEqual(await claudeMod.maybeProbe(pst, { ok: true, at: valueAt }, T + 8 * MIN), null); assert.strictEqual(probeCalls, 1);  // 65 sn: taze
  r = await claudeMod.maybeProbe(pst, { ok: true, at: valueAt }, T + 8 * MIN + 35000); assert.ok(r && probeCalls === 2);                 // 100 sn: eski + yeni kullanım + 5 dk geçti
  // Durum satırı dosyasından gelen değer için eşik 15 dk
  pst.upsert('claude', 'm|n', T + 13 * MIN, 'x', 1, 1, 0, 0); // son ölçümden sonra yeni kullanım
  assert.strictEqual(await claudeMod.maybeProbe(pst, { ok: true, at: T + 4 * MIN, src: 'statusline' }, T + 14 * MIN), null); assert.strictEqual(probeCalls, 2); // 10 dk
  r = await claudeMod.maybeProbe(pst, { ok: true, at: T - 6 * MIN, src: 'statusline' }, T + 14 * MIN); assert.ok(r && probeCalls === 3);                       // 20 dk
  // Sonuç yok + yeni kullanım
  pst.upsert('claude', 'e|f', T + 19 * MIN, 'x', 1, 1, 0, 0);
  r = await claudeMod.maybeProbe(pst, { ok: false, error: 'x' }, T + 20 * MIN); assert.ok(r && probeCalls === 4);
  // Hız sınırı beklemesi: değer 31 sn önce olsa da ölçülür (değerden sonra yeni kullanım var)
  pst.kv('claudeBackoffUntil', T + 100 * MIN); pst.upsert('claude', 'g|h', T + 25 * MIN, 'x', 1, 1, 0, 0);
  r = await claudeMod.maybeProbe(pst, { ok: true, at: T + 25 * MIN - 30000 }, T + 25 * MIN + 1000); assert.ok(r && probeCalls === 5);
  // komut yüzde vermiyorsa (eski Claude Code) bir saat denenmez
  cliprobe.measure = async () => { probeCalls++; return { seen: true, limits: null }; };
  pst.upsert('claude', 'i|j', T + 31 * MIN, 'x', 1, 1, 0, 0);
  assert.strictEqual(await claudeMod.maybeProbe(pst, { ok: false }, T + 32 * MIN), null); assert.strictEqual(probeCalls, 6);
  pst.upsert('claude', 'k|l', T + 40 * MIN, 'x', 1, 1, 0, 0);
  assert.strictEqual(await claudeMod.maybeProbe(pst, { ok: false }, T + 45 * MIN), null); assert.strictEqual(probeCalls, 6);      // engelli
  console.log('tüm testler geçti');
})().catch((e) => { console.error(e); process.exit(1); });
