'use strict';
const fs = require('fs');
const path = require('path');

const DEFAULTS = {
  enabled: ['claude', 'codex', 'antigravity'],
  theme: 'system',
  tab: 'all',
  interval: 30,        // saniye; 0 = yalnızca elle
  notify: true,
  refreshLogin: true,  // süresi dolan Claude Code oturumunu Claude Code'a yeniletir
  login: false,
  dashPage: 'usage',
  trayStyle: 'logo',   // Windows tepsisi: 'logo' (veri yok, uygulama logosu) | 'bars' (5s ve haftalık çubukları) | 'number' (tek sayı, en düşük)
  widget: false,       // her zaman üstte küçük yüzen pencere
  widgetPos: null,     // { x, y } son konum
  widgetScale: 1,      // widget boyutu: 0.7 ile 1.8 arası çarpan
  usageCache: false,   // Kullanım sayfasında "Cache dahil" seçimi
};

class Settings {
  constructor(dir) {
    this.file = path.join(dir, 'settings.json');
    this.v = { ...DEFAULTS };
    // Dosya başka bir araçla UTF-8 BOM'lu yazılmış olabilir; BOM JSON.parse'ı bozar, ayarlar sessizce sıfırlanırdı.
    try { Object.assign(this.v, JSON.parse(fs.readFileSync(this.file, 'utf8').replace(/^﻿/, ''))); } catch { /* ilk açılış */ }
  }
  patch(p) { Object.assign(this.v, p); try { fs.writeFileSync(this.file, JSON.stringify(this.v, null, 2)); } catch { /* yoksay */ } return this.v; }
}

module.exports = { Settings };
