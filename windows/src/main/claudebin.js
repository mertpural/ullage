'use strict';
// `claude` komutunu bulur: önce PATH'te, yoksa Claude Desktop uygulamasının kendi içindeki claude.exe'yi arar
// (Mac karşılığı: macos/Sources/AILimit/Automation.swift içindeki desktopBundled).
// Windows'ta Desktop'ın Claude Code'u şurada olabilir (sürüm klasörleri; en yüksek sürüm seçilir):
//   %APPDATA%\Claude\claude-code\<sürüm>\...\claude.exe
//   %LOCALAPPDATA%\Claude-Data\<paket>\claude-code\<sürüm>\...\claude.exe   (Mağaza/MSIX kurulumu, bu bilgisayardaki yer)
//   %LOCALAPPDATA%\Packages\Claude_*\LocalCache\Roaming\Claude\claude-code\<sürüm>\...\claude.exe
const fs = require('fs');
const path = require('path');

const list = (dir) => { try { return fs.readdirSync(dir); } catch { return []; } };

/** PATH'te `claude` (claude.exe, claude.cmd ...) var mı? */
function onPath(env = process.env) {
  const win = process.platform === 'win32';
  const exts = win ? (env.PATHEXT || '.EXE;.CMD;.BAT;.COM').split(';').map((e) => e.toLowerCase()) : [''];
  for (const d of (env.PATH || env.Path || '').split(win ? ';' : ':')) {
    if (!d) continue;
    for (const e of exts) if (fs.existsSync(path.join(d, 'claude' + e))) return true;
  }
  return false;
}

/** "2.1.10" > "2.1.5" (sayısal karşılaştırma, metin sırası değil). */
function cmpVersion(a, b) {
  const pa = String(a).split('.').map((x) => parseInt(x, 10) || 0), pb = String(b).split('.').map((x) => parseInt(x, 10) || 0);
  for (let i = 0; i < Math.max(pa.length, pb.length); i++) { const d = (pa[i] || 0) - (pb[i] || 0); if (d) return d; }
  return 0;
}

/** Klasörün altında (en çok `depth` seviye) claude.exe arar. */
function findExe(dir, depth) {
  for (const name of list(dir)) {
    const p = path.join(dir, name);
    if (name.toLowerCase() === 'claude.exe') return p;
  }
  if (depth <= 0) return null;
  for (const name of list(dir)) {
    const p = path.join(dir, name);
    let isDir = false; try { isDir = fs.statSync(p).isDirectory(); } catch { /* yoksay */ }
    if (isDir) { const r = findExe(p, depth - 1); if (r) return r; }
  }
  return null;
}

/** Claude Desktop'ın paketlediği claude.exe (en yüksek sürüm), yoksa null. */
function desktopBundled(env = process.env) {
  const bases = [];
  if (env.APPDATA) bases.push(path.join(env.APPDATA, 'Claude'));
  if (env.LOCALAPPDATA) {
    const local = env.LOCALAPPDATA;
    bases.push(path.join(local, 'Claude'));
    for (const sub of list(path.join(local, 'Claude-Data'))) bases.push(path.join(local, 'Claude-Data', sub));
    for (const sub of list(path.join(local, 'Packages'))) if (/^Claude_/i.test(sub)) bases.push(path.join(local, 'Packages', sub, 'LocalCache', 'Roaming', 'Claude'));
  }
  let best = null;
  for (const b of bases) {
    const root = path.join(b, 'claude-code');
    for (const v of list(root)) {
      if (!/^\d+(\.\d+)+/.test(v)) continue;
      if (best && cmpVersion(v, best.version) <= 0) continue;
      const exe = findExe(path.join(root, v), 3);
      if (exe) best = { version: v, exe };
    }
  }
  return best ? best.exe : null;
}

let cache = null; // { at, value }
/** Çalıştırma bilgisi: { file, shell, kind } ya da bulunamadıysa null. Sonuç kısa süre saklanır. */
function resolve(env = process.env) {
  const now = Date.now();
  if (env === process.env && cache && now - cache.at < (cache.value ? 10 * 60 * 1000 : 60 * 1000)) return cache.value;
  let value = null;
  if (onPath(env)) value = { file: 'claude', shell: process.platform === 'win32', kind: 'path' }; // Windows'ta .cmd olabilir, kabuk gerekir
  else { const exe = desktopBundled(env); if (exe) value = { file: exe, shell: false, kind: 'desktop' }; }
  if (env === process.env) cache = { at: now, value };
  return value;
}

/** Çalıştırma yöntemi: PATH'teki `claude` Windows'ta çoğunlukla bir .cmd dosyasıdır, bu yüzden kabuk üzerinden tek komut metniyle
 *  (boş değerler ve boşluklu argümanlar tırnaklı) çalıştırılır. Claude Desktop'ın claude.exe'si doğrudan, argüman dizisiyle çalışır.
 *  Dönen: [dosya, argümanlar, seçenekler] */
function spec(bin, args) {
  if (!bin.shell) return [bin.file, args, { shell: false }];
  const q = (a) => (a === '' || a === '.' || /[\s"]/.test(a) ? `"${a}"` : a);
  return [[bin.file, ...args.map(q)].join(' '), [], { shell: true }];
}

module.exports = { resolve, onPath, desktopBundled, cmpVersion, spec };
