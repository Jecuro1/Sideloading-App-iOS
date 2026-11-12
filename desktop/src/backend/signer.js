'use strict';

const fs = require('fs');
const plist = require('plist');
const { run } = require('./util');

/** Reads the readable XML part of a .mobileprovision file. */
function readProfile(file) {
  const buffer = fs.readFileSync(file);
  const start = buffer.indexOf('<?xml');
  const end = buffer.indexOf('</plist>');
  if (start < 0 || end < 0) throw new Error('Das Provisioning-Profil konnte nicht gelesen werden.');
  const data = plist.parse(buffer.subarray(start, end + 8).toString('utf8'));
  const entitlements = data.Entitlements || {};
  const teamId = (data.TeamIdentifier && data.TeamIdentifier[0]) || entitlements['com.apple.developer.team-identifier'] || '';
  const appId = entitlements['application-identifier'] || `${teamId}.*`;
  const pattern = appId.startsWith(`${teamId}.`) ? appId.slice(teamId.length + 1) : appId;
  const expiration = data.ExpirationDate ? new Date(data.ExpirationDate) : null;
  return {
    path: file,
    name: data.Name || file.split(/[\\/]/).pop(),
    teamName: data.TeamName || '',
    teamId,
    bundlePattern: pattern,
    expiration: expiration ? expiration.toISOString() : null,
    expired: expiration ? expiration < new Date() : false,
    devices: data.ProvisionedDevices || [],
    allDevices: !!data.ProvisionsAllDevices,
  };
}

function profileIncludes(profile, udid) {
  if (!profile || profile.allDevices || !udid) return true;
  return profile.devices.some((d) => d.toLowerCase() === udid.toLowerCase());
}

/**
 * Re-signs an IPA with zsign (works on Windows and macOS).
 * The password is passed to zsign only and never written to the log.
 */
async function signIpa({ zsign, input, output, p12, password, profile, bundleId, removeExtensions, onLog, signal }) {
  if (!zsign) throw new Error('zsign wurde nicht gefunden (Einstellungen → Signierung).');
  const args = ['-k', p12, '-p', password || '', '-m', profile, '-o', output, '-z', '1'];
  if (bundleId) args.push('-b', bundleId);
  if (removeExtensions) args.push('-E', '-W');
  args.push(input);

  onLog(`zsign ${bundleId ? `-b ${bundleId} ` : ''}→ ${output.split(/[\\/]/).pop()}`);
  const result = await run(zsign, args, {
    signal,
    onLine: (line) => onLog(line.replace(password || '\u0000', '••••')),
  });
  if (result.code !== 0 || !fs.existsSync(output)) {
    const detail = (result.stderr || result.stdout).trim().split('\n').slice(-6).join('\n');
    throw new Error(`Signieren fehlgeschlagen (Code ${result.code}).\n${detail.replace(password || '\u0000', '••••')}`);
  }
}

module.exports = { readProfile, profileIncludes, signIpa };
