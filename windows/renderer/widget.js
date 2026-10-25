'use strict';
(function () {
  const { PROVIDERS, applyTheme, bar, el } = window.ULL;
  const root = document.getElementById('root');
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
    if (!any) root.append(el('div', 'w-empty', 'Limit verisi yok. Claude için Ayarlar > Sağlayıcılar kısmına bak.'));
    requestAnimationFrame(() => window.ullage.resizePopover(Math.ceil(document.body.scrollHeight)));
  }

  window.ullage.onState((s) => { S = s; render(); });
  window.ullage.getState().then((s) => { S = s; render(); });
})();
