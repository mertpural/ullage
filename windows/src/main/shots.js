'use strict';
// Geliştirme aracı: popover ve Kullanım penceresinin ekran görüntülerini alır (electron . --shots=KLASÖR).
const fs = require('fs');
const path = require('path');

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

exports.run = async ({ SHOTS, app, drawIcon, popover, openDashboard, settings, broadcast }) => {
  fs.mkdirSync(SHOTS, { recursive: true });
  const snap = async (win, name) => {
    const img = await win.webContents.capturePage();
    fs.writeFileSync(path.join(SHOTS, name + '.png'), img.toPNG());
  };
  for (const [text, color] of [['48', '#d98200'], ['100', '#22a559'], ['9', '#d93025']]) {
    fs.writeFileSync(path.join(SHOTS, `tray_${text}.png`), (await drawIcon(text, color)).toPNG());
  }
  const pop = popover();
  pop.setPosition(60, 60); pop.showInactive();
  const themes = (process.env.SHOT_THEMES || 'system,dark,terminal,sticker,paper,neon,brutal,glass,light').split(',');
  for (const t of themes) {
    settings.patch({ theme: t, tab: 'all' }); broadcast(); await sleep(900);
    await snap(pop, `popover_${t}_all`);
  }
  settings.patch({ theme: 'dark', tab: 'claude' }); broadcast(); await sleep(900); await snap(pop, 'popover_dark_claude');
  settings.patch({ tab: 'antigravity' }); broadcast(); await sleep(900); await snap(pop, 'popover_dark_antigravity');
  pop.hide();
  const pages = (process.env.SHOT_PAGES || 'usage,providers,sync,appearance,automation,about').split(',');
  for (const pg of pages) {
    settings.patch({ theme: process.env.SHOT_DASH_THEME || 'dark' });
    const d = openDashboard(pg); await sleep(1400); await snap(d, `dashboard_${pg}`);
  }
  app.quit();
};
