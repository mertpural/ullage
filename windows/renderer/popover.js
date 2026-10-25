'use strict';
(function () {
  const { PROVIDERS, applyTheme, formatTokens, formatRemaining, pace, statusWord, timeHM, bar, el } = window.ULL;
  const root = document.getElementById('root');
  let S = null; // { usage, daily, updatedAt, settings }

  function icon(p, size) {
    const d = el('span', 'ico');
    if (size) { d.style.width = d.style.height = size + 'px'; }
    if (p === 'codex') d.classList.add('mask');
    else if (p === 'gemini') d.innerHTML = '<svg viewBox="0 0 24 24"><path d="M12 1C12.6 7 17 11.4 23 12C17 12.6 12.6 17 12 23C11.4 17 7 12.6 1 12C7 11.4 11.4 7 12 1Z" fill="#4285f4"/></svg>';
    else d.innerHTML = `<img src="../assets/${p}.png">`;
    return d;
  }

  const providerName = (id) => PROVIDERS.find((p) => p.id === id).name;
  const providerColor = (id) => PROVIDERS.find((p) => p.id === id).color;

  // Claude girişi yoksa ya da süresi dolmuşsa, boş kart yerine ne yapılacağını söyle.
  const LOGIN_HINT = {
    'signed-out': 'Claude Code girişi yok. Terminalde claude yaz, sonra /login ile giriş yap.',
    'no-file': 'Claude Code kurulu değil ya da hiç giriş yapılmamış. Terminalde claude yazıp /login yap.',
    expired: 'Claude Code oturumunun süresi dolmuş. Claude Code\'u açınca kendiliğinden yenilenir.',
  };

  function loginHelp(u) {
    const box = el('div', 'login-help');
    box.append(el('div', 'empty', LOGIN_HINT[u.loginState]));
    const row = el('div', 'login-actions');
    const copy = el('button', 'pill', 'Komutu kopyala');
    copy.onclick = () => { window.ullage.copyText('claude'); copy.textContent = 'Kopyalandı'; };
    const check = el('button', 'pill', 'Girişi kontrol et');
    check.onclick = () => window.ullage.refresh(true);
    row.append(copy, check); box.append(row);
    return box;
  }

  function metric(title, row, windowMs) {
    const m = el('div', 'metric');
    const top = el('div', 'top'); top.append(el('span', 'caps', title), el('b', null, Math.round(row.left * 100) + '%'));
    m.append(top, bar(row.left, (pace(row, windowMs) || {}).expected));
    m.append(el('div', 'reset', row.reset ? (row.reset > Date.now() ? 'Sıfırlanma ' + formatRemaining(row.reset - Date.now()) : 'Pencere sıfırlandı') : ''));
    return m;
  }

  function overviewCard(p) {
    const u = S.usage[p]; const w = u.win;
    const c = el('div', 'card');
    const head = el('div', 'ov-head');
    head.append(icon(p, 22), el('b', null, providerName(p)), el('span', 'grow'));
    if (u.todayTokens != null) head.append(el('span', 'sub', 'Bugün ' + formatTokens(u.todayTokens)));
    c.append(head);
    if (w.five || w.week) {
      const two = el('div', 'two');
      if (w.five) two.append(metric('5 SAATLİK', w.five, 5 * 3600e3));
      if (w.week) two.append(metric('HAFTALIK', w.week, 7 * 86400e3));
      c.append(two);
    }
    for (const r of w.other) c.append(metric(r.title.replace(' · günlük kota', '').toUpperCase(), r, 86400e3));
    if (!w.five && !w.week && !w.other.length) c.append(LOGIN_HINT[u.loginState] ? el('div', 'empty', LOGIN_HINT[u.loginState]) : el('div', 'empty', 'Veri alınamadı. Ayrıntı için Sağlayıcılar sayfasına bak.'));
    if (u.staleSince) c.append(el('div', 'stale', `Eski değer: ${timeHM(u.staleSince)} (güncellenemedi)`));
    return c;
  }

  function metricCard(title, glyph, row, windowMs) {
    const c = el('div', 'card mc');
    const [word, color] = statusWord(row.left);
    const r1 = el('div', 'row'); r1.append(el('span', 'caps', glyph + ' ' + title), el('span', 'chip', word));
    r1.lastChild.style.cssText = `color:${color};background:color-mix(in srgb, ${color} 18%, transparent)`;
    c.append(r1, el('div', 'big', `${Math.round(row.left * 100)}%<small>kaldı</small>`));
    const pc = pace(row, windowMs);
    c.append(bar(row.left, pc && pc.expected));
    const foot = el('div', 'foot');
    foot.append(el('span', null, row.reset ? (row.reset > Date.now() ? formatRemaining(row.reset - Date.now()) : 'sıfırlandı') : ''));
    if (pc) { const ch = el('span', 'chip', pc.label); ch.style.cssText = `color:${pc.color};background:color-mix(in srgb, ${pc.color} 18%, transparent)`; foot.append(ch); }
    c.append(foot);
    return c;
  }

  function detail(p) {
    const u = S.usage[p]; const w = u.win;
    const box = el('div', 'list');
    const t = el('div', 'det-title'); t.append(icon(p, 26), el('b', null, providerName(p))); box.append(t);
    if (u.staleSince) box.append(el('div', 'stale', `Eski değer: ${timeHM(u.staleSince)} (güncellenemedi)`));
    if (!w.five && !w.week && !w.other.length && !(u.extra || []).length) {
      if (LOGIN_HINT[u.loginState]) { const c = el('div', 'card'); c.append(loginHelp(u)); box.append(c); }
      else box.append(el('div', 'card empty', u.notes[0] || 'Veri alınamadı.'));
    } else if (LOGIN_HINT[u.loginState]) box.append(loginHelp(u));
    if (w.five || w.week) {
      const two = el('div', 'cards2');
      if (w.five) two.append(metricCard('5 SAATLİK', '⚡', w.five, 5 * 3600e3));
      if (w.week) two.append(metricCard('HAFTALIK', '▦', w.week, 7 * 86400e3));
      box.append(two);
    }
    if ((u.extra || []).length > 2 || w.other.length) {
      const c = el('div', 'card pools'); c.append(el('div', 'caps', w.other.length ? 'KOTALAR' : 'HAVUZLAR'));
      c.firstChild.style.marginBottom = '8px';
      for (const r of u.extra) {
        const lb = el('div', 'lb'); lb.append(el('span', null, r.title), el('span', null, `<b>${Math.round(r.left * 100)}%</b>${r.reset ? ' · ' + (r.reset > Date.now() ? formatRemaining(r.reset - Date.now()) : 'sıfırlandı') : ''}`));
        c.append(lb, bar(r.left));
      }
      box.append(c);
    }
    if (u.todayTokens != null) {
      const c = el('div', 'card');
      const head = el('div', 'ov-head'); head.style.marginBottom = '0';
      head.append(el('span', 'caps', 'TOKEN'), el('span', 'grow'), el('span', 'sub', 'Son 7 gün')); c.append(head);
      const tok = el('div', 'tok'); tok.append(el('div', null, `<div class="num">${formatTokens(u.todayTokens)}</div><div class="sub" style="font-size:10px">bugün</div>`
        + (u.cacheReadToday != null ? `<div class="sub" style="font-size:10px">cache okuma ${formatTokens(u.cacheReadToday)}</div>` : '')));
      const days = el('div', 'days'); const arr = (S.daily[p] || []); const mx = Math.max(1, ...arr);
      for (const v of arr) { const i = el('i'); i.style.cssText = `height:${Math.max(3, 34 * v / mx)}px;background:${providerColor(p)}`; days.append(i); }
      tok.append(days); c.append(tok); box.append(c);
    }
    return box;
  }

  function render() {
    if (!S) return;
    const set = S.settings; applyTheme(set.theme);
    const enabled = PROVIDERS.map((p) => p.id).filter((id) => set.enabled.includes(id));
    const tab = enabled.includes(set.tab) ? set.tab : 'all';
    root.innerHTML = '';
    const head = el('div', 'head'); head.append(el('h1', null, 'Ullage'), el('span', 'sub', S.updatedAt ? 'Güncellendi ' + timeHM(S.updatedAt) : ''));
    const tabs = el('div', 'tabs');
    const all = el('button', 'pill' + (tab === 'all' ? ' on' : ''), 'Tümü'); all.onclick = () => window.ullage.setSettings({ tab: 'all' }); tabs.append(all);
    for (const id of enabled) { const b = el('button', 'pill' + (tab === id ? ' on' : '')); b.append(icon(id)); b.onclick = () => window.ullage.setSettings({ tab: id }); tabs.append(b); }
    root.append(head, tabs);
    if (!enabled.length) root.append(el('div', 'empty', 'Hiçbir sağlayıcı seçili değil. Ayarlardan aç.'));
    else if (tab === 'all') { const l = el('div', 'list'); for (const id of enabled) l.append(overviewCard(id)); root.append(l); }
    else root.append(detail(tab));
    const foot = el('div', 'foot-bar');
    const mk = (html, fn) => { const b = el('button', 'pill', html); b.onclick = fn; return b; };
    foot.append(mk('▮▮ Kullanım', () => window.ullage.openDashboard('usage')), mk('⚙ Ayarlar', () => window.ullage.openDashboard('providers')), el('span', 'grow'),
      mk('↻', () => window.ullage.refresh(true)), mk('⏻', () => window.ullage.quit()));
    root.append(foot);
    requestAnimationFrame(() => window.ullage.resizePopover(Math.ceil(document.body.scrollHeight)));
  }

  window.ullage.onState((s) => { S = s; render(); });
  window.ullage.getState().then((s) => { S = s; render(); });
  setInterval(render, 30000); // geri sayımlar için
})();
