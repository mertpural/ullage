'use strict';
(function () {
  const { PROVIDERS, THEMES, applyTheme, formatTokens, el } = window.ULL;
  const nav = document.getElementById('nav'), main = document.getElementById('main');
  const PAGES = [['usage', '▮', 'Kullanım'], ['providers', '▦', 'Sağlayıcılar'], ['sync', '↻', 'Senkronizasyon'], ['appearance', '◐', 'Görünüm'], ['automation', '🔔', 'Bildirim ve otomasyon'], ['about', 'ⓘ', 'Hakkında']];
  const TRACKED = ['claude', 'codex', 'antigravity'];
  const colorOf = (id) => (PROVIDERS.find((p) => p.id === id) || {}).color || '#888';
  const nameOf = (id) => (PROVIDERS.find((p) => p.id === id) || {}).name || id;
  let S = null, H = null;
  const ui = { range: '7d', group: 'provider', filter: null, hover: null, get cache() { return !!(S && S.settings.usageCache); } };

  // ---- yardımcılar
  const p2 = (n) => String(n).padStart(2, '0');
  const dk = (d) => `${d.getFullYear()}-${p2(d.getMonth() + 1)}-${p2(d.getDate())}`;
  const fromKey = (k) => { const [y, m, d] = k.split('-').map(Number); return new Date(y, m - 1, d); };
  const sod = (d) => { const x = new Date(d); x.setHours(0, 0, 0, 0); return x; };
  const addDays = (d, n) => { const x = new Date(d); x.setDate(x.getDate() + n); return x; };

  function dayMap() { // gün -> sağlayıcı -> token (cache hariç)
    const m = {};
    for (const r of H.daily) { (m[r.bucket] = m[r.bucket] || {})[r.provider] = ((m[r.bucket] || {})[r.provider] || 0) + (ui.cache ? r.tokensWithCache : r.tokens); }
    return m;
  }
  const dayTotal = (m, key) => { const d = m[key]; if (!d) return 0; return ui.filter ? (d[ui.filter] || 0) : Object.values(d).reduce((a, b) => a + b, 0); };

  function header(page) { main.append(el('h1', null, (PAGES.find((p) => p[0] === page) || [])[2] || '')); }

  // ---- Kullanım
  function usagePage() {
    const m = dayMap(); const today = sod(new Date());
    const sumRange = (from, to) => { let t = 0; for (let d = from; d <= to; d = addDays(d, 1)) { const x = m[dk(d)]; if (x) t += Object.entries(x).filter(([p]) => TRACKED.includes(p)).reduce((a, [, v]) => a + v, 0); } return t; };
    const t0 = sumRange(today, today), y = sumRange(addDays(today, -1), addDays(today, -1));
    const w7 = sumRange(addDays(today, -6), today), pw7 = sumRange(addDays(today, -13), addDays(today, -7)), d30 = sumRange(addDays(today, -29), today);
    const all = Object.keys(m).reduce((a, k) => a + Object.values(m[k]).reduce((x, v) => x + v, 0), 0);
    const cmp = (v, c, label) => (c > 0 ? `<small class="${v >= c ? 'up' : 'down'}">${v >= c ? '↗' : '↘'} ${Math.abs(Math.round((v - c) / c * 100))}% ${label}</small>` : '<small>&nbsp;</small>');
    const stat = (cap, v, extra, cls) => { const c = el('div', 'card stat ' + (cls || ''), `<span class="caps">${cap}</span><b>${v}</b>${extra || ''}`); return c; };
    const r1 = el('div', 'row2');
    r1.append(stat('BUGÜN', formatTokens(t0), cmp(t0, y, 'düne göre'), 'big'), stat('DÜN', formatTokens(y), '<small>&nbsp;</small>', 'big'),
      stat('SON 7 GÜN', formatTokens(w7), cmp(w7, pw7, 'önceki haftaya göre'), 'big'), stat('SON 30 GÜN', formatTokens(d30), '<small>&nbsp;</small>', 'big'));
    main.append(r1);

    // seri hesapları
    const keys = Object.keys(m).filter((k) => dayTotal(m, k) > 0).sort();
    let run = 0, longest = 0, prev = null, best = null;
    for (const k of keys) { const d = fromKey(k); run = prev && Math.round((d - prev) / 86400000) === 1 ? run + 1 : 1; longest = Math.max(longest, run); prev = d; if (!best || dayTotal(m, k) > dayTotal(m, best)) best = k; }
    let cur = 0, d = today; if (!dayTotal(m, dk(d))) d = addDays(d, -1);
    while (dayTotal(m, dk(d)) > 0) { cur++; d = addDays(d, -1); }
    const sum = keys.reduce((a, k) => a + dayTotal(m, k), 0);
    const r2 = el('div', 'row2');
    r2.append(stat('Σ TOPLAM TOKEN', formatTokens(all), '<small>tüm zamanlar</small>'), stat('🔥 GÜNCEL SERİ', cur + ' gün', `<small>${cur ? 'kesintisiz kullanım' : 'bugün kullanım yok'}</small>`),
      stat('🏆 EN UZUN SERİ', longest + ' gün', `<small>${keys.length} aktif gün</small>`),
      stat('⚡ EN YOĞUN GÜN', best ? formatTokens(dayTotal(m, best)) : '0', `<small>${best ? fromKey(best).toLocaleDateString('tr-TR', { day: 'numeric', month: 'short', year: 'numeric' }) : '–'}</small>`),
      stat('GÜNLÜK ORT.', formatTokens(keys.length ? Math.round(sum / keys.length) : 0), '<small>aktif gün başına</small>'));
    main.append(r2);
    main.append(heatmap(m, today));

    // kontroller
    const ctrl = el('div', 'ctrl');
    const seg = (opts, cur2, on) => { const s = el('div', 'seg'); for (const [v, l] of opts) { const b = el('button', v === cur2 ? 'on' : '', l); b.onclick = () => on(v); s.append(b); } return s; };
    ctrl.append(seg([['24h', '24 saat'], ['7d', '7 gün'], ['30d', '30 gün']], ui.range, (v) => { ui.range = v; render(); }),
      seg([['provider', 'Sağlayıcı'], ['model', 'Model']], ui.group, (v) => { ui.group = v; render(); }));
    const cb = el('label', null, `<input type="checkbox" ${ui.cache ? 'checked' : ''}> Cache dahil`); cb.style.cssText = 'margin-left:auto;font-size:12px;cursor:pointer';
    cb.querySelector('input').onchange = (e) => window.ullage.setSettings({ usageCache: e.target.checked }); ctrl.append(cb);
    main.append(ctrl);
    const fl = el('div', 'ctrl'); fl.style.margin = '0 0 10px';
    const pill = (id, label) => { const b = el('button', 'pill' + (ui.filter === id ? ' on' : ''), label); b.onclick = () => { ui.filter = id; render(); }; return b; };
    fl.append(pill(null, 'Hepsi'), ...TRACKED.map((id) => pill(id, nameOf(id)))); main.append(fl);
    chartAndDist();
  }

  function heatmap(m, today) {
    const WEEKS = 53;
    const dow = (today.getDay() + 6) % 7; // Pazartesi = 0
    const start = addDays(today, -dow - 7 * (WEEKS - 1));
    const card = el('div', 'card heat');
    card.append(el('div', 'ov-head', '<b style="font-size:13px">Etkinlik</b><span class="sub" style="font-size:11px;margin-left:8px">Son 53 hafta</span>'));
    const vals = []; for (let w = 0; w < WEEKS; w++) for (let r = 0; r < 7; r++) { const dt = addDays(start, w * 7 + r); if (dt <= today) { const v = dayTotal(m, dk(dt)); if (v > 0) vals.push(v); } }
    vals.sort((a, b) => a - b);
    const th = vals.length ? [0.25, 0.5, 0.75].map((q) => vals[Math.min(vals.length - 1, Math.floor(vals.length * q))]) : [];
    const level = (v) => { if (v <= 0) return 0; for (let i = 0; i < th.length; i++) if (v <= th[i]) return i + 1; return th.length + 1; };
    const opac = [0, 0.5, 0.68, 0.84, 1];
    const months = el('div', 'months'); months.append(el('span')); let last = -1;
    for (let w = 0; w < WEEKS; w++) { const mo = addDays(start, w * 7).getMonth(); const s = el('span', null, mo !== last ? addDays(start, w * 7).toLocaleDateString('tr-TR', { month: 'short' }) : ''); last = mo; months.append(s); }
    card.append(months);
    const grid = el('div', 'grid');
    const labels = ['Pzt', '', 'Çar', '', 'Cum', '', ''];
    // her satır için: etiket + 53 hücre
    for (let r = 0; r < 7; r++) {
      grid.append(el('div', 'lab', labels[r]));
      for (let w = 0; w < WEEKS; w++) {
        const dt = addDays(start, w * 7 + r);
        const c = el('div', 'cell');
        if (dt > today) { c.style.visibility = 'hidden'; grid.append(c); continue; }
        const key = dk(dt), day = m[key] || {}, total = dayTotal(m, key);
        if (total > 0) {
          c.style.opacity = opac[Math.min(level(total), 4)];
          for (const p of PROVIDERS) { const v = ui.filter && ui.filter !== p.id ? 0 : (day[p.id] || 0); if (v > 0) { const s = el('i'); s.style.cssText = `flex:${v};background:${p.color}`; c.append(s); } }
        }
        c.onmouseenter = () => { c.classList.add('hv'); readout.textContent = describe(dt, day, total); };
        c.onmouseleave = () => { c.classList.remove('hv'); readout.textContent = 'Bir günün üzerine gel, o günkü kullanımı gör.'; };
        grid.append(c);
      }
    }
    grid.style.gridTemplateColumns = `26px repeat(${WEEKS}, 1fr)`;
    card.append(grid);
    const foot = el('div', 'foot'); const readout = el('span', null, 'Bir günün üzerine gel, o günkü kullanımı gör.');
    const lg = el('div', 'legend'); for (const id of TRACKED) if (!ui.filter || ui.filter === id) lg.append(el('span', null, `<i style="background:${colorOf(id)}"></i>${nameOf(id)}`));
    foot.append(readout, lg); card.append(foot);
    return card;
  }

  function describe(dt, day, total) {
    const s = dt.toLocaleDateString('tr-TR', { day: 'numeric', month: 'long', year: 'numeric', weekday: 'long' });
    if (!total) return `${s} · kullanım yok`;
    const parts = Object.entries(day).filter(([p]) => !ui.filter || p === ui.filter).sort((a, b) => b[1] - a[1]).map(([p, v]) => `${nameOf(p)} ${formatTokens(v)}`).join(' · ');
    return `${s} · ${formatTokens(total)} token · ${parts}`;
  }

  function chartAndDist() {
    const hourly = ui.range === '24h';
    const rows = (hourly ? H.hourly : H.daily).filter((r) => TRACKED.includes(r.provider) && (!ui.filter || r.provider === ui.filter));
    const now = new Date(); const buckets = [];
    if (hourly) { for (let i = 23; i >= 0; i--) { const d = new Date(now.getTime() - i * 3600000); buckets.push(`${dk(d)} ${p2(d.getHours())}`); } }
    else { const n = ui.range === '7d' ? 7 : 30; for (let i = n - 1; i >= 0; i--) buckets.push(dk(addDays(sod(now), -i))); }
    const label = (r) => (ui.group === 'provider' ? nameOf(r.provider) : (r.model || '?'));
    const val = (r) => (ui.cache ? r.tokensWithCache : r.tokens);
    const byBucket = {}, totals = {};
    for (const r of rows) { if (!buckets.includes(r.bucket)) continue; const l = label(r); (byBucket[r.bucket] = byBucket[r.bucket] || {})[l] = ((byBucket[r.bucket] || {})[l] || 0) + val(r); totals[l] = (totals[l] || 0) + val(r); }
    const names = Object.keys(totals).sort((a, b) => totals[b] - totals[a]);
    const pal = ['#4285f4', '#ff9f0a', '#14b8a6', '#ec4899', '#8b5cf6', '#34d399', '#6366f1', '#a16207', '#06b6d4'];
    const col = (n) => { const p = PROVIDERS.find((x) => x.name === n); return p ? p.color : pal[names.indexOf(n) % pal.length]; };
    const grand = names.reduce((a, n) => a + totals[n], 0);
    const mx = Math.max(1, ...buckets.map((b) => Object.values(byBucket[b] || {}).reduce((a, v) => a + v, 0)));
    const W = 900, Hh = 240, pl = 8, pr = 44, pt = 10, pb = 22, bw = (W - pl - pr) / buckets.length;
    let svg = `<svg viewBox="0 0 ${W} ${Hh}" preserveAspectRatio="none">`;
    for (let i = 0; i <= 2; i++) { const y = pt + (Hh - pt - pb) * (1 - i / 2); svg += `<line x1="${pl}" x2="${W - pr}" y1="${y}" y2="${y}"/><text x="${W - pr + 6}" y="${y + 3}">${formatTokens(Math.round(mx * i / 2))}</text>`; }
    buckets.forEach((b, i) => { let y = Hh - pb; for (const n of names) { const v = (byBucket[b] || {})[n] || 0; if (!v) continue; const h = (Hh - pt - pb) * v / mx; y -= h; svg += `<rect x="${pl + i * bw + bw * 0.12}" y="${y}" width="${bw * 0.76}" height="${h}" rx="2" fill="${col(n)}"/>`; } 
      if (buckets.length <= 8 || i % Math.ceil(buckets.length / 7) === 0) svg += `<text x="${pl + i * bw + bw / 2}" y="${Hh - 6}" text-anchor="middle">${hourly ? b.slice(11) + ':00' : fromKey(b).toLocaleDateString('tr-TR', { day: 'numeric', month: 'short' })}</text>`; });
    svg += '</svg>';
    const c = el('div', 'card chart'); c.style.marginBottom = '12px';
    c.append(el('div', 'ov-head', `<b style="font-size:13px">Token kullanımı</b><span class="grow"></span><span class="sub">${formatTokens(grand)} toplam</span>`));
    if (!grand) c.append(el('div', 'empty', 'Bu aralıkta kayıt yok.')); else c.insertAdjacentHTML('beforeend', svg);
    main.append(c);
    const d = el('div', 'card dist'); d.append(el('b', null, 'Dağılım'));
    for (const n of names) d.append(el('div', 'line', `<span class="dot" style="background:${col(n)}"></span><span class="nm">${n}</span><span class="tr"><i style="width:${totals[n] / grand * 100}%;background:${col(n)}"></i></span><span class="v">${formatTokens(totals[n])}</span><span class="pc">${Math.round(totals[n] / grand * 100)}%</span>`));
    main.append(d);
  }

  // ---- diğer sayfalar
  let SL = null, SLerr = null; // Claude Code durum satırı: { installed, other, ageMin } ve son hata
  const setting = (title, sub, control) => { const r = el('div', 'card setting'); r.append(el('div', 't', `<b>${title}</b><span>${sub || ''}</span>`), control); return r; };
  const toggle = (on, fn) => { const s = el('div', 'switch' + (on ? ' on' : '')); s.onclick = () => fn(!on); return s; };
  const tagHtml = (c) => { const m = { exact: ['Kesin', '#34c759'], estimate: ['Tahmini', '#ff9f0a'], none: ['Veri yok', '#8e8e93'] }[c || 'none']; return `<span class="chip tag" style="color:${m[0] ? m[1] : ''};background:color-mix(in srgb, ${m[1]} 18%, transparent)">${m[0]}</span>`; };

  function providersPage() {
    main.append(el('div', 'sub', 'Menü çubuğunda ve popover\'da görünecek sağlayıcıları seç.'));
    main.lastChild.style.marginBottom = '12px';
    for (const p of PROVIDERS) {
      const u = S.usage[p.id] || { notes: [] };
      const card = el('div', 'card prov');
      const ic = el('span', 'ico'); if (p.id === 'codex') ic.classList.add('mask'); else if (p.id === 'gemini') ic.innerHTML = '<svg viewBox="0 0 24 24"><path d="M12 1C12.6 7 17 11.4 23 12C17 12.6 12.6 17 12 23C11.4 17 7 12.6 1 12C7 11.4 11.4 7 12 1Z" fill="#4285f4"/></svg>'; else ic.innerHTML = `<img src="../assets/${p.id}.png">`;
      const body = el('div', 'body', `<b>${p.name}</b> <span class="sub" style="font-size:10px;margin-left:6px">Limit</span>${tagHtml(u.limitConfidence)}<span class="sub" style="font-size:10px;margin-left:6px">Token</span>${tagHtml(u.tokenConfidence)}`);
      for (const n of u.notes || []) body.append(el('div', 'notes', n));
      const en = S.settings.enabled.includes(p.id);
      card.append(ic, body, toggle(en, (v) => window.ullage.setSettings({ enabled: v ? [...S.settings.enabled, p.id] : S.settings.enabled.filter((x) => x !== p.id) })));
      main.append(card);
    }
  }

  function syncPage() {
    const sel = el('select'); for (const [v, l] of [[15, '15 saniye'], [30, '30 saniye'], [60, '1 dakika'], [120, '2 dakika'], [300, '5 dakika'], [600, '10 dakika'], [900, '15 dakika'], [0, 'Yalnızca elle']]) { const o = el('option', null, l); o.value = v; if (v === S.settings.interval) o.selected = true; sel.append(o); }
    sel.onchange = () => window.ullage.setSettings({ interval: Number(sel.value) });
    main.append(setting('Otomatik yenileme', 'Verilerin arka planda ne sıklıkla okunacağı. Yerel kayıtlar (token geçmişi, Codex, Antigravity) her yenilemede okunur.', sel));
    const b = el('button', 'pill', 'Senkronize et'); b.onclick = () => window.ullage.refresh(true);
    main.append(setting('Şimdi senkronize et', S.updatedAt ? 'Son senkron: ' + new Date(S.updatedAt).toLocaleTimeString('tr-TR') : 'Henüz okunmadı.', b));
    main.append(el('div', 'card sub', '<b style="color:var(--text)">Kaynak başına sınırlar</b><br>Claude limit yüzdesi: Anthropic\'in kullanım bilgisi sınırlı olduğu için seçtiğin süre ne olursa olsun en sık 1 dakikada bir sorgulanır; hız sınırına takılırsa 5 dakika beklenir.<br>Antigravity limiti: IDE açıksa her yenilemede yerel sunucudan okunur, kapalıysa okunamaz.<br>Codex ve token geçmişi: yerel dosyalardan, her yenilemede.'));
    main.lastChild.style.cssText += ';font-size:12px;line-height:1.7';
  }

  function appearancePage() {
    main.append(el('div', 'sub', 'Tema popover\'a ve bu pencereye uygulanır.')); main.lastChild.style.marginBottom = '12px';
    const grid = el('div', 'themes');
    for (const t of THEMES) {
      const dark = window.matchMedia('(prefers-color-scheme: dark)').matches; const c = t.id === 'system' ? (dark ? t.dark : t.light) : t;
      const card = el('div', 'tcard' + (S.settings.theme === t.id ? ' on' : ''));
      const pv = el('div', 'pv'); pv.style.cssText = `background:${c.bg};border-radius:${t.radius}px;border:${t.bw}px solid ${t.border};color:${c.text}`;
      pv.innerHTML = `<div class="c" style="background:${c.card};border-radius:${Math.max(2, t.radius - 8)}px;border:${t.bw}px solid ${t.border}"></div><div class="r"><i style="background:${t.accent};border-radius:${t.bar === 'block' || t.bar === 'segmented' || t.bar === 'hairline' ? 0 : 4}px"></i><b>62%</b></div>`;
      card.append(pv, el('div', 'nm', t.name)); card.onclick = () => window.ullage.setSettings({ theme: t.id }); grid.append(card);
    }
    main.append(grid);
    const sel = el('select');
    for (const [v, l] of [['logo', 'Uygulama logosu'], ['bars', '5s ve haftalık çubuklar'], ['number', 'Tek sayı (en düşük kalan)']]) { const o = el('option', null, l); o.value = v; if (v === (S.settings.trayStyle || 'logo')) o.selected = true; sel.append(o); }
    sel.onchange = () => window.ullage.setSettings({ trayStyle: sel.value });
    main.append(setting('Tepsi simgesi', 'Windows tepsisinde ne gösterilsin. Logo seçiliyken simge veri göstermez, basınca uygulama açılır; limitler yüzen widget\'ta görünür. Çubuklar ve tek sayı seçeneklerinde simgeye basınca hızlı görünüm açılır.', sel));
    main.append(setting('Yüzen widget', 'Limitleri ekranda her zaman üstte duran küçük bir pencere olarak gösterir. Sürükleyerek yerini değiştirebilirsin.', toggle(S.settings.widget, (v) => window.ullage.setSettings({ widget: v }))));
    const size = el('div', 'sizectl');
    const pct = Math.round((Number(S.settings.widgetScale) || 1) * 100);
    const val = el('b', null, pct + '%');
    const rng = el('input'); rng.type = 'range'; rng.min = 70; rng.max = 180; rng.step = 10; rng.value = pct;
    rng.oninput = () => { val.textContent = rng.value + '%'; };           // sürüklerken yalnızca yazı değişir
    rng.onchange = () => window.ullage.setSettings({ widgetScale: Number(rng.value) / 100 }); // bırakınca uygulanır
    size.append(rng, val);
    main.append(setting('Widget boyutu', 'Yüzen widget\'ın büyüklüğünü ayarla. Widget kapalıysa bir sonraki açılışta uygulanır.', size));
  }

  function automationPage() {
    main.append(setting('Limit bildirimleri', 'Kalan %15 ve %5\'in altına inince, ayrıca limit yenilenince bildirim gönderir.', toggle(S.settings.notify, (v) => window.ullage.setSettings({ notify: v }))));
    main.append(setting('Claude oturumunu otomatik yenile', 'Claude Code oturumunun süresi dolarsa (yaklaşık 8 saatte bir) limit değeri eski kalır. Bu açıkken Ullage, Claude Code\'a tek satırlık bir istek attırıp oturumunu yeniletir. Çok az token harcar, anahtarlarına dokunmaz.', toggle(S.settings.refreshLogin !== false, (v) => window.ullage.setSettings({ refreshLogin: v }))));
    main.append(setting('Limiti Claude Code komutuyla ölç', 'Anthropic sorgusu işe yaramazsa, yalnızca yeni Claude kullanımı olunca ve en sık 5 dakikada bir Claude Code\'a tek satırlık küçük bir istek attırıp limiti ondan okur. Çok az token harcar. Claude uygulamasını kullanıyorsan da çalışır. Eski Claude Code sürümleri limit yüzdesini vermez.', toggle(S.settings.cliProbe !== false, (v) => window.ullage.setSettings({ cliProbe: v }))));
    const slSub ='Claude Code her cevaptan sonra limit bilgisini bir dosyaya yazar, Ullage onu okur: ağ yok, hız sınırı yok. Yalnızca Claude Code çalışırken güncellenir. Açınca ~/.claude/settings.json içine bir durum satırı komutu eklenir (önce yedeği alınır). Başka bir durum satırın varsa dokunulmaz; kapatınca yalnızca bizim eklediğimiz kaldırılır.'
      + (SL && SL.installed ? '<br><b>' + (SL.ageMin == null ? 'Henüz veri gelmedi: Claude Code\'u açıp bir mesaj yaz.' : `Son veri ${SL.ageMin} dk önce.`) + '</b>' : '')
      + (SL && SL.other ? '<br><b>Şu an başka bir durum satırı tanımlı, değiştirilmedi.</b>' : '')
      + (SLerr ? `<br><b style="color:#ff9f0a">${String(SLerr).replace(/[<>&]/g, '')}</b>` : '');
    main.append(setting('Claude limitini Claude Code\'dan al', slSub, toggle(!!(SL && SL.installed), async (v) => { const r = await window.ullage.setStatusLine(v); SL = r; SLerr = r.error; render(); })));
    main.append(setting('Girişte otomatik başlat', 'Bilgisayara giriş yapınca uygulama kendiliğinden açılır.', toggle(S.settings.login, (v) => window.ullage.setSettings({ login: v }))));
  }

  function aboutPage() {
    main.append(el('div', 'card', '<b style="font-size:22px">Ullage</b><br><span class="sub">Yapay zeka araçlarının limitini ve token kullanımını takip et.</span>'));
    main.lastChild.style.marginBottom = '12px';
    main.append(el('div', 'card sub', '<b style="color:var(--text)">Veri kaynakları</b><br>Claude: ~/.claude kayıtları (token), Anthropic kullanım uç noktası (limit)<br>Codex: ~/.codex oturum kayıtları (limit ve token)<br>Antigravity: yerel konuşma veritabanı (token), yerel dil sunucusu (limit)<br><br>Alınamayan ya da tahmini veriler Sağlayıcılar sayfasında "Kesin / Tahmini / Veri yok" etiketiyle gösterilir. Uydurma değer gösterilmez.'));
    main.lastChild.style.cssText += ';font-size:12px;line-height:1.7';
  }

  // ---- iskelet
  async function render() {
    if (!S) return;
    applyTheme(S.settings.theme);
    const page = S.settings.dashPage || 'usage';
    nav.innerHTML = ''; nav.append(el('h2', null, 'Ullage'));
    for (const [id, ic, label] of PAGES) { const b = el('button', id === page ? 'on' : '', `<span>${ic}</span>${label}`); b.onclick = () => window.ullage.setSettings({ dashPage: id }); nav.append(b); }
    const keep = main.scrollTop;
    main.innerHTML = ''; header(page);
    if (page === 'usage') { H = await window.ullage.getHistory(); usagePage(); }
    else if (page === 'providers') providersPage();
    else if (page === 'sync') syncPage();
    else if (page === 'appearance') appearancePage();
    else if (page === 'automation') { SL = await window.ullage.statusLineState(); automationPage(); }
    else aboutPage();
    main.scrollTop = keep;
  }

  window.ullage.onState((s) => { S = s; render(); });
  window.ullage.getState().then((s) => { S = s; render(); });
})();
