'use strict';

/* Demo data + a stand-in API so the UI can be shown without a device
   (used for screenshots: index.html?demo=ready|installing|success|failed|drop|idle|nodevice). */
const DemoData = (() => {
  const GLYPHS = {
    sparkles: '<path d="M12 3l1.9 5.6L19.5 10l-5.6 1.9L12 17.5l-1.9-5.6L4.5 10l5.6-1.4z"/><path d="M19 3v4M17 5h4M5 17v3M3.5 18.5h3"/>',
    brush: '<path d="m9.06 11.9 8.07-8.06a2.85 2.85 0 1 1 4.03 4.03l-8.06 8.08"/><path d="M7.07 14.94c-1.66 0-3 1.35-3 3.02 0 1.33-2.5 1.52-2 2.02 1.08 1.1 2.49 2.02 4 2.02 2.2 0 4-1.8 4-4.04a3.01 3.01 0 0 0-3-3.02z"/>',
    play: '<path d="M7 4v16l13-8z" fill="#fff"/>',
    map: '<path d="M14.1 6 9.9 4 3 6.8v13.2l6.9-2.8 4.2 2 6.9-2.8V3.2z"/><path d="M9.9 4v13.2M14.1 6v13.2"/>',
  };

  function svgIcon(c1, c2, glyph) {
    const svg = `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 180 180">
      <defs><linearGradient id="g" x1="0" y1="0" x2="1" y2="1">
      <stop offset="0" stop-color="${c1}"/><stop offset="1" stop-color="${c2}"/></linearGradient></defs>
      <rect width="180" height="180" fill="url(#g)"/>
      <circle cx="145" cy="25" r="75" fill="#fff" opacity=".16"/>
      <g transform="translate(40 40) scale(4.17)" fill="none" stroke="#fff" stroke-width="1.8"
         stroke-linecap="round" stroke-linejoin="round">${GLYPHS[glyph]}</g></svg>`;
    return `data:image/svg+xml;base64,${btoa(svg)}`;
  }

  const icons = {
    nebula: svgIcon('#b06bff', '#4b1aa8', 'sparkles'),
    pixel: svgIcon('#ff8a4c', '#c2185b', 'brush'),
    orbit: svgIcon('#38d9ff', '#2350d6', 'play'),
    trail: svgIcon('#5be38f', '#13795b', 'map'),
  };

  const udid = '00008140-001A2B3C4D5E801E';

  function devices(scenario) {
    if (scenario === 'nodevice') return [];
    return [
      { id: udid, udid, name: 'iPhone von Alex', model: 'iPhone 16 Pro', osVersion: '18.2', deviceClass: 'iPhone', connection: 'usb', needsTrust: false },
      { id: 'ipad', udid: '00008103-000A11B22C33D44E', name: 'iPad Air', model: 'iPad Air (M2)', osVersion: '18.1', deviceClass: 'iPad', connection: 'wifi', needsTrust: false },
    ];
  }

  const settings = {
    signingEnabled: true,
    p12Path: 'C:\\Users\\Alex\\Zertifikate\\AppleDevelopment.p12',
    profilePath: 'C:\\Users\\Alex\\Zertifikate\\IPABeam_Wildcard.mobileprovision',
    bundleId: '',
    zsignPath: '',
    hasPassword: true,
    recents: [
      { path: 'C:\\Users\\Alex\\Downloads\\NebulaNotes.ipa', name: 'Nebula Notes', bundleId: 'com.example.nebulanotes', version: '2.4.1', icon: icons.nebula },
      { path: 'C:\\Users\\Alex\\Downloads\\PixelForge.ipa', name: 'Pixel Forge', bundleId: 'dev.alex.pixelforge', version: '1.0.3', icon: icons.pixel },
      { path: 'C:\\Users\\Alex\\Downloads\\OrbitPlayer.ipa', name: 'Orbit Player', bundleId: 'io.orbit.player', version: '5.2', icon: icons.orbit },
      { path: 'C:\\Users\\Alex\\Downloads\\TrailLog.ipa', name: 'Trail Log', bundleId: 'app.traillog.ios', version: '3.1.0', icon: icons.trail },
    ],
  };

  const profile = {
    name: 'IPA Beam Wildcard', teamName: 'Alex Beispiel', teamId: 'ABCDE12345', bundlePattern: '*',
    expiration: new Date(Date.now() + 290 * 86400000).toISOString(), expired: false, devices: [udid], allDevices: false,
  };

  const ipa = {
    path: 'C:\\Users\\Alex\\Downloads\\NebulaNotes.ipa', name: 'Nebula Notes', bundleId: 'com.example.nebulanotes',
    version: '2.4.1', build: '128', minOS: '17.0', size: 48213000, icon: icons.nebula, hasExtensions: true,
  };

  const baseLog = [
    ['Nebula Notes v2.4.1 → iPhone von Alex (USB‑C)', 'info'],
    ['Vorbereiten', 'step'],
    ['Signieren', 'step'],
    ['zsign → signed.ipa', 'info'],
    ['>>> Signing: NebulaNotes.app …', 'info'],
    ['>>> BundleId: com.example.nebulanotes', 'info'],
    ['Signatur erstellt ✓', 'info'],
    ['Übertragen & installieren', 'step'],
    ['Übertrage 48.2 MB …', 'info'],
    ['Upload abgeschlossen.', 'info'],
    ['Install: CreatingStagingDirectory (5%)', 'info'],
    ['Install: ExtractingPackage (15%)', 'info'],
    ['Install: InspectingPackage (20%)', 'info'],
    ['Install: VerifyingApplication (40%)', 'info'],
    ['Install: InstallingEmbeddedProfile (60%)', 'info'],
  ];

  function job(scenario) {
    if (!['installing', 'success', 'failed'].includes(scenario)) return null;
    const j = {
      appName: ipa.name, deviceName: 'iPhone von Alex', connection: 'usb',
      steps: { prepare: 'done', sign: 'done', install: 'running' },
      progress: 0.76, state: 'running', message: null,
      log: baseLog.map(([text, kind]) => ({ text, kind })),
    };
    if (scenario === 'success') {
      j.steps.install = 'done';
      j.state = 'succeeded';
      j.progress = 1;
      j.log.push({ text: 'Install: Complete', kind: 'info' }, { text: 'Nebula Notes wurde erfolgreich auf iPhone von Alex installiert.', kind: 'success' });
    }
    if (scenario === 'failed') {
      j.steps.install = 'failed';
      j.state = 'failed';
      j.message = 'ApplicationVerificationFailed: Failed to verify code signature of NebulaNotes.app\n\n💡 Die App ist nicht gültig für dieses Gerät signiert. Aktiviere „Neu signieren“ mit Zertifikat (.p12) und Profil, das dein iPhone enthält.';
      j.log.push({ text: j.message.split('\n')[0], kind: 'error' });
    }
    return j;
  }

  function history() {
    return [
      { appName: 'Pixel Forge', deviceName: 'iPad Air', connection: 'wifi', state: 'succeeded', time: '14:12' },
      { appName: 'Orbit Player', deviceName: 'iPhone von Alex', connection: 'usb', state: 'succeeded', time: '11:47' },
    ];
  }

  function createApi(scenario) {
    return {
      platform: 'win32',
      getSettings: async () => ({ ...settings }),
      setSettings: async (patch) => ({ ...settings, ...patch }),
      toolStatus: async () => ({ platform: 'win32', usbmuxd: true, zsign: 'zsign.exe' }),
      listDevices: async () => ({ devices: devices(scenario), error: null }),
      pickIpa: async () => null,
      inspectIpa: async () => ipa,
      removeRecent: async () => settings,
      recentsExist: async (files) => files.map(() => true),
      pickFile: async () => null,
      readProfile: async () => profile,
      reveal: async () => {},
      openExternal: async () => {},
      startInstall: async () => true,
      cancelInstall: async () => {},
      pathForFile: () => '',
      onInstallEvent: () => () => {},
      onOpenIpa: () => {},
    };
  }

  return { createApi, devices, ipa, job, history, profile };
})();
