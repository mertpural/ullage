'use strict';
const { app, BrowserWindow, Tray, Menu, nativeImage, ipcMain, screen, Notification } = require('electron');
const path = require('path');
const { Store } = require('./store');
const { Settings } = require('./settings');
const { refreshAll } = require('./sources');

const R = (...p) => path.join(__dirname, '..', '..', 'renderer', ...p);
const SHOTS = (process.argv.find((a) => a.startsWith('--shots=')) || '').slice(8);

let store, settings, tray, popover, dashboard, iconWin;
let state = { usage: {}, daily: {}, updatedAt: 0, settings: {} };
let timer = null, refreshing = false;

if (!app.requestSingleInstanceLock()) app.quit();
if (process.platform === 'darwin' && app.dock) app.dock.hide();

const publicState = () => ({ ...state, settings: settings.v });
const broadcast = () => { for (const w of [popover, dashboard]) if (w && !w.isDestroyed()) w.webContents.send('state', publicState()); };

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

// ---- tepsi simgesi
async function drawIcon(text, color) {
  if (!iconWin || iconWin.isDestroyed()) {
    iconWin = new BrowserWindow({ show: false, width: 64, height: 64, webPreferences: { offscreen: false } });
    await iconWin.loadURL('data:text/html,<canvas id=c width=64 height=64></canvas>');
  }
  const url = await iconWin.webContents.executeJavaScript(`(() => {
    const c = document.getElementById('c'), g = c.getContext('2d');
    g.clearRect(0, 0, 64, 64);
    g.fillStyle = ${JSON.stringify(color)}; g.beginPath(); g.roundRect(2, 2, 60, 60, 14); g.fill();
    g.fillStyle = '#fff'; g.font = 'bold ${text.length > 2 ? 30 : 38}px Segoe UI, Arial, sans-serif'; g.textAlign = 'center'; g.textBaseline = 'middle';
    g.fillText(${JSON.stringify(text)}, 32, 35);
    return c.toDataURL();
  })()`);
  return nativeImage.createFromDataURL(url);
}

const statusColor = (l) => (l > 0.4 ? '#22a559' : l > 0.15 ? '#d98200' : '#d93025');
const NAMES = { claude: 'Claude', codex: 'Codex', gemini: 'Gemini', antigravity: 'Antigravity' };

async function updateTray() {
  if (!tray) return;
  const enabled = settings.v.enabled;
  const lines = []; const parts = []; let tightest = null;
  for (const p of enabled) {
    const w = state.usage[p] && state.usage[p].win; if (!w) continue;
    const pct = (r) => Math.round(r.left * 100);
    if (w.five || w.week) {
      lines.push(`${NAMES[p]}: ${w.five ? '5s ' + pct(w.five) + '%' : ''}${w.five && w.week ? '  ' : ''}${w.week ? 'H ' + pct(w.week) + '%' : ''}`);
      parts.push(`${w.five ? '5s ' + pct(w.five) + '%' : ''}${w.five && w.week ? ' ' : ''}${w.week ? 'H ' + pct(w.week) + '%' : ''}`);
    }
    for (const r of [w.five, w.week, ...w.other]) if (r && (tightest === null || r.left < tightest)) tightest = r.left;
  }
  tray.setToolTip(lines.length ? lines.join('\n') : 'Ullage');
  if (process.platform === 'darwin') tray.setTitle(parts.join('   '));
  else if (tightest !== null) tray.setImage(await drawIcon(String(Math.round(tightest * 100)), statusColor(tightest)));
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
    const r = await refreshAll(store, { force });
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
  if ('enabled' in patch) updateTray();
  broadcast();
  return settings.v;
});
ipcMain.handle('refresh', (_e, force) => doRefresh(force));
ipcMain.handle('dashboard', (_e, page) => openDashboard(page));
ipcMain.handle('quit', () => app.quit());
ipcMain.on('resize-popover', (_e, h) => {
  if (!popover || popover.isDestroyed()) return;
  const height = Math.max(140, Math.min(640, Math.round(h)));
  const [w, cur] = popover.getContentSize();
  if (Math.abs(cur - height) < 2) return;
  const bounds = popover.getBounds();
  const bottomAnchored = process.platform !== 'darwin';
  popover.setContentSize(w, height);
  if (bottomAnchored && popover.isVisible()) { const nb = popover.getBounds(); popover.setPosition(bounds.x, bounds.y + bounds.height - nb.height, false); }
});

// ---- açılış
app.whenReady().then(async () => {
  const dir = app.getPath('userData');
  store = new Store(dir); settings = new Settings(dir);
  makePopover();
  tray = new Tray(nativeImage.createEmpty());
  if (process.platform !== 'darwin') tray.setImage(await drawIcon('…', '#6e6e73'));
  tray.setToolTip('Ullage');
  tray.on('click', togglePopover);
  tray.on('right-click', () => tray.popUpContextMenu(Menu.buildFromTemplate([
    { label: 'Kullanım', click: () => openDashboard('usage') }, { label: 'Ayarlar', click: () => openDashboard('providers') },
    { label: 'Yenile', click: () => doRefresh(true) }, { type: 'separator' }, { label: 'Çıkış', click: () => app.quit() },
  ])));
  await doRefresh(false);
  restartTimer();
  if (SHOTS) require('./shots').run({ SHOTS, app, drawIcon, popover: () => popover, openDashboard: (p) => { openDashboard(p); return dashboard; }, settings, broadcast, placePopover });
});

app.on('window-all-closed', (e) => e.preventDefault());
app.on('before-quit', () => { if (store) store.save(true); });
