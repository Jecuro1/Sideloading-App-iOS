'use strict';

const path = require('path');
const fs = require('fs');
const { app, BrowserWindow, ipcMain, dialog, shell } = require('electron');

const settingsStore = require('./src/backend/settings');
const tools = require('./src/backend/tools');
const devices = require('./src/backend/devices');
const ipa = require('./src/backend/ipa');
const signer = require('./src/backend/signer');
const { runInstall, friendlyError } = require('./src/backend/installer');

let mainWindow = null;
let settings = null;
let currentJob = null; // { controller }
const pendingOpen = [];

const demoArg = process.argv.find((a) => a.startsWith('--demo='));
const demo = demoArg ? demoArg.split('=')[1] : null;

function ipaFromArgv(argv) {
  return argv.find((a) => /\.ipa$/i.test(a) && fs.existsSync(a));
}

function sendOpen(file) {
  if (!file) return;
  if (mainWindow && mainWindow.webContents && !mainWindow.webContents.isLoading()) {
    mainWindow.webContents.send('ipa:open', file);
  } else {
    pendingOpen.push(file);
  }
}

function createWindow() {
  const isMac = process.platform === 'darwin';
  mainWindow = new BrowserWindow({
    width: 1440,
    height: 900,
    minWidth: 1200,
    minHeight: 780,
    backgroundColor: '#05060e',
    title: 'IPA Beam',
    icon: path.join(__dirname, 'build', 'icon.png'),
    titleBarStyle: 'hidden',
    ...(isMac
      ? { trafficLightPosition: { x: 20, y: 20 } }
      : { titleBarOverlay: { color: '#00000000', symbolColor: '#ffffff', height: 52 } }),
    show: false,
    webPreferences: {
      preload: path.join(__dirname, 'preload.js'),
      contextIsolation: true,
      nodeIntegration: false,
      sandbox: true,
    },
  });

  const query = { platform: process.platform };
  if (demo) query.demo = demo;
  mainWindow.loadFile(path.join(__dirname, 'src', 'renderer', 'index.html'), { query });
  mainWindow.once('ready-to-show', () => mainWindow.show());
  mainWindow.webContents.on('did-finish-load', () => {
    while (pendingOpen.length) mainWindow.webContents.send('ipa:open', pendingOpen.shift());
  });
  // Never navigate away from the app; open external links in the browser.
  mainWindow.webContents.setWindowOpenHandler(({ url }) => {
    if (/^https:\/\//.test(url)) shell.openExternal(url);
    return { action: 'deny' };
  });
  mainWindow.webContents.on('will-navigate', (event) => event.preventDefault());
}

// Single instance: a second launch (e.g. double-clicking an .ipa on Windows) forwards the file.
if (!app.requestSingleInstanceLock()) {
  app.quit();
} else {
  app.on('second-instance', (_event, argv) => {
    sendOpen(ipaFromArgv(argv));
    if (mainWindow) {
      if (mainWindow.isMinimized()) mainWindow.restore();
      mainWindow.focus();
    }
  });

  app.on('open-file', (event, file) => {
    event.preventDefault();
    sendOpen(file);
  });

  app.whenReady().then(() => {
    settings = settingsStore.load();
    registerIpc();
    createWindow();
    sendOpen(ipaFromArgv(process.argv));
    app.on('activate', () => {
      if (BrowserWindow.getAllWindows().length === 0) createWindow();
    });
  });

  app.on('window-all-closed', () => app.quit());
}

function persist() {
  settingsStore.save(settings);
  return settingsStore.publicView(settings);
}

function registerIpc() {
  ipcMain.handle('settings:get', () => settingsStore.publicView(settings));

  ipcMain.handle('settings:set', (_e, patch) => {
    const allowed = ['signingEnabled', 'p12Path', 'profilePath', 'bundleId', 'zsignPath'];
    for (const key of allowed) {
      if (patch && Object.prototype.hasOwnProperty.call(patch, key)) settings[key] = patch[key];
    }
    if (patch && typeof patch.password === 'string') settingsStore.setPassword(settings, patch.password);
    return persist();
  });

  ipcMain.handle('tools:status', () => tools.status(settings));

  ipcMain.handle('devices:list', () => devices.listDevices());

  ipcMain.handle('ipa:pick', async () => {
    const result = await dialog.showOpenDialog(mainWindow, {
      title: 'IPA auswählen',
      properties: ['openFile'],
      filters: [{ name: 'iOS-App', extensions: ['ipa'] }],
    });
    return result.canceled ? null : result.filePaths[0];
  });

  ipcMain.handle('ipa:inspect', async (_e, file) => {
    const info = await ipa.inspect(file);
    settings.recents = [
      { path: info.path, name: info.name, bundleId: info.bundleId, version: info.version, icon: info.icon },
      ...settings.recents.filter((r) => r.path !== info.path),
    ].slice(0, 8);
    persist();
    return info;
  });

  ipcMain.handle('recents:remove', (_e, file) => {
    settings.recents = settings.recents.filter((r) => r.path !== file);
    return persist();
  });

  ipcMain.handle('recents:exists', (_e, files) => files.map((f) => fs.existsSync(f)));

  ipcMain.handle('file:pick', async (_e, kind) => {
    const filters = {
      p12: [{ name: 'Zertifikat', extensions: ['p12', 'pfx'] }],
      profile: [{ name: 'Provisioning-Profil', extensions: ['mobileprovision'] }],
      zsign: [{ name: 'zsign', extensions: process.platform === 'win32' ? ['exe'] : ['*'] }],
    }[kind];
    const result = await dialog.showOpenDialog(mainWindow, { properties: ['openFile'], filters });
    return result.canceled ? null : result.filePaths[0];
  });

  ipcMain.handle('profile:read', (_e, file) => {
    try {
      return signer.readProfile(file);
    } catch (err) {
      return { error: err.message };
    }
  });

  ipcMain.handle('shell:reveal', (_e, file) => shell.showItemInFolder(file));
  ipcMain.handle('shell:open', (_e, url) => {
    if (/^https:\/\//.test(url)) shell.openExternal(url);
  });

  ipcMain.handle('install:start', async (event, { ipaInfo, device }) => {
    if (currentJob) throw new Error('Es läuft bereits eine Installation.');
    const controller = new AbortController();
    currentJob = { controller };
    const emit = (payload) => {
      if (!event.sender.isDestroyed()) event.sender.send('install:event', payload);
    };

    let signing = null;
    if (settings.signingEnabled) {
      signing = {
        p12Path: settings.p12Path,
        password: settingsStore.getPassword(settings),
        profilePath: settings.profilePath,
        bundleId: settings.bundleId,
      };
    }

    try {
      await runInstall({
        ipa: ipaInfo,
        device,
        signing,
        zsign: tools.locate('zsign', settings.zsignPath),
        emit,
        signal: controller.signal,
      });
      emit({ type: 'done', state: 'succeeded' });
    } catch (err) {
      if (controller.signal.aborted || (err && err.name === 'AbortError')) {
        emit({ type: 'done', state: 'cancelled' });
      } else {
        emit({ type: 'done', state: 'failed', message: friendlyError(err) });
      }
    } finally {
      currentJob = null;
    }
    return true;
  });

  ipcMain.handle('install:cancel', () => {
    if (currentJob) currentJob.controller.abort();
  });
}
