'use strict';
// Claude Code her cevaptan sonra durum satırı komutuna oturum bilgisini (5 saatlik ve haftalık limit dahil) verir.
// Ullage bu bilgiyi bir dosyaya yazan küçük bir betiği Claude Code ayarlarına ekler ve dosyayı okur:
// ağ yok, hız sınırı yok. Yalnızca Claude Code çalışırken güncellenir. (Mac karşılığı: macos/Sources/AILimit/StatusLine.swift)
const fs = require('fs');
const os = require('os');
const path = require('path');
const { isoMs } = require('./util');

const SCRIPT_NAME = 'statusline.ps1';
const DATA_NAME = 'claude-status.json';

// Betik yalnızca ASCII: Windows PowerShell 5.1 BOM'suz dosyayı ANSI okur.
// Girdi baytları olduğu gibi kopyalanır (metne çevrilmez), böylece Türkçe karakterler bozulmaz. Ekrana bir şey basmaz.
const SCRIPT_TEXT = [
  '# Ullage: copies the status line input of Claude Code (rate limits included) to claude-status.json next to this script.',
  '# It prints nothing. Bytes are copied as they are, so non-ASCII characters stay intact.',
  'try {',
  '  $ms = New-Object System.IO.MemoryStream',
  '  [Console]::OpenStandardInput().CopyTo($ms)',
  `  $tmp = Join-Path $PSScriptRoot '${DATA_NAME}.tmp'`,
  '  [System.IO.File]::WriteAllBytes($tmp, $ms.ToArray())',
  `  Move-Item -Force -LiteralPath $tmp -Destination (Join-Path $PSScriptRoot '${DATA_NAME}')`,
  '} catch { }',
  '',
].join('\r\n');

const defaultSettingsFile = () => path.join(os.homedir(), '.claude', 'settings.json');
const scriptPath = (dir) => path.join(dir, SCRIPT_NAME);

/** Claude Code komutu Windows'ta Git Bash üzerinden çalıştırır (denendi). Yolda boşluk olabileceği için yol tırnak içinde,
 *  ters eğik çizgi yerine düz eğik çizgiyle yazılır; bu hem Git Bash'te hem cmd'de hem PowerShell'de çalışır. */
function commandFor(dir) {
  return `powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "${scriptPath(dir).replace(/\\/g, '/')}"`;
}

function readSettings(settingsFile) {
  if (!fs.existsSync(settingsFile)) return { obj: {}, existed: false };
  try { return { obj: JSON.parse(fs.readFileSync(settingsFile, 'utf8').replace(/^﻿/, '')), existed: true }; } catch { return null; }
}

const statusCommandOf = (obj) => (obj && obj.statusLine && typeof obj.statusLine.command === 'string' ? obj.statusLine.command : null);

/** { installed: bizim komut tanımlı mı, other: başka bir durum satırı tanımlı mı } */
function state(dir, settingsFile = defaultSettingsFile()) {
  const s = readSettings(settingsFile);
  const cmd = s && statusCommandOf(s.obj);
  return { installed: cmd === commandFor(dir), other: !!cmd && cmd !== commandFor(dir) };
}

function writeJson(file, obj) {
  const tmp = file + '.tmp';
  fs.writeFileSync(tmp, JSON.stringify(obj, null, 2) + '\n');
  fs.renameSync(tmp, file);
}

/** Betiği yazar ve Claude Code ayarlarına ekler. Değişmeden önce ayar dosyasının yedeği alınır. Dönen metin hata mesajıdır. */
function install(dir, settingsFile = defaultSettingsFile()) {
  const s = readSettings(settingsFile);
  if (!s) return 'settings.json okunamadı, dokunulmadı';
  const cmd = statusCommandOf(s.obj);
  if (cmd && cmd !== commandFor(dir)) return 'Başka bir durum satırı tanımlı, değiştirilmedi';
  try {
    fs.mkdirSync(dir, { recursive: true });
    fs.writeFileSync(scriptPath(dir), SCRIPT_TEXT);
    fs.mkdirSync(path.dirname(settingsFile), { recursive: true });
    const backup = settingsFile + '.ullage-yedek';
    if (s.existed && !fs.existsSync(backup)) fs.copyFileSync(settingsFile, backup);
    writeJson(settingsFile, { ...s.obj, statusLine: { type: 'command', command: commandFor(dir), padding: 0 } });
  } catch (e) { return e.message; }
  return null;
}

/** Yalnızca bizim eklediğimiz tanımı kaldırır. */
function uninstall(dir, settingsFile = defaultSettingsFile()) {
  const s = readSettings(settingsFile);
  if (!s || statusCommandOf(s.obj) !== commandFor(dir)) return;
  const { statusLine, ...rest } = s.obj;
  try { writeJson(settingsFile, rest); } catch { /* yoksay */ }
}

/** Durum satırı girdisinden limitleri çıkarır: kalan = 1 - used_percentage/100, resets_at saniye (ya da ms, ISO metin). */
function parseStatus(obj, at) {
  const rl = obj && obj.rate_limits;
  if (!rl || typeof rl !== 'object') return null;
  const win = (k) => {
    const w = rl[k];
    if (!w || typeof w.used_percentage !== 'number') return null;
    const r = w.resets_at;
    const reset = typeof r === 'number' ? (r > 1e11 ? r : r * 1000) : typeof r === 'string' ? isoMs(r) : null;
    return { left: Math.max(0, Math.min(1, 1 - w.used_percentage / 100)), reset };
  };
  const five = win('five_hour'), week = win('seven_day');
  if (!five && !week) return null;
  return { at, five: five && five.left, week: week && week.left, fiveReset: five && five.reset, weekReset: week && week.reset, src: 'statusline' };
}

/** Dosyadaki son oturum bilgisinden limitleri okur; `at` dosyanın son yazılma zamanıdır. */
function read(dir) {
  const file = path.join(dir, DATA_NAME);
  try {
    const st = fs.statSync(file);
    return parseStatus(JSON.parse(fs.readFileSync(file, 'utf8').replace(/^﻿/, '')), st.mtimeMs);
  } catch { return null; }
}

module.exports = { install, uninstall, state, read, parseStatus, commandFor, SCRIPT_NAME, DATA_NAME };
