'use strict';

const { contextBridge, ipcRenderer, webUtils } = require('electron');

contextBridge.exposeInMainWorld('ipabeam', {
  platform: process.platform,
  getSettings: () => ipcRenderer.invoke('settings:get'),
  setSettings: (patch) => ipcRenderer.invoke('settings:set', patch),
  toolStatus: () => ipcRenderer.invoke('tools:status'),
  listDevices: () => ipcRenderer.invoke('devices:list'),
  pickIpa: () => ipcRenderer.invoke('ipa:pick'),
  inspectIpa: (file) => ipcRenderer.invoke('ipa:inspect', file),
  removeRecent: (file) => ipcRenderer.invoke('recents:remove', file),
  recentsExist: (files) => ipcRenderer.invoke('recents:exists', files),
  pickFile: (kind) => ipcRenderer.invoke('file:pick', kind),
  readProfile: (file) => ipcRenderer.invoke('profile:read', file),
  reveal: (file) => ipcRenderer.invoke('shell:reveal', file),
  openExternal: (url) => ipcRenderer.invoke('shell:open', url),
  startInstall: (payload) => ipcRenderer.invoke('install:start', payload),
  cancelInstall: () => ipcRenderer.invoke('install:cancel'),
  pathForFile: (file) => webUtils.getPathForFile(file),
  onInstallEvent: (callback) => {
    const listener = (_e, payload) => callback(payload);
    ipcRenderer.on('install:event', listener);
    return () => ipcRenderer.removeListener('install:event', listener);
  },
  onOpenIpa: (callback) => {
    ipcRenderer.on('ipa:open', (_e, file) => callback(file));
  },
});
