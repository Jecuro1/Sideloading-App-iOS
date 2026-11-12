'use strict';

const { Usbmux, utilities } = require('appium-ios-device');
const { getDefaultSocket } = require('appium-ios-device/build/lib/usbmux');
const { withTimeout } = require('./util');

const MODEL_NAMES = {
  'iPhone12,1': 'iPhone 11', 'iPhone12,3': 'iPhone 11 Pro', 'iPhone12,5': 'iPhone 11 Pro Max',
  'iPhone12,8': 'iPhone SE (2. Gen.)',
  'iPhone13,1': 'iPhone 12 mini', 'iPhone13,2': 'iPhone 12', 'iPhone13,3': 'iPhone 12 Pro',
  'iPhone13,4': 'iPhone 12 Pro Max',
  'iPhone14,4': 'iPhone 13 mini', 'iPhone14,5': 'iPhone 13', 'iPhone14,2': 'iPhone 13 Pro',
  'iPhone14,3': 'iPhone 13 Pro Max', 'iPhone14,6': 'iPhone SE (3. Gen.)',
  'iPhone14,7': 'iPhone 14', 'iPhone14,8': 'iPhone 14 Plus', 'iPhone15,2': 'iPhone 14 Pro',
  'iPhone15,3': 'iPhone 14 Pro Max',
  'iPhone15,4': 'iPhone 15', 'iPhone15,5': 'iPhone 15 Plus', 'iPhone16,1': 'iPhone 15 Pro',
  'iPhone16,2': 'iPhone 15 Pro Max',
  'iPhone17,3': 'iPhone 16', 'iPhone17,4': 'iPhone 16 Plus', 'iPhone17,1': 'iPhone 16 Pro',
  'iPhone17,2': 'iPhone 16 Pro Max', 'iPhone17,5': 'iPhone 16e',
};

const infoCache = new Map(); // udid -> { at, info }

function serviceHint() {
  return process.platform === 'win32'
    ? 'Apple-Gerätedienst nicht gefunden. Installiere „Apple Devices“ aus dem Microsoft Store (oder iTunes).'
    : 'Apple-Gerätedienst (usbmuxd) nicht erreichbar.';
}

async function rawDeviceList() {
  const socket = await getDefaultSocket({ timeout: 3000 });
  const usbmux = new Usbmux(socket);
  try {
    return await usbmux.listDevices(4000);
  } finally {
    usbmux.close();
  }
}

async function describe(udid) {
  const cached = infoCache.get(udid);
  if (cached && Date.now() - cached.at < 30000) return cached.info;
  const info = await withTimeout(utilities.getDeviceInfo(udid), 6000, 'Gerät antwortet nicht');
  infoCache.set(udid, { at: Date.now(), info });
  return info;
}

/** Lists iPhones/iPads connected via USB or Wi‑Fi. */
async function listDevices() {
  let raw;
  try {
    raw = await rawDeviceList();
  } catch (err) {
    return { devices: [], error: serviceHint() };
  }

  const byUdid = new Map();
  for (const entry of raw) {
    const props = entry.Properties || {};
    const udid = props.SerialNumber;
    if (!udid) continue;
    const connection = props.ConnectionType === 'Network' ? 'wifi' : 'usb';
    const existing = byUdid.get(udid);
    if (!existing || (existing.connection === 'wifi' && connection === 'usb')) {
      byUdid.set(udid, { udid, connection });
    }
  }

  const devices = [];
  for (const { udid, connection } of byUdid.values()) {
    const device = {
      id: udid,
      udid,
      connection,
      name: 'iPhone',
      model: '',
      osVersion: '',
      deviceClass: 'iPhone',
      needsTrust: false,
    };
    try {
      const info = await describe(udid);
      device.name = info.DeviceName || device.name;
      device.osVersion = info.ProductVersion || '';
      device.deviceClass = info.DeviceClass || 'iPhone';
      device.model = MODEL_NAMES[info.ProductType] || info.ProductType || '';
    } catch {
      device.needsTrust = true;
      device.name = 'Gerät nicht gekoppelt';
    }
    devices.push(device);
  }

  devices.sort((a, b) => {
    if (a.needsTrust !== b.needsTrust) return a.needsTrust ? 1 : -1;
    if (a.connection !== b.connection) return a.connection === 'usb' ? -1 : 1;
    return a.name.localeCompare(b.name);
  });
  return { devices, error: null };
}

module.exports = { listDevices, serviceHint };
