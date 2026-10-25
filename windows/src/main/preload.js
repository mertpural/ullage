'use strict';
const { contextBridge, ipcRenderer } = require('electron');

contextBridge.exposeInMainWorld('ullage', {
  getState: () => ipcRenderer.invoke('state'),
  onState: (cb) => ipcRenderer.on('state', (_e, s) => cb(s)),
  getHistory: () => ipcRenderer.invoke('history'),
  setSettings: (patch) => ipcRenderer.invoke('settings', patch),
  refresh: (force) => ipcRenderer.invoke('refresh', !!force),
  openDashboard: (page) => ipcRenderer.invoke('dashboard', page),
  resizePopover: (h) => ipcRenderer.send('resize-popover', h),
  quit: () => ipcRenderer.invoke('quit'),
  copyText: (text) => ipcRenderer.invoke('copy-text', text),});
