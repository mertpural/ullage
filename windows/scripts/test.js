'use strict';
// Küçük birim testleri: node scripts/test.js
const assert = require('assert');
const os = require('os');
const path = require('path');
const fs = require('fs');
const { pbFields, parseQuota } = require('../src/main/providers/antigravity');
const { Store, dayKey } = require('../src/main/store');
const { windows } = require('../src/main/sources');

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

console.log('tüm testler geçti');
