'use strict';

const fs = require('fs');
const yauzl = require('yauzl');
const plist = require('plist');
const bplist = require('bplist-parser');
const { normalizePng } = require('./cgbi');

function openZip(file) {
  return new Promise((resolve, reject) => {
    yauzl.open(file, { lazyEntries: true, autoClose: false }, (err, zip) => (err ? reject(err) : resolve(zip)));
  });
}

function listEntries(zip) {
  return new Promise((resolve, reject) => {
    const entries = [];
    zip.on('entry', (entry) => {
      entries.push(entry);
      zip.readEntry();
    });
    zip.once('end', () => resolve(entries));
    zip.once('error', reject);
    zip.readEntry();
  });
}

function readEntry(zip, entry) {
  return new Promise((resolve, reject) => {
    zip.openReadStream(entry, (err, stream) => {
      if (err) return reject(err);
      const chunks = [];
      stream.on('data', (c) => chunks.push(c));
      stream.on('end', () => resolve(Buffer.concat(chunks)));
      stream.on('error', reject);
    });
  });
}

function parsePlist(buffer) {
  if (buffer.subarray(0, 6).toString('ascii') === 'bplist') {
    return bplist.parseBuffer(buffer)[0];
  }
  return plist.parse(buffer.toString('utf8'));
}

function iconBaseNames(info) {
  const names = [];
  for (const key of ['CFBundleIcons', 'CFBundleIcons~ipad']) {
    const primary = info[key] && info[key].CFBundlePrimaryIcon;
    if (primary) {
      if (Array.isArray(primary.CFBundleIconFiles)) names.push(...primary.CFBundleIconFiles);
      if (primary.CFBundleIconName) names.push(primary.CFBundleIconName);
    }
  }
  if (Array.isArray(info.CFBundleIconFiles)) names.push(...info.CFBundleIconFiles);
  if (info.CFBundleIconFile) names.push(info.CFBundleIconFile);
  names.push('AppIcon');
  return names.map((n) => n.replace(/\.png$/i, '')).filter(Boolean);
}

function iconScore(name) {
  let score = 0;
  if (name.includes('@3x')) score += 30;
  else if (name.includes('@2x')) score += 20;
  if (/60x60|76x76|83\.5/.test(name)) score += 10;
  if (name.includes('~ipad')) score -= 5;
  return score;
}

/** Reads app metadata and icon from an .ipa without extracting it. */
async function inspect(file) {
  const zip = await openZip(file).catch(() => {
    throw new Error('Die Datei ist kein gültiges IPA-Archiv.');
  });
  try {
    const entries = await listEntries(zip);
    const infoEntry = entries.find((e) => /^Payload\/[^/]+\.app\/Info\.plist$/.test(e.fileName));
    if (!infoEntry) throw new Error('Im IPA wurde keine App (Payload/*.app) gefunden.');
    const appDir = infoEntry.fileName.slice(0, -'Info.plist'.length);

    let info;
    try {
      info = parsePlist(await readEntry(zip, infoEntry));
    } catch {
      throw new Error('Die Info.plist der App konnte nicht gelesen werden.');
    }

    const bases = iconBaseNames(info);
    const candidates = entries
      .map((e) => e)
      .filter((e) => {
        if (!e.fileName.startsWith(appDir) || !/\.png$/i.test(e.fileName)) return false;
        const rest = e.fileName.slice(appDir.length);
        return !rest.includes('/') && bases.some((b) => rest.startsWith(b));
      })
      .sort((a, b) => iconScore(b.fileName) - iconScore(a.fileName));

    let icon = null;
    if (candidates.length) {
      try {
        const png = normalizePng(await readEntry(zip, candidates[0]));
        icon = `data:image/png;base64,${png.toString('base64')}`;
      } catch {
        icon = null;
      }
    }

    const hasExtensions = entries.some((e) =>
      ['PlugIns/', 'Watch/', 'Extensions/'].some((dir) => e.fileName.startsWith(appDir + dir))
    );

    return {
      path: file,
      name: info.CFBundleDisplayName || info.CFBundleName || file.split(/[\\/]/).pop().replace(/\.ipa$/i, ''),
      bundleId: info.CFBundleIdentifier || 'unbekannt',
      version: info.CFBundleShortVersionString || '1.0',
      build: info.CFBundleVersion || '',
      minOS: info.MinimumOSVersion || null,
      size: fs.statSync(file).size,
      icon,
      hasExtensions,
    };
  } finally {
    zip.close();
  }
}

module.exports = { inspect, parsePlist };
