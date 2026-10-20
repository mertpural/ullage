'use strict';
const fs = require('fs');
const path = require('path');

const DEFAULTS = {
  enabled: ['claude', 'codex', 'antigravity'],
  theme: 'system',
  tab: 'all',
  interval: 30,        // saniye; 0 = yalnızca elle
  notify: true,
  login: false,
  dashPage: 'usage',
};

class Settings {
  constructor(dir) {
    this.file = path.join(dir, 'settings.json');
    this.v = { ...DEFAULTS };
    try { Object.assign(this.v, JSON.parse(fs.readFileSync(this.file, 'utf8'))); } catch { /* ilk açılış */ }
  }
  patch(p) { Object.assign(this.v, p); try { fs.writeFileSync(this.file, JSON.stringify(this.v, null, 2)); } catch { /* yoksay */ } return this.v; }
}

module.exports = { Settings };
