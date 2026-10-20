'use strict';
// Tüm sağlayıcıları okuyup arayüzün kullanacağı tek bir özet üretir.
const claude = require('./providers/claude');
const codex = require('./providers/codex');
const antigravity = require('./providers/antigravity');

const PROVIDERS = ['claude', 'codex', 'gemini', 'antigravity'];

/** 5 saatlik ve haftalık satırlar; havuzlu sağlayıcılarda (Antigravity) en kısıtlayıcı olan. */
function windows(u) {
  const extraMin = (word) => (u.extra || []).filter((r) => r.title.includes(word)).sort((a, b) => a.left - b.left)[0];
  const five = u.fiveHourLeft != null ? { title: '5 saatlik', left: u.fiveHourLeft, reset: u.fiveHourReset } : extraMin('5 saatlik');
  const week = u.weeklyLeft != null ? { title: 'Haftalık', left: u.weeklyLeft, reset: u.weeklyReset } : extraMin('Haftalık');
  const other = (u.extra || []).filter((r) => !r.title.includes('5 saatlik') && !r.title.includes('Haftalık'));
  return { five: five || null, week: week || null, other };
}

async function refreshAll(store, { force = false, refreshLogin = true } = {}) {
  if (force) claude.invalidate(store);
  const usage = {};
  const safe = async (name, fn, fallback) => { try { usage[name] = await fn(); } catch (e) { usage[name] = { limitConfidence: 'none', tokenConfidence: 'none', extra: [], notes: [`${fallback}: ${e.message}`] }; } };
  await safe('claude', () => claude.read(store, { refreshLogin }), 'Claude okunamadı');
  await safe('codex', async () => codex.read(store), 'Codex okunamadı');
  await safe('antigravity', () => antigravity.read(store), 'Antigravity okunamadı');
  usage.gemini = { limitConfidence: 'none', tokenConfidence: 'none', extra: [], notes: ['Gemini Windows sürümünde henüz yok.'] };
  for (const p of PROVIDERS) usage[p].win = windows(usage[p]);
  store.save();
  const daily = {};
  for (const p of PROVIDERS) daily[p] = store.dailyTotals(p, 7);
  return { usage, daily, updatedAt: Date.now() };
}

module.exports = { refreshAll, PROVIDERS, windows };
