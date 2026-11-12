'use strict';

const fs = require('fs');
const path = require('path');
const { app, safeStorage } = require('electron');

const DEFAULTS = {
  recents: [],
  signingEnabled: false,
  p12Path: '',
  passwordEncrypted: '',
  profilePath: '',
  bundleId: '',
  zsignPath: '',
  removeExtensions: true,
};

function file() {
  return path.join(app.getPath('userData'), 'settings.json');
}

function load() {
  try {
    return { ...DEFAULTS, ...JSON.parse(fs.readFileSync(file(), 'utf8')) };
  } catch {
    return { ...DEFAULTS };
  }
}

function save(settings) {
  fs.mkdirSync(path.dirname(file()), { recursive: true });
  fs.writeFileSync(file(), JSON.stringify(settings, null, 2));
}

/** Public view for the renderer – never contains the password itself. */
function publicView(settings) {
  const { passwordEncrypted, ...rest } = settings;
  return { ...rest, hasPassword: !!passwordEncrypted };
}

function setPassword(settings, password) {
  if (!password) {
    settings.passwordEncrypted = '';
  } else if (safeStorage.isEncryptionAvailable()) {
    settings.passwordEncrypted = safeStorage.encryptString(password).toString('base64');
  } else {
    settings.passwordEncrypted = `plain:${Buffer.from(password, 'utf8').toString('base64')}`;
  }
}

function getPassword(settings) {
  const value = settings.passwordEncrypted;
  if (!value) return '';
  if (value.startsWith('plain:')) return Buffer.from(value.slice(6), 'base64').toString('utf8');
  try {
    return safeStorage.decryptString(Buffer.from(value, 'base64'));
  } catch {
    return '';
  }
}

module.exports = { load, save, publicView, setPassword, getPassword };
