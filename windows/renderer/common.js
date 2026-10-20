'use strict';
// Popover ve Kullanım penceresinin ortak parçaları: temalar, biçimleyiciler, tempo hesabı.
(function () {
  const PROVIDERS = [
    { id: 'claude', name: 'Claude', color: '#d9785a' },
    { id: 'codex', name: 'Codex', color: '#9ea1a8' },
    { id: 'gemini', name: 'Gemini', color: '#4285f4' },
    { id: 'antigravity', name: 'Antigravity', color: '#294dcc' },
  ];

  const THEMES = [
    { id: 'system', name: 'Sistem', dark: { bg: '#1c1c1e', card: 'rgba(255,255,255,.07)', text: '#fff', sub: '#a1a1a6' }, light: { bg: '#f5f5f7', card: 'rgba(0,0,0,.05)', text: '#1d1d1f', sub: '#6e6e73' }, border: 'transparent', bw: 0, radius: 14, font: 'system', accent: '#5a80ff', bar: 'capsule', barH: 6, pill: 999 },
    { id: 'dark', name: 'Koyu', bg: '#141419', card: '#24242b', text: '#ffffff', sub: '#9e9ea6', border: 'rgba(255,255,255,.08)', bw: 1, radius: 14, font: 'system', accent: '#8c73ff', bar: 'capsule', barH: 8, pill: 999 },
    { id: 'light', name: 'Açık', bg: '#f7f5f0', card: '#ffffff', text: '#1a1a1a', sub: '#6b6b6b', border: 'rgba(0,0,0,.06)', bw: 0, radius: 22, font: 'system', accent: '#d9734d', bar: 'thin', barH: 3, pill: 999 },
    { id: 'terminal', name: 'Terminal', bg: '#000000', card: '#081208', text: '#66ff80', sub: '#479e57', border: 'rgba(51,153,77,.6)', bw: 1, radius: 3, font: 'mono', accent: '#66ff80', bar: 'segmented', barH: 10, pill: 2 },
    { id: 'sticker', name: 'Sticker', bg: '#e6f7ed', card: '#ffffff', text: '#000000', sub: '#595959', border: '#000000', bw: 2, radius: 16, font: 'rounded', accent: '#1a9980', bar: 'block', barH: 10, pill: 12 },
    { id: 'paper', name: 'Kağıt', bg: '#f7f0db', card: '#fcf7e8', text: '#33291c', sub: '#7a6b54', border: 'rgba(51,41,28,.25)', bw: 0.8, radius: 4, font: 'serif', accent: '#8f5c33', bar: 'hairline', barH: 2, pill: 4 },
    { id: 'neon', name: 'Neon', bg: '#05050d', card: '#121221', text: '#ebfaff', sub: '#80a8c7', border: 'rgba(255,64,204,.7)', bw: 1, radius: 18, font: 'system', accent: '#33f2ff', bar: 'thin', barH: 3, pill: 999 },
    { id: 'brutal', name: 'Brutal', bg: '#ffe633', card: '#ffffff', text: '#000000', sub: '#404040', border: '#000000', bw: 3, radius: 0, font: 'system', accent: '#ff4d4d', bar: 'block', barH: 12, pill: 0 },
    { id: 'glass', name: 'Cam', bg: '#122442', card: 'rgba(255,255,255,.08)', text: '#ffffff', sub: 'rgba(255,255,255,.62)', border: 'rgba(255,255,255,.22)', bw: 1, radius: 22, font: 'rounded', accent: '#8cd9ff', bar: 'thin', barH: 4, pill: 999 },
  ];

  const FONTS = {
    system: "'Segoe UI Variable', 'Segoe UI', system-ui, -apple-system, sans-serif",
    rounded: "'Nunito', 'Segoe UI Variable', ui-rounded, system-ui, sans-serif",
    mono: "Consolas, 'Cascadia Mono', 'SF Mono', Menlo, monospace",
    serif: "Georgia, 'Times New Roman', serif",
  };

  function applyTheme(id) {
    const t = THEMES.find((x) => x.id === id) || THEMES[0];
    const dark = window.matchMedia('(prefers-color-scheme: dark)').matches;
    const c = t.id === 'system' ? (dark ? t.dark : t.light) : t;
    const r = document.documentElement.style;
    r.setProperty('--bg', c.bg); r.setProperty('--card', c.card); r.setProperty('--text', c.text); r.setProperty('--sub', c.sub);
    r.setProperty('--border', t.border); r.setProperty('--bw', t.bw + 'px'); r.setProperty('--radius', t.radius + 'px');
    r.setProperty('--font', FONTS[t.font]); r.setProperty('--accent', t.accent); r.setProperty('--pill', t.pill + 'px'); r.setProperty('--barh', t.barH + 'px');
    document.documentElement.dataset.theme = t.id;
    document.documentElement.dataset.bar = t.bar;
    return t;
  }

  const statusColor = (left) => (left > 0.4 ? '#34c759' : left > 0.15 ? '#ff9f0a' : '#ff453a');
  const statusWord = (left) => (left > 0.4 ? ['Sağlıklı', '#34c759'] : left > 0.15 ? ['Dikkat', '#ff9f0a'] : ['Kritik', '#ff453a']);

  function formatTokens(n) {
    if (n >= 1e9) return (n / 1e9).toFixed(1) + 'B';
    if (n >= 1e6) return (n / 1e6).toFixed(1) + 'M';
    if (n >= 1e3) return Math.floor(n / 1e3) + 'K';
    return String(n);
  }

  function formatRemaining(ms) {
    const s = Math.floor(ms / 1000);
    if (s <= 0) return 'şimdi';
    const d = Math.floor(s / 86400), h = Math.floor((s % 86400) / 3600), m = Math.floor((s % 3600) / 60);
    if (d > 0) return `${d}g ${h}s`;
    if (h > 0) return `${h}s ${m}dk`;
    return `${m}dk`;
  }

  /** Kullanım, geçen süreyle orantılıysa "Dengeli"; öndeyse "Hızlı", gerideyse "Rahat". */
  function pace(row, windowMs, now = Date.now()) {
    if (!row || !row.reset || row.reset <= now) return null;
    const remaining = row.reset - now;
    if (remaining > windowMs + 60000) return null;
    const elapsed = Math.max(0, Math.min(1, 1 - remaining / windowMs));
    const delta = (1 - row.left) - elapsed;
    const expected = 1 - elapsed;
    if (row.left <= 0.001) return { label: 'Bitti', color: '#ff453a', expected };
    if (delta > 0.25) return { label: 'Çok hızlı', color: '#ff453a', expected };
    if (delta > 0.1) return { label: 'Hızlı', color: '#ff9f0a', expected };
    if (delta < -0.15) return { label: 'Rahat', color: '#0a84ff', expected };
    return { label: 'Dengeli', color: '#34c759', expected };
  }

  const timeHM = (ms) => new Date(ms).toLocaleTimeString('tr-TR', { hour: '2-digit', minute: '2-digit' });

  /** Tema çubuk biçimine göre bir ilerleme çubuğu üretir. */
  function bar(left, expected) {
    const col = statusColor(left);
    const wrap = document.createElement('div');
    wrap.className = 'bar';
    if (document.documentElement.dataset.bar === 'segmented') {
      for (let i = 0; i < 20; i++) { const s = document.createElement('i'); if (i / 20 < left) s.style.background = col; wrap.appendChild(s); }
    } else {
      const f = document.createElement('i'); f.style.width = Math.max(2, left * 100) + '%'; f.style.background = col; wrap.appendChild(f);
    }
    if (expected != null) { const m = document.createElement('b'); m.style.left = `calc(${expected * 100}% - 1px)`; wrap.appendChild(m); }
    return wrap;
  }

  const el = (tag, cls, html) => { const e = document.createElement(tag); if (cls) e.className = cls; if (html != null) e.innerHTML = html; return e; };

  window.ULL = { PROVIDERS, THEMES, applyTheme, statusColor, statusWord, formatTokens, formatRemaining, pace, timeHM, bar, el };
})();
