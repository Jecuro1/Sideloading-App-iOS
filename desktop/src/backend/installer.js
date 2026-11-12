'use strict';

const fs = require('fs');
const os = require('os');
const path = require('path');
const { Transform } = require('stream');
const { pipeline } = require('stream/promises');
const { services } = require('appium-ios-device');
const { signIpa } = require('./signer');

function abortError() {
  const err = new Error('Abgebrochen');
  err.name = 'AbortError';
  return err;
}

/** Uploads the IPA via AFC into PublicStaging and returns the device-side path. */
async function upload(udid, ipaPath, { onProgress, onLog, signal }) {
  const afc = await services.startAfcService(udid);
  const fileName = `ipabeam-${Date.now()}.ipa`;
  try {
    try {
      await afc.createDirectory('/PublicStaging');
    } catch {
      // already exists
    }
    const total = fs.statSync(ipaPath).size;
    let sent = 0;
    let lastReport = 0;
    onLog(`Übertrage ${(total / 1024 / 1024).toFixed(1)} MB …`);

    const counter = new Transform({
      transform(chunk, _enc, done) {
        if (signal.aborted) return done(abortError());
        sent += chunk.length;
        const now = Date.now();
        if (now - lastReport > 120 || sent === total) {
          lastReport = now;
          onProgress(sent / total);
        }
        done(null, chunk);
      },
    });

    const remote = await afc.createWriteStream(`/PublicStaging/${fileName}`, { autoDestroy: true });
    const closed = new Promise((resolve) => remote.once('close', resolve));
    await pipeline(fs.createReadStream(ipaPath, { highWaterMark: 1 << 20 }), counter, remote);
    await Promise.race([closed, new Promise((r) => setTimeout(r, 3000))]);
    onLog('Upload abgeschlossen.');
  } finally {
    afc.close();
  }
  return `PublicStaging/${fileName}`;
}

/** Asks installd to install the uploaded package, streaming progress. */
async function installPackage(udid, remotePath, bundleId, { onProgress, onLog, signal }) {
  const proxy = await services.startInstallationProxyService(udid);
  const plistService = proxy._plistService;
  const onAbort = () => proxy.close();
  signal.addEventListener('abort', onAbort, { once: true });
  try {
    plistService.sendPlist({
      Command: 'Install',
      PackagePath: remotePath,
      ClientOptions: bundleId ? { CFBundleIdentifier: bundleId } : {},
    });
    let lastStatus = '';
    for (;;) {
      if (signal.aborted) throw abortError();
      const message = await plistService.receivePlist(180000);
      if (message.Error) {
        const description = message.ErrorDescription ? `: ${message.ErrorDescription}` : '';
        throw new Error(`${message.Error}${description}`);
      }
      if (message.Status && message.Status !== lastStatus) {
        lastStatus = message.Status;
        onLog(`Install: ${message.Status}${message.PercentComplete != null ? ` (${message.PercentComplete}%)` : ''}`);
      }
      if (typeof message.PercentComplete === 'number') onProgress(message.PercentComplete / 100);
      if (message.Status === 'Complete') break;
    }
  } finally {
    signal.removeEventListener('abort', onAbort);
    proxy.close();
  }
}

/**
 * Full pipeline: (optional) sign → upload → install.
 * `emit(event)` receives { type: 'step' | 'progress' | 'log', ... }.
 */
async function runInstall({ ipa, device, signing, zsign, emit, signal }) {
  const log = (text, kind = 'info') => emit({ type: 'log', text, kind });
  const workDir = fs.mkdtempSync(path.join(os.tmpdir(), 'ipabeam-'));
  try {
    log(`${ipa.name} v${ipa.version} → ${device.name} (${device.connection === 'wifi' ? 'WLAN' : 'USB‑C'})`);

    // 1. Prepare / sign
    emit({ type: 'step', step: 'prepare', state: 'running' });
    let packagePath = ipa.path;
    emit({ type: 'step', step: 'prepare', state: 'done' });

    if (signing) {
      emit({ type: 'step', step: 'sign', state: 'running' });
      const output = path.join(workDir, 'signed.ipa');
      await signIpa({
        zsign,
        input: ipa.path,
        output,
        p12: signing.p12Path,
        password: signing.password,
        profile: signing.profilePath,
        bundleId: signing.bundleId || null,
        onLog: log,
        signal,
      });
      packagePath = output;
      log('Signatur erstellt ✓');
      emit({ type: 'step', step: 'sign', state: 'done' });
    } else {
      emit({ type: 'step', step: 'sign', state: 'skipped' });
      log('Signierung übersprungen – Original-Signatur wird verwendet.');
    }

    // 2. Upload + install
    emit({ type: 'step', step: 'install', state: 'running' });
    const remotePath = await upload(device.udid, packagePath, {
      signal,
      onLog: log,
      onProgress: (p) => emit({ type: 'progress', value: p * 0.55 }),
    });
    if (signal.aborted) throw abortError();
    await installPackage(device.udid, remotePath, signing && signing.bundleId ? signing.bundleId : ipa.bundleId, {
      signal,
      onLog: log,
      onProgress: (p) => emit({ type: 'progress', value: 0.55 + p * 0.45 }),
    });
    emit({ type: 'progress', value: 1 });
    emit({ type: 'step', step: 'install', state: 'done' });
    log(`${ipa.name} wurde erfolgreich auf ${device.name} installiert.`, 'success');
  } finally {
    fs.rmSync(workDir, { recursive: true, force: true });
  }
}

/** Adds helpful hints to common installd errors. */
function friendlyError(err) {
  const message = (err && err.message) || String(err);
  const lower = message.toLowerCase();
  let hint = null;
  if (lower.includes('developer mode') || lower.includes('developermode')) {
    hint = 'Aktiviere auf dem iPhone: Einstellungen → Datenschutz & Sicherheit → Entwicklermodus.';
  } else if (lower.includes('applicationverificationfailed') || lower.includes('signature') || lower.includes('0xe8008015')) {
    hint = 'Die App ist nicht gültig für dieses Gerät signiert. Aktiviere „Neu signieren“ mit Zertifikat (.p12) und Profil, das dein iPhone enthält.';
  } else if (lower.includes('provision') || lower.includes('0xe8008012')) {
    hint = 'Das Provisioning-Profil passt nicht zu App oder Gerät.';
  } else if (lower.includes('could not find the expected device') || lower.includes('econnrefused') || lower.includes('connection was refused')) {
    hint = 'Verbindung zum iPhone verloren. Entsperre das iPhone und prüfe Kabel bzw. WLAN.';
  } else if (lower.includes('pair') || lower.includes('lockdown')) {
    hint = 'Das iPhone vertraut diesem Computer noch nicht. Entsperren und „Vertrauen“ tippen.';
  }
  return hint ? `${message}\n\n💡 ${hint}` : message;
}

module.exports = { runInstall, friendlyError };
