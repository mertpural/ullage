'use strict';
const { app, BrowserWindow, Tray, Menu, nativeImage, ipcMain, screen, Notification, clipboard } = require('electron');
const path = require('path');
const { Store } = require('./store');
const { Settings } = require('./settings');
const { refreshAll } = require('./sources');

const R = (...p) => path.join(__dirname, '..', '..', 'renderer', ...p);
const SHOTS = (process.argv.find((a) => a.startsWith('--shots=')) || '').slice(8);

let store, settings, tray, popover, dashboard, widget, iconWin;
let state = { usage: {}, daily: {}, updatedAt: 0, settings: {} };
let timer = null, refreshing = false;

if (!app.requestSingleInstanceLock()) app.quit();
if (process.platform === 'darwin' && app.dock) app.dock.hide();

const publicState = () => ({ ...state, settings: settings.v });
const broadcast = () => { for (const w of [popover, dashboard, widget]) if (w && !w.isDestroyed()) w.webContents.send('state', publicState()); };

// ---- pencereler
function makePopover() {
  popover = new BrowserWindow({
    width: 380, height: 300, show: false, frame: false, resizable: false, skipTaskbar: true, alwaysOnTop: true,
    fullscreenable: false, backgroundColor: '#1c1c1e', webPreferences: { preload: path.join(__dirname, 'preload.js') },
  });
  popover.loadFile(R('popover.html'));
  popover.on('blur', () => { if (!SHOTS && !popover.webContents.isDevToolsOpened()) popover.hide(); });
}

function placePopover() {
  const b = tray.getBounds();
  const [w, h] = popover.getSize();
  const disp = screen.getDisplayNearestPoint({ x: b.x, y: b.y });
  const wa = disp.workArea;
  let x = Math.round(b.x + b.width / 2 - w / 2);
  let y = process.platform === 'darwin' ? Math.round(b.y + b.height + 4) : Math.round(b.y - h - 8);
  if (b.width === 0 && b.height === 0) { x = wa.x + wa.width - w - 12; y = process.platform === 'darwin' ? wa.y + 4 : wa.y + wa.height - h - 12; }
  x = Math.max(wa.x + 4, Math.min(x, wa.x + wa.width - w - 4));
  y = Math.max(wa.y + 4, Math.min(y, wa.y + wa.height - h - 4));
  popover.setPosition(x, y, false);
}

function togglePopover() {
  if (popover.isVisible()) { popover.hide(); return; }
  placePopover(); popover.show(); popover.focus();
  doRefresh(false);
}

function openDashboard(page) {
  if (page) settings.patch({ dashPage: page });
  if (popover && popover.isVisible()) popover.hide();
  if (!dashboard || dashboard.isDestroyed()) {
    dashboard = new BrowserWindow({
      width: 1020, height: 720, minWidth: 860, minHeight: 560, title: 'Ullage', autoHideMenuBar: true, backgroundColor: '#1c1c1e',
      webPreferences: { preload: path.join(__dirname, 'preload.js') },
    });
    dashboard.setMenu(null);
    dashboard.loadFile(R('dashboard.html'));
    dashboard.on('closed', () => { dashboard = null; });
  } else { dashboard.show(); dashboard.focus(); dashboard.webContents.send('state', publicState()); }
}

// ---- küçük yüzen widget: her zaman üstte, görev çubuğunda görünmez, sürüklenebilir
function widgetPosition(pos) {
  const inside = (d) => pos.x >= d.workArea.x && pos.x < d.workArea.x + d.workArea.width && pos.y >= d.workArea.y && pos.y < d.workArea.y + d.workArea.height;
  return screen.getAllDisplays().some(inside);
}

function makeWidget() {
  const saved = settings.v.widgetPos;
  const useSaved = saved && widgetPosition(saved);
  // Şeffaf ve odak almayan pencere: arkadaki uygulamalar etkilenmez, yalnızca karta basınca tutulur.
  widget = new BrowserWindow({
    width: 252, height: 120, show: false, frame: false, transparent: true, hasShadow: false, resizable: false, skipTaskbar: true,
    alwaysOnTop: true, focusable: false, minimizable: false, maximizable: false, fullscreenable: false, backgroundColor: '#00000000',
    webPreferences: { preload: path.join(__dirname, 'preload.js') },
  });
  widget.setAlwaysOnTop(true, 'screen-saver');
  if (useSaved) widget.setPosition(saved.x, saved.y);
  else { const wa = screen.getPrimaryDisplay().workArea; widget.setPosition(wa.x + wa.width - 252 - 4, wa.y + 4); }
  widget.loadFile(R('widget.html'));
  widget.once('ready-to-show', () => widget.showInactive());
  let t = null;
  widget.on('move', () => {
    clearTimeout(t);
    t = setTimeout(() => { if (widget && !widget.isDestroyed()) { const [x, y] = widget.getPosition(); settings.patch({ widgetPos: { x, y } }); } }, 400);
  });
  widget.on('closed', () => { widget = null; });
}

/** Ayara göre widget'ı açar ya da kapatır. */
function syncWidget() {
  if (settings.v.widget && (!widget || widget.isDestroyed())) makeWidget();
  if (!settings.v.widget && widget && !widget.isDestroyed()) widget.close();
}

// ---- tepsi simgesi
/** spec: { kind: 'bars', bars: [{ label, left, color }] } ya da { kind: 'number', text, color }. 64 px tuval; Windows küçültür. */
async function drawTray(spec) {
  if (!iconWin || iconWin.isDestroyed()) {
    iconWin = new BrowserWindow({ show: false, width: 64, height: 64, webPreferences: { offscreen: false } });
    await iconWin.loadURL('data:text/html,<canvas id=c width=64 height=64></canvas>');
  }
  const url = await iconWin.webContents.executeJavaScript(`(() => {
    const spec = ${JSON.stringify(spec)};
    const c = document.getElementById('c'), g = c.getContext('2d');
    g.clearRect(0, 0, 64, 64);
    if (spec.kind === 'number') {
      g.fillStyle = spec.color; g.beginPath(); g.roundRect(2, 2, 60, 60, 14); g.fill();
      g.fillStyle = '#fff'; g.font = 'bold ' + (spec.text.length > 2 ? 30 : 38) + 'px Segoe UI, Arial, sans-serif'; g.textAlign = 'center'; g.textBaseline = 'middle';
      g.fillText(spec.text, 32, 35);
    } else {
      spec.bars.forEach((b, i) => {
        const y = 12 + i * 26;
        g.font = 'bold 26px Segoe UI, Arial, sans-serif'; g.textAlign = 'left'; g.textBaseline = 'middle';
        g.lineJoin = 'round'; g.lineWidth = 4; g.strokeStyle = 'rgba(0,0,0,.65)'; g.strokeText(b.label, 0, y + 14);
        g.fillStyle = '#f2f2f7'; g.fillText(b.label, 0, y + 14);
        g.fillStyle = 'rgba(128,128,128,.45)'; g.beginPath(); g.roundRect(30, y + 5, 32, 18, 9); g.fill();
        if (b.left > 0) { g.fillStyle = b.color; g.beginPath(); g.roundRect(30, y + 5, Math.max(9, 32 * b.left), 18, 9); g.fill(); }
      });
    }
    return c.toDataURL();
  })()`);
  return nativeImage.createFromDataURL(url);
}

const drawIcon = (text, color) => drawTray({ kind: 'number', text, color });

// Logo modu: tepsi simgesi veri göstermez, yalnızca uygulamanın logosu görünür (veri widget'ta ve pencerede).
let logo = null;
const logoImage = () => logo || (logo = nativeImage.createFromPath(path.join(__dirname, '..', '..', 'assets', 'icon.png')).resize({ width: 32, height: 32 }));
const logoMode = () => process.platform !== 'darwin' && settings.v.trayStyle === 'logo';

const statusColor = (l) => (l > 0.4 ? '#22a559' : l > 0.15 ? '#d98200' : '#d93025');
const NAMES = { claude: 'Claude', codex: 'Codex', gemini: 'Gemini', antigravity: 'Antigravity' };

async function updateTray() {
  if (!tray) return;
  const enabled = settings.v.enabled;
  const lines = []; const parts = []; let tightest = null, five = null, week = null;
  for (const p of enabled) {
    const w = state.usage[p] && state.usage[p].win; if (!w) continue;
    const pct = (r) => Math.round(r.left * 100);
    if (w.five || w.week) {
      lines.push(`${NAMES[p]}: ${w.five ? '5s ' + pct(w.five) + '%' : ''}${w.five && w.week ? '  ' : ''}${w.week ? 'H ' + pct(w.week) + '%' : ''}`);
      parts.push(`${w.five ? '5s ' + pct(w.five) + '%' : ''}${w.five && w.week ? ' ' : ''}${w.week ? 'H ' + pct(w.week) + '%' : ''}`);
    }
    if (w.five && (!five || w.five.left < five.left)) five = w.five;
    if (w.week && (!week || w.week.left < week.left)) week = w.week;
    for (const r of [w.five, w.week, ...w.other]) if (r && (tightest === null || r.left < tightest)) tightest = r.left;
  }
  tray.setToolTip(lines.length && !logoMode() ? lines.join('\n') : 'Ullage');
  if (process.platform === 'darwin') { tray.setTitle(parts.join('   ')); return; }
  if (logoMode()) { tray.setImage(logoImage()); return; }
  // Tepsi simgesi: 5 saatlik ve haftalık en kısıtlayıcı değerler, her ikisi de yoksa tek sayı.
  if (settings.v.trayStyle !== 'number' && (five || week)) {
    const bars = [];
    if (five) bars.push({ label: '5s', left: five.left, color: statusColor(five.left) });
    if (week) bars.push({ label: 'H', left: week.left, color: statusColor(week.left) });
    tray.setImage(await drawTray({ kind: 'bars', bars }));
  } else if (tightest !== null) tray.setImage(await drawIcon(String(Math.round(tightest * 100)), statusColor(tightest)));
}

// ---- bildirimler: eşikler pencere başına bir kez, ayrıca limit yenilenince
function notify(prev, next) {
  if (!settings.v.notify || !Notification.isSupported()) return;
  const seen = new Set(store.kv('notified') || []);
  for (const p of settings.v.enabled) {
    const u = next[p]; if (!u || u.limitConfidence === 'none') continue;
    const rows = [u.win.five, u.win.week, ...u.win.other].filter(Boolean);
    for (const r of rows) {
      const base = `${p}|${r.title}|${r.reset || 0}`;
      for (const [lv, label] of [[0.05, '%5'], [0.15, '%15']]) {
        if (r.left <= lv && !seen.has(`${base}|${lv}`)) {
          seen.add(`${base}|0.05`); seen.add(`${base}|${lv}`);
          new Notification({ title: `${NAMES[p]}: limit azaldı`, body: `${r.title} için kalan ${label} altına düştü (${Math.round(r.left * 100)}%).` }).show();
          break;
        }
      }
      const old = prev[p] && [prev[p].win.five, prev[p].win.week, ...prev[p].win.other].filter(Boolean).find((x) => x.title === r.title);
      if (old && old.left <= 0.2 && r.left >= 0.9) new Notification({ title: `${NAMES[p]}: limit yenilendi`, body: `${r.title} penceresi sıfırlandı, %${Math.round(r.left * 100)} kaldı.` }).show();
    }
  }
  store.kv('notified', Array.from(seen).slice(-300));
}

// ---- yenileme
async function doRefresh(force) {
  if (refreshing) return;
  refreshing = true;
  try {
    const prev = state.usage;
    const r = await refreshAll(store, { force, refreshLogin: settings.v.refreshLogin !== false });
    state = { ...state, ...r };
    if (Object.keys(prev).length) notify(prev, r.usage);
    await updateTray();
    broadcast();
  } catch (e) { console.error('yenileme hatası', e); } finally { refreshing = false; }
}

function restartTimer() {
  clearInterval(timer); timer = null;
  const s = settings.v.interval;
  if (s > 0) timer = setInterval(() => doRefresh(false), s * 1000);
}

// ---- IPC
ipcMain.handle('state', () => publicState());
ipcMain.handle('history', () => store.aggregate());
ipcMain.handle('settings', (_e, patch) => {
  settings.patch(patch);
  if ('interval' in patch) restartTimer();
  if ('login' in patch) app.setLoginItemSettings({ openAtLogin: !!patch.login });
  if ('enabled' in patch || 'trayStyle' in patch) updateTray();
  if ('widget' in patch) syncWidget();
  broadcast();
  return settings.v;
});
ipcMain.handle('refresh', (_e, force) => doRefresh(force));
ipcMain.handle('dashboard', (_e, page) => openDashboard(page));
ipcMain.handle('quit', () => app.quit());
ipcMain.handle('copy-text', (_e, text) => clipboard.writeText(String(text)));ipcMain.on('resize-popover', (e, h) => {
  const win = BrowserWindow.fromWebContents(e.sender);
  if (!win || win.isDestroyed()) return;
  const height = Math.max(win === popover ? 140 : 90, Math.min(640, Math.round(h)));
  const [w, cur] = win.getContentSize();
  if (Math.abs(cur - height) < 2) return;
  const bounds = win.getBounds();
  const bottomAnchored = win === popover && process.platform !== 'darwin';
  win.setContentSize(w, height);
  if (bottomAnchored && win.isVisible()) { const nb = win.getBounds(); win.setPosition(bounds.x, bounds.y + bounds.height - nb.height, false); }
});

// ---- açılış
app.whenReady().then(async () => {
  const dir = app.getPath('userData');
  store = new Store(dir); settings = new Settings(dir);
  makePopover();
  tray = new Tray(nativeImage.createEmpty());
  if (process.platform !== 'darwin') tray.setImage(logoMode() ? logoImage() : await drawIcon('…', '#6e6e73'));
  tray.setToolTip('Ullage');
  // Logo modunda tepsi simgesine basınca uygulama penceresi açılır; hızlı görünüm sağ tık menüsünde.
  tray.on('click', () => (logoMode() ? openDashboard('usage') : togglePopover()));
  tray.on('right-click', () => tray.popUpContextMenu(Menu.buildFromTemplate([
    { label: 'Kullanım', click: () => openDashboard('usage') }, { label: 'Ayarlar', click: () => openDashboard('providers') },
    { label: 'Hızlı görünüm', click: togglePopover },
    { label: 'Yenile', click: () => doRefresh(true) },
    { label: 'Yüzen widget', type: 'checkbox', checked: !!settings.v.widget, click: (item) => { settings.patch({ widget: item.checked }); syncWidget(); } },
    { type: 'separator' }, { label: 'Çıkış', click: () => app.quit() },
  ])));
  syncWidget();
  await doRefresh(false);
  restartTimer();
  if (SHOTS) require('./shots').run({ SHOTS, app, drawIcon, popover: () => popover, openDashboard: (p) => { openDashboard(p); return dashboard; }, settings, broadcast, placePopover });
});

app.on('window-all-closed', (e) => e.preventDefault());
app.on('before-quit', () => { if (store) store.save(true); });
