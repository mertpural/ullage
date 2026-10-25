'use strict';
(function () {
  const { PROVIDERS, applyTheme, bar, el } = window.ULL;
  const root = document.getElementById('root');
  const stage = document.getElementById('stage');
  let S = null; // { usage, settings }

  function line(label, row) {
    const l = el('div', 'w-line');
    l.append(el('span', 'caps', label), el('b', null, Math.round(row.left * 100) + '%'), bar(row.left));
    return l;
  }

  function render() {
    if (!S) return;
    applyTheme(S.settings.theme);
    root.innerHTML = '';
    const head = el('div', 'w-head');
    const close = el('button', 'w-x', '×');
    close.onclick = () => window.ullage.setSettings({ widget: false });
    head.append(el('span', 'caps', 'Ullage'), close);
    root.append(head);
    let any = false;
    for (const p of PROVIDERS) {
      if (!S.settings.enabled.includes(p.id)) continue;
      const w = S.usage[p.id] && S.usage[p.id].win;
      if (!w || (!w.five && !w.week)) continue;
      any = true;
      const row = el('div', 'w-row');
      row.append(el('div', 'w-name', p.name));
      if (w.five) row.append(line('5s', w.five));
      if (w.week) row.append(line('H', w.week));
      root.append(row);
    }
    if (!any) {
      const c = S.usage.claude || {};
      const hint = { 'signed-out': 'Claude girişi yok: terminalde claude yazıp /login yap.', 'no-file': 'Claude girişi yok: terminalde claude yazıp /login yap.', expired: 'Claude oturumunun süresi dolmuş; Claude Code\'u açınca yenilenir.' }[c.loginState];
      root.append(el('div', 'w-empty', S.settings.enabled.includes('claude') && hint ? hint : 'Limit verisi yok. Ayrıntı için Ayarlar > Sağlayıcılar.'));
    }
    const scale = Number(S.settings.widgetScale) || 1;
    stage.style.transform = `scale(${scale})`;
    requestAnimationFrame(() => window.ullage.resizePopover(Math.ceil(stage.offsetHeight * scale)));
  }

  window.ullage.onState((s) => { S = s; render(); });
  window.ullage.getState().then((s) => { S = s; render(); });
})();
