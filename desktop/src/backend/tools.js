'use strict';

const fs = require('fs');
const net = require('net');
const path = require('path');

const isWin = process.platform === 'win32';
const isMac = process.platform === 'darwin';

function platformDir() {
  if (isWin) return 'win';
  if (isMac) return 'mac';
  return 'linux';
}

function isExecutable(file) {
  try {
    fs.accessSync(file, isWin ? fs.constants.F_OK : fs.constants.X_OK);
    return fs.statSync(file).isFile();
  } catch {
    return false;
  }
}

/** Finds a bundled or installed command line tool. */
function locate(name, override) {
  if (override && isExecutable(override)) return override;
  const exe = isWin ? `${name}.exe` : name;
  const dirs = [];
  if (process.resourcesPath) dirs.push(path.join(process.resourcesPath, 'bin'));
  dirs.push(path.join(__dirname, '..', '..', 'resources', 'bin', platformDir()));
  for (const dir of (process.env.PATH || '').split(path.delimiter)) {
    if (dir) dirs.push(dir);
  }
  if (isMac) dirs.push('/opt/homebrew/bin', '/usr/local/bin');
  for (const dir of dirs) {
    const candidate = path.join(dir, exe);
    if (isExecutable(candidate)) return candidate;
  }
  return null;
}

/** Is Apple's device service (usbmuxd / Apple Mobile Device Service) reachable? */
function usbmuxdReachable() {
  if (!isWin) {
    return Promise.resolve(fs.existsSync('/var/run/usbmuxd'));
  }
  return new Promise((resolve) => {
    const socket = net.createConnection(27015, '127.0.0.1');
    const done = (ok) => {
      socket.destroy();
      resolve(ok);
    };
    socket.setTimeout(1500, () => done(false));
    socket.once('connect', () => done(true));
    socket.once('error', () => done(false));
  });
}

async function status(settings = {}) {
  return {
    platform: process.platform,
    usbmuxd: await usbmuxdReachable(),
    zsign: locate('zsign', settings.zsignPath),
  };
}

module.exports = { locate, status, usbmuxdReachable, isWin, isMac };
