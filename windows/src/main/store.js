'use strict';
// Geçmiş deposu: token olayları ve okuma konumları tek bir JSON dosyasında tutulur.
// Log dosyaları silinse bile geçmiş burada kalır.
const fs = require('fs');
const path = require('path');

function dayKey(ms) {
  const d = new Date(ms);
  const p = (n) => String(n).padStart(2, '0');
  return `${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())}`;
}

class Store {
  constructor(dir) {
    fs.mkdirSync(dir, { recursive: true });
    this.file = path.join(dir, 'history.json');
    this.data = { events: {}, offsets: {}, mtimes: {}, totals: {}, kv: {} };
    try { Object.assign(this.data, JSON.parse(fs.readFileSync(this.file, 'utf8'))); } catch { /* yeni depo */ }
    this.timer = null;
  }

  // ---- kalıcılık
  save(now = false) {
    clearTimeout(this.timer);
    const write = () => {
      const tmp = this.file + '.tmp';
      fs.writeFileSync(tmp, JSON.stringify(this.data));
      fs.renameSync(tmp, this.file);
    };
    if (now) write(); else this.timer = setTimeout(write, 1500);
  }

  kv(key, value) {
    if (value === undefined) return this.data.kv[key];
    this.data.kv[key] = value;
    this.save();
    return value;
  }

  // ---- olaylar
  /** Akış sırasında aynı mesaj birkaç kez yazıldığı için en büyük değerler tutulur. */
  upsert(provider, key, ts, model, input, output, cacheWrite, cacheRead) {
    const k = `${provider}|${key}`;
    const cur = this.data.events[k];
    if (cur) {
      cur[2] = Math.max(cur[2], input); cur[3] = Math.max(cur[3], output);
      cur[4] = Math.max(cur[4], cacheWrite); cur[5] = Math.max(cur[5], cacheRead);
    } else {
      this.data.events[k] = [ts, model, input, output, cacheWrite, cacheRead];
    }
  }

  offset(p) { return this.data.offsets[p] || 0; }
  setOffset(p, v) { this.data.offsets[p] = v; }
  fileTotal(p) { return this.data.totals[p]; }
  setFileTotal(p, v) { this.data.totals[p] = v; }
  mtime(p) { return this.data.mtimes[p]; }
  setMtime(p, v) { this.data.mtimes[p] = v; }

  resetProvider(provider, pathPart) {
    for (const k of Object.keys(this.data.events)) if (k.startsWith(provider + '|')) delete this.data.events[k];
    for (const m of ['offsets', 'totals', 'mtimes']) {
      for (const k of Object.keys(this.data[m])) if (k.includes(pathPart)) delete this.data[m][k];
    }
  }

  // ---- sorgular (cache okumaları hariç: "harcanan token" = girdi + çıktı + cache yazma)
  *eventsOf(provider) {
    const pre = provider + '|';
    for (const [k, v] of Object.entries(this.data.events)) if (k.startsWith(pre)) yield v;
  }

  billableSince(provider, sinceMs) {
    let t = 0;
    for (const e of this.eventsOf(provider)) if (e[0] >= sinceMs) t += e[2] + e[3] + e[4];
    return t;
  }

  /** Cache okumaları: harcanan token'a dahil değil, ayrıca gösterilmek için. */
  cacheReadSince(provider, sinceMs) {
    let t = 0;
    for (const e of this.eventsOf(provider)) if (e[0] >= sinceMs) t += e[5];
    return t;
  }

  /** Son `days` günün (bugün dahil) günlük toplamları, eskiden yeniye. */
  dailyTotals(provider, days) {
    const start = new Date(); start.setHours(0, 0, 0, 0); start.setDate(start.getDate() - (days - 1));
    const by = {};
    for (const e of this.eventsOf(provider)) if (e[0] >= start.getTime()) by[dayKey(e[0])] = (by[dayKey(e[0])] || 0) + e[2] + e[3] + e[4];
    return Array.from({ length: days }, (_, i) => {
      const d = new Date(start); d.setDate(d.getDate() + i);
      return by[dayKey(d.getTime())] || 0;
    });
  }

  /** Arayüz için: gün/sağlayıcı/model bazında toplamlar (son 3 yıl) ve saatlik toplamlar (son 48 saat). */
  aggregate() {
    const now = Date.now();
    const since = now - 3 * 365 * 86400000;
    const daily = {}; const hourly = {};
    for (const [k, e] of Object.entries(this.data.events)) {
      if (e[0] < since) continue;
      const provider = k.slice(0, k.indexOf('|'));
      const bill = e[2] + e[3] + e[4];
      const all = bill + e[5];
      const dk = `${dayKey(e[0])}|${provider}|${e[1] || '?'}`;
      const d = daily[dk] || (daily[dk] = [0, 0]);
      d[0] += bill; d[1] += all;
      if (e[0] >= now - 48 * 3600000) {
        const dt = new Date(e[0]);
        const hk = `${dayKey(e[0])} ${String(dt.getHours()).padStart(2, '0')}|${provider}|${e[1] || '?'}`;
        const h = hourly[hk] || (hourly[hk] = [0, 0]);
        h[0] += bill; h[1] += all;
      }
    }
    const rows = (o) => Object.entries(o).map(([k, v]) => { const [bucket, provider, model] = k.split('|'); return { bucket, provider, model, tokens: v[0], tokensWithCache: v[1] }; });
    return { daily: rows(daily), hourly: rows(hourly) };
  }
}

module.exports = { Store, dayKey };
