'use strict';

/* global icon, hydrateIcons, DemoData */

const params = new URLSearchParams(location.search);
const demo = params.get('demo');
const api = demo || !window.ipabeam ? DemoData.createApi(demo || 'ready') : window.ipabeam;
const platform = params.get('platform') || api.platform || 'darwin';
const isWin = platform === 'win32';
document.body.classList.add(`platform-${platform}`);

const state = {
  devices: [],
  selectedId: null,
  deviceError: null,
  refreshing: false,
  tools: null,
  ipa: null,
  inspecting: false,
  inspectError: null,
  settings: { recents: [] },
  profile: null,
  recentsExist: {},
  job: null,
  history: [],
};

const $ = (id) => document.getElementById(id);
const esc = (s) => String(s ?? '').replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
const fileName = (p) => String(p || '').split(/[\\/]/).pop();
const fmtSize = (b) => (b >= 1e9 ? `${(b / 1e9).toFixed(2)} GB` : `${(b / 1e6).toFixed(1)} MB`);
const connTitle = (c) => ({ usb: 'USB‑C', wifi: 'WLAN', offline: 'Offline' }[c] || c);
const connIcon = (c) => ({ usb: 'usb', wifi: 'wifi', offline: 'offline' }[c] || 'usb');

function selectedDevice() {
  return state.devices.find((d) => d.id === state.selectedId) || null;
}

function appIconHtml(src, size, glyphSize) {
  const inner = src ? `<img src="${esc(src)}" alt="">` : icon('box', glyphSize || Math.round(size * 0.45));
  return `<div class="app-icon" style="width:${size}px;height:${size}px">${inner}</div>`;
}

function badge(connection) {
  return `<span class="badge ${connection}">${icon(connIcon(connection), 10)}${connTitle(connection)}</span>`;
}

function setHTML(el, html) {
  if (el.__html !== html) {
    el.__html = html;
    el.innerHTML = html;
  }
}

/* ---------------- Derived state ---------------- */

function overallProgress(job) {
  if (!job) return 0;
  if (job.state === 'succeeded') return 1;
  const s = job.steps;
  let p = 0;
  if (s.prepare === 'done') p += 0.05;
  if (s.sign === 'done' || s.sign === 'skipped') p += 0.2;
  else if (s.sign === 'running') p += 0.1;
  if (s.install === 'running' || s.install === 'done' || s.install === 'failed') p += 0.75 * (job.progress || 0);
  return Math.min(p, 0.99);
}

function stageState() {
  if (state.job) {
    if (state.job.state === 'running') return 'installing';
    return state.job.state === 'succeeded' ? 'success' : 'failed';
  }
  const device = selectedDevice();
  if (!device || device.needsTrust) return 'noDevice';
  return state.ipa ? 'ready' : 'waiting';
}

function signingWarning() {
  const s = state.settings;
  if (!s.signingEnabled) return null;
  if (!s.p12Path) return 'Wähle dein Zertifikat (.p12).';
  if (!s.profilePath) return 'Wähle ein Provisioning-Profil (.mobileprovision).';
  if (state.profile && state.profile.error) return state.profile.error;
  if (state.profile && state.profile.expired) return 'Das Profil ist abgelaufen.';
  const device = selectedDevice();
  if (state.profile && device && !state.profile.allDevices &&
      !state.profile.devices.some((u) => u.toLowerCase() === String(device.udid).toLowerCase())) {
    return `„${device.name}“ ist nicht im Profil enthalten – iOS wird die Installation ablehnen.`;
  }
  if (state.tools && !state.tools.zsign) return 'zsign wurde nicht gefunden (Einstellungen).';
  return null;
}

function installBlocker() {
  if (!state.tools) return 'Werkzeuge werden geprüft …';
  if (!state.tools.usbmuxd) {
    return isWin
      ? 'Apple-Gerätedienst fehlt – installiere „Apple Devices“ aus dem Microsoft Store.'
      : 'Apple-Gerätedienst (usbmuxd) ist nicht erreichbar.';
  }
  if (!state.ipa) return 'Wähle zuerst eine IPA-Datei.';
  const device = selectedDevice();
  if (!device) return 'Verbinde dein iPhone per USB‑C oder WLAN.';
  if (device.needsTrust) return 'Tippe auf dem iPhone auf „Vertrauen“, um es zu koppeln.';
  const s = state.settings;
  if (s.signingEnabled && (!s.p12Path || !s.profilePath)) return 'Wähle Zertifikat und Profil für die Signierung.';
  if (s.signingEnabled && state.tools && !state.tools.zsign) return 'zsign fehlt – siehe Einstellungen.';
  return null;
}

/* ---------------- Top bar ---------------- */

function renderTop() {
  const usb = state.devices.filter((d) => d.connection === 'usb' && !d.needsTrust).length;
  const wifi = state.devices.filter((d) => d.connection === 'wifi' && !d.needsTrust).length;
  const item = (cls, ic, title, n, color) => `
    <span class="conn-item ${cls} ${n ? 'on' : ''}">
      <span class="dot ${n ? 'on' : ''}" style="--c:${color}"></span>${icon(ic, 13)}${title}${n ? ` · ${n}` : ''}
    </span>`;
  setHTML($('connSummary'), `${item('usb', 'usb', 'USB‑C', usb, 'var(--cyan)')}<span class="sep"></span>${item('wifi', 'wifi', 'WLAN', wifi, 'var(--success)')}`);
}

/* ---------------- Left panel ---------------- */

function renderLeft() {
  const deviceCards = state.devices.length
    ? `<div class="devices">${state.devices.map((d) => `
        <div class="device ${d.id === state.selectedId ? 'selected neon' : ''} ${d.needsTrust ? 'trust' : ''}"
             data-action="select-device" data-id="${esc(d.id)}" style="border-radius:16px">
          <div class="device-icon">${icon(String(d.deviceClass).toLowerCase().includes('ipad') ? 'ipad' : 'iphone', 20)}</div>
          <div class="device-text">
            <div class="row" style="gap:6px"><span class="device-name">${esc(d.name)}</span><span class="spacer"></span>${badge(d.connection)}</div>
            <span class="device-sub">${d.needsTrust ? 'Vertrauen erforderlich' : esc([d.model, d.osVersion && `iOS ${d.osVersion}`].filter(Boolean).join(' · '))}</span>
          </div>
        </div>`).join('')}</div>`
    : `<div class="radar">
        <div class="radar-anim"><span></span><span></span><span></span><span class="sweep"></span>${icon('iphone', 24)}</div>
        <b style="font-size:13px">Suche nach Geräten …</b>
        <span class="tiny">iPhone per USB‑C anschließen oder im selben WLAN entsperren.</span>
        ${state.deviceError ? `<span class="hint-box" style="--c:var(--warning)">${icon('alert', 14)}<span>${esc(state.deviceError)}</span></span>` : ''}
      </div>`;

  const device = selectedDevice();
  const trust = device && device.needsTrust
    ? `<div class="hint-box">${icon('lock', 14)}<span>iPhone entsperren und „Diesem Computer vertrauen“ tippen${isWin ? ' (Apple Devices muss installiert sein)' : ''}.</span></div>`
    : '';

  const recents = state.settings.recents || [];
  const library = recents.length
    ? `<div class="library scroll">${recents.map((r) => {
        const exists = state.recentsExist[r.path] !== false;
        const current = state.ipa && state.ipa.path === r.path;
        return `<button class="lib-row ${current ? 'current' : ''} ${exists ? '' : 'missing'}" data-action="open-recent" data-path="${esc(r.path)}" title="${esc(r.path)}">
          ${appIconHtml(r.icon, 32)}
          <span class="t"><div class="n">${esc(r.name)}</div><div class="s">v${esc(r.version)} · ${esc(r.bundleId)}</div></span>
          ${current ? `<span class="ok">${icon('check', 14)}</span>` : ''}
        </button>`;
      }).join('')}</div>`
    : '<span class="tiny">Hier erscheinen zuletzt verwendete IPAs.</span>';

  const history = state.history.length
    ? `<div class="label" style="margin-top:8px">${icon('clock')}Verlauf</div>
       <div class="history">${state.history.slice(0, 4).map((h) => `
         <div class="hist-row">
           <span class="st ${h.state === 'succeeded' ? 'ok' : 'bad'}">${icon(h.state === 'succeeded' ? 'check' : 'x', 11)}</span>
           <span style="flex:1;min-width:0"><div style="font-size:12px;font-weight:650">${esc(h.appName)}</div>
           <div class="tiny">${esc(h.deviceName)} · ${esc(h.time)}</div></span>${badge(h.connection)}
         </div>`).join('')}</div>`
    : '';

  const t = state.tools;
  setHTML($('leftPanel'), `
    <div class="row"><span class="label">${icon('radar')}Geräte</span><span class="spacer"></span>
      <span class="count">${state.devices.filter((d) => !d.needsTrust).length}</span></div>
    ${deviceCards}
    ${trust}
    <div class="row" style="margin-top:8px"><span class="label">${icon('layers')}Bibliothek</span><span class="spacer"></span>
      <button class="link-btn" data-action="pick-ipa" title="IPA öffnen">${icon('plus', 13)}</button></div>
    ${library}
    ${history}
    <div class="tool-footer">
      <span><i class="${t && t.usbmuxd ? 'on' : ''}"></i>${isWin ? 'Apple-Gerätedienst' : 'usbmuxd'}</span>
      <span><i class="${t && t.zsign ? 'on' : ''}"></i>zsign</span>
    </div>`);
}

/* ---------------- Stage ---------------- */

const SLOT = 6;
function buildPhone() {
  const color = (i) => {
    const h = ((i * 0.137 + 0.55) % 1) * 360;
    return `linear-gradient(135deg, hsl(${h} 70% 70%), hsl(${(h + 30) % 360} 65% 38%))`;
  };
  $('home').innerHTML = Array.from({ length: 16 }, (_, i) =>
    i === SLOT ? '<i class="slot" id="slot"></i>' : `<i style="background:${color(i)}"></i>`).join('');
  $('dock').innerHTML = Array.from({ length: 4 }, (_, i) => `<i style="background:${color(i + 20)}"></i>`).join('');
}

function renderStage() {
  const st = stageState();
  const stage = $('stage');
  stage.className = `stage ${st === 'noDevice' ? 'no-device' : ''} ${['ready', 'installing', 'success'].includes(st) ? 'active' : ''} ${st === 'installing' ? 'installing' : ''}`;
  const progress = overallProgress(state.job);
  const ipaIcon = (state.ipa && state.ipa.icon) || null;

  // Floating icon
  const floatIcon = $('floatIcon');
  setHTML(floatIcon, state.ipa ? appIconHtml(ipaIcon, 78, 34) : '');
  floatIcon.classList.toggle('hidden', !state.ipa || st === 'success');

  // Glow colour
  const glow = { success: 'rgba(51,235,158,0.55)', failed: 'rgba(255,84,105,0.55)', noDevice: 'rgba(110,97,255,0.25)' }[st] || 'rgba(110,97,255,0.55)';
  $('phone').style.setProperty('--glow', glow);
  $('phoneGlow').style.setProperty('--glow', glow);

  // Home-screen slot
  const slot = $('slot');
  slot.className = 'slot';
  slot.style.background = '';
  let slotHtml = '';
  if (st === 'ready') slot.classList.add('ready');
  else if (st === 'installing') {
    slot.classList.add('installing');
    slotHtml = `${appIconHtml(ipaIcon, 0)}<span class="pie" style="--p:${Math.round(progress * 100)}"></span>`;
  } else if (st === 'success') {
    slot.classList.add('success');
    slotHtml = appIconHtml(ipaIcon, 0);
  } else {
    slot.style.background = 'linear-gradient(135deg, hsl(250 70% 70%), hsl(280 65% 38%))';
  }
  setHTML(slot, slotHtml.replace(/width:0px;height:0px/g, ''));

  // Screen overlay
  let overlay = '';
  const job = state.job;
  if (st === 'noDevice') {
    overlay = `<div class="offline"><div class="icons">${icon('usb')}${icon('wifi')}</div>
      <b>Kein iPhone verbunden</b><span>USB‑C anstecken oder<br>im selben WLAN entsperren</span></div>`;
  } else if (st === 'waiting') {
    overlay = `<div class="drop-hint">${icon('arrowDown')}IPA hier ablegen</div>`;
  } else if (st === 'installing') {
    overlay = `<div class="big-percent"><b>${Math.round(progress * 100)} %</b><span>Wird installiert …</span></div>`;
  } else if (st === 'success') {
    overlay = `<div class="banner" style="--c:var(--success)"><span class="bi">${icon('check')}</span>
      <span><b>Installiert</b><span>${esc(job.appName)} ist bereit.</span></span></div>`;
  } else if (st === 'failed') {
    overlay = `<div class="banner" style="--c:var(--danger)"><span class="bi">${icon('x')}</span>
      <span><b>${job.state === 'cancelled' ? 'Abgebrochen' : 'Fehlgeschlagen'}</b><span>Siehe Protokoll am Computer.</span></span></div>`;
  }
  setHTML($('screenOverlay'), overlay);

  // Footer
  const device = selectedDevice();
  const head = device
    ? `<span class="dot ${device.needsTrust ? '' : 'on'}" style="--c:var(--success)"></span>${esc(device.name)} ${badge(device.connection)}`
    : `${icon('radar', 16)}Suche iPhone über USB‑C & WLAN …`;

  let button;
  if (job && job.state === 'running') {
    button = `<button class="ghost-btn" data-action="cancel">${icon('stop')}Abbrechen</button>`;
  } else {
    const title = job ? (job.state === 'succeeded' ? 'Nochmal beamen' : 'Erneut versuchen') : 'Jetzt aufs iPhone beamen';
    button = `<button class="beam-btn" data-action="install" ${installBlocker() ? 'disabled' : ''}>${icon('bolt')}${title}</button>`;
  }

  let sub;
  if (job) {
    sub = {
      running: `${{ prepare: 'Vorbereiten', sign: 'Signieren', install: 'Übertragen & installieren' }[currentStep(job)] || 'Läuft'} · ${Math.round(progress * 100)} %`,
      succeeded: `${esc(job.appName)} ist jetzt auf ${esc(job.deviceName)}. Viel Spaß!`,
      failed: 'Fehlgeschlagen – Details rechts im Protokoll.',
      cancelled: 'Abgebrochen.',
    }[job.state];
  } else {
    sub = esc(installBlocker() || `Bereit · ${isWin ? 'Strg' : '⌘'}+Enter zum Installieren`);
  }

  setHTML($('stageFooter'), `<div class="stage-device">${head}</div>${button}<div class="stage-sub">${sub}</div>`);
}

function currentStep(job) {
  return ['prepare', 'sign', 'install'].find((s) => job.steps[s] === 'running');
}

/* ---------------- Right panel ---------------- */

function renderRight() {
  const right = $('rightPanel');
  if (!right.__built) {
    right.__built = true;
    right.innerHTML = '<div class="glass card" id="cardApp"></div><div class="glass card" id="cardSign"></div><div class="glass card" id="cardActivity"></div>';
  }
  renderAppCard();
  renderSigningCard();
  renderActivity();
}

function renderAppCard() {
  const ipa = state.ipa;
  let body;
  if (ipa) {
    body = `
      <div class="app-head">${appIconHtml(ipa.icon, 60)}
        <div style="min-width:0"><div class="app-name">${esc(ipa.name)}</div><div class="mono">${esc(ipa.bundleId)}</div></div></div>
      <div class="pills">
        <span class="pill" style="--c:var(--indigo)">${icon('tag')}v${esc(ipa.version)}${ipa.build && ipa.build !== ipa.version ? ` (${esc(ipa.build)})` : ''}</span>
        <span class="pill" style="--c:var(--cyan)">${icon('box')}${fmtSize(ipa.size)}</span>
        ${ipa.minOS ? `<span class="pill" style="--c:var(--magenta)">${icon('iphone')}iOS ${esc(ipa.minOS)}+</span>` : ''}
        ${ipa.hasExtensions ? `<span class="pill" style="--c:var(--warning)">${icon('puzzle')}Erweiterungen</span>` : ''}
      </div>`;
  } else if (state.inspecting) {
    body = '<p class="muted">IPA wird analysiert …</p>';
  } else {
    body = `<button class="pick-zone" data-action="pick-ipa">${icon('fileDown')}
      <span><b>IPA auswählen</b><span class="tiny">oder irgendwo ins Fenster ziehen</span></span></button>`;
  }
  const error = state.inspectError ? `<div class="warn-line" style="color:var(--danger)">${icon('alert')}${esc(state.inspectError)}</div>` : '';
  setHTML($('cardApp'), `
    <div class="row"><span class="label">${icon('box')}App</span><span class="spacer"></span>
      ${ipa && !(state.job && state.job.state === 'running') ? `<button class="link-btn" data-action="clear-ipa" title="Entfernen">${icon('x', 12)}</button>` : ''}</div>
    ${body}${error}`);
}

function renderSigningCard() {
  const s = state.settings;
  const p = state.profile;
  let body;
  if (s.signingEnabled) {
    const warning = signingWarning();
    body = `
      <button class="field" data-action="pick-p12">${icon('key')}<span class="v ${s.p12Path ? '' : 'ph'}">${esc(s.p12Path ? fileName(s.p12Path) : 'Zertifikat (.p12) wählen …')}</span></button>
      <label class="field">${icon('lock')}<input type="password" id="pwInput" placeholder="${s.hasPassword ? '•••••••• (gespeichert)' : 'Zertifikat-Passwort'}" autocomplete="off"></label>
      <button class="field" data-action="pick-profile">${icon('shield')}<span class="v ${s.profilePath ? '' : 'ph'}">${esc(p && !p.error ? `${p.name} · ${p.bundlePattern}` : s.profilePath ? fileName(s.profilePath) : 'Profil (.mobileprovision) wählen …')}</span></button>
      <label class="field">${icon('tag')}<input type="text" id="bundleInput" value="${esc(s.bundleId || '')}" placeholder="Bundle-ID (optional)" spellcheck="false"></label>
      ${warning
        ? `<div class="warn-line">${icon('alert')}<span>${esc(warning)}</span></div>`
        : p && p.expiration ? `<div class="ok-line">${icon('shield')}Gültig bis ${new Date(p.expiration).toLocaleDateString('de-DE', { day: 'numeric', month: 'short', year: 'numeric' })} · ${esc(p.teamName)}</div>` : ''}`;
  } else {
    body = '<p class="muted">Original-Signatur wird verwendet. Einschalten, um mit deinem Zertifikat (.p12) und Profil neu zu signieren.</p>';
  }
  setHTML($('cardSign'), `
    <div class="row"><span class="label">${icon('pen')}Signierung</span><span class="spacer"></span>
      <label class="switch"><input type="checkbox" id="signToggle" ${s.signingEnabled ? 'checked' : ''}><span></span></label></div>
    ${body}`);
}

function renderActivity() {
  const job = state.job;
  const el = $('cardActivity');
  if (!job) {
    setHTML(el, `<div class="row"><span class="label">${icon('activity')}Aktivität</span></div>
      <p class="muted">Hier siehst du live, was beim Beamen passiert.</p>`);
    return;
  }
  const names = { prepare: 'Vorbereiten', sign: 'Signieren', install: 'Installieren' };
  const stepIcon = { prepare: 'box', sign: 'pen', install: 'arrowDown' };
  const keys = ['prepare', 'sign', 'install'];
  const steps = keys.map((k, i) => {
    const s = job.steps[k];
    const ic = s === 'done' ? 'check' : s === 'failed' ? 'x' : s === 'skipped' ? 'minus' : stepIcon[k];
    const node = `<div class="step ${s}"><span class="node">${icon(ic, 14)}</span>${names[k]}</div>`;
    const connector = i < keys.length - 1
      ? `<span class="connector ${s === 'done' || s === 'skipped' ? 'on' : s === 'failed' ? 'bad' : ''}"></span>` : '';
    return node + connector;
  }).join('');

  const signature = `${job.state}|${keys.map((k) => job.steps[k]).join(',')}|${job.message || ''}`;
  if (el.__sig !== signature) {
    el.__sig = signature;
    el.__html = null;
    el.innerHTML = `
      <div class="row"><span class="label">${icon('activity')}Aktivität</span><span class="spacer"></span>
        ${job.state !== 'running' ? `<button class="link-btn" data-action="dismiss-job" title="Zurücksetzen">${icon('x', 12)}</button>` : ''}</div>
      <div class="steps">${steps}</div>
      ${job.message ? `<div class="error-box">${esc(job.message)}</div>` : ''}
      <div class="terminal">
        <div class="term-bar"><i style="background:#ff5f57"></i><i style="background:#febc2e"></i><i style="background:#28c840"></i>
          <span class="spacer"></span><button class="link-btn" data-action="copy-log" title="Protokoll kopieren">${icon('copy', 12)}</button></div>
        <div class="term-body" id="termBody"></div>
      </div>`;
    el.__logCount = 0;
  }
  const body = $('termBody');
  if (body && el.__logCount !== job.log.length) {
    const prefix = { info: '›', step: '▸', success: '✓', error: '✗' };
    body.innerHTML = job.log.map((l) => `<div class="ln ${l.kind}"><i>${prefix[l.kind] || '›'}</i><span>${esc(l.text)}</span></div>`).join('');
    body.scrollTop = body.scrollHeight;
    el.__logCount = job.log.length;
  }
}

function render() {
  renderTop();
  renderLeft();
  renderStage();
  renderRight();
}

/* ---------------- Actions ---------------- */

async function refreshDevices() {
  if (state.refreshing || demo) return;
  state.refreshing = true;
  try {
    const result = await api.listDevices();
    state.devices = result.devices;
    state.deviceError = result.error;
    const current = selectedDevice();
    if (!current || current.needsTrust) {
      const first = state.devices.find((d) => !d.needsTrust) || state.devices[0];
      state.selectedId = first ? first.id : null;
    }
  } finally {
    state.refreshing = false;
  }
  render();
}

async function loadIpa(file) {
  if (!file) return;
  if (!/\.ipa$/i.test(file)) {
    state.inspectError = 'Bitte wähle eine .ipa-Datei aus.';
    render();
    return;
  }
  if (state.job && state.job.state === 'running') return;
  state.inspecting = true;
  state.inspectError = null;
  render();
  try {
    state.ipa = await api.inspectIpa(file);
    if (state.job && state.job.state !== 'running') state.job = null;
    state.settings = await api.getSettings();
    await refreshRecentsExist();
  } catch (err) {
    state.inspectError = (err && err.message ? err.message : String(err)).replace(/^Error invoking remote method '[^']+': (Error: )?/, '');
  } finally {
    state.inspecting = false;
    render();
  }
}

async function refreshRecentsExist() {
  const files = (state.settings.recents || []).map((r) => r.path);
  const exists = await api.recentsExist(files);
  state.recentsExist = Object.fromEntries(files.map((f, i) => [f, exists[i]]));
}

async function loadProfile() {
  state.profile = state.settings.profilePath ? await api.readProfile(state.settings.profilePath) : null;
}

async function updateSettings(patch) {
  state.settings = await api.setSettings(patch);
  if ('profilePath' in patch) await loadProfile();
  if ('zsignPath' in patch) state.tools = await api.toolStatus();
  render();
}

async function startInstall() {
  const device = selectedDevice();
  const ipa = state.ipa;
  if (!device || !ipa || installBlocker()) return;
  state.job = {
    appName: ipa.name,
    deviceName: device.name,
    connection: device.connection,
    steps: { prepare: 'pending', sign: 'pending', install: 'pending' },
    progress: 0,
    state: 'running',
    message: null,
    log: [],
  };
  render();
  try {
    await api.startInstall({
      ipaInfo: { path: ipa.path, name: ipa.name, version: ipa.version, bundleId: ipa.bundleId },
      device: { udid: device.udid, name: device.name, connection: device.connection },
    });
  } catch (err) {
    handleInstallEvent({ type: 'done', state: 'failed', message: err.message || String(err) });
  }
}

function handleInstallEvent(event) {
  const job = state.job;
  if (!job) return;
  if (event.type === 'step') job.steps[event.step] = event.state;
  if (event.type === 'progress') job.progress = Math.max(job.progress, event.value);
  if (event.type === 'log') job.log.push({ text: event.text, kind: event.kind || 'info' });
  if (event.type === 'step' && event.state === 'running') {
    job.log.push({ text: { prepare: 'Vorbereiten', sign: 'Signieren', install: 'Übertragen & installieren' }[event.step], kind: 'step' });
  }
  if (event.type === 'done') {
    job.state = event.state;
    for (const k of Object.keys(job.steps)) {
      if (job.steps[k] === 'running') job.steps[k] = event.state === 'succeeded' ? 'done' : 'failed';
    }
    if (event.message) {
      job.message = event.message;
      job.log.push({ text: event.message.split('\n')[0], kind: 'error' });
    }
    if (event.state === 'cancelled') job.log.push({ text: 'Installation abgebrochen.', kind: 'error' });
    state.history.unshift({
      appName: job.appName, deviceName: job.deviceName, connection: job.connection, state: event.state,
      time: new Date().toLocaleTimeString('de-DE', { hour: '2-digit', minute: '2-digit' }),
    });
  }
  renderStage();
  renderActivity();
  if (event.type === 'done') render();
}

/* ---------------- Modals ---------------- */

function openModal(html) {
  const modal = $('modal');
  modal.innerHTML = `<div class="modal glass">${html}</div>`;
  modal.classList.add('show');
}

function closeModal() {
  $('modal').classList.remove('show');
}

function showHelp() {
  const steps = isWin
    ? [
      ['usb', 'Apple-Treiber installieren', 'Installiere die App <b>„Apple Devices“</b> aus dem Microsoft Store (oder iTunes). Sie bringt den Apple-Gerätedienst mit, über den IPA Beam mit dem iPhone spricht.'],
      ['lock', 'Per USB‑C verbinden & vertrauen', 'iPhone anschließen, entsperren und auf <b>„Diesem Computer vertrauen“</b> tippen.'],
      ['shield', 'Entwicklermodus aktivieren', 'Auf dem iPhone: Einstellungen → Datenschutz & Sicherheit → <b>Entwicklermodus</b> → Ein.'],
      ['wifi', 'Drahtlos (WLAN)', 'In „Apple Devices“ beim iPhone <b>„Dieses iPhone im WLAN anzeigen“</b> aktivieren. Danach klappt alles ohne Kabel im selben Netzwerk.'],
      ['key', 'Signieren', 'Damit iOS die App annimmt, muss sie für dein Gerät signiert sein: Zertifikat als <b>.p12</b> plus passendes <b>.mobileprovision</b> unter „Signierung“ wählen.'],
    ]
    : [
      ['lock', 'Per USB‑C verbinden & vertrauen', 'iPhone anschließen, entsperren und auf <b>„Diesem Computer vertrauen“</b> tippen.'],
      ['shield', 'Entwicklermodus aktivieren', 'Auf dem iPhone: Einstellungen → Datenschutz & Sicherheit → <b>Entwicklermodus</b> → Ein.'],
      ['wifi', 'Drahtlos (WLAN)', 'Im Finder beim iPhone <b>„Dieses iPhone im WLAN anzeigen“</b> aktivieren. Danach klappt alles ohne Kabel im selben Netzwerk.'],
      ['key', 'Signieren', 'Zertifikat als <b>.p12</b> (aus der Schlüsselbundverwaltung exportiert) und passendes <b>.mobileprovision</b> unter „Signierung“ wählen.'],
    ];
  openModal(`
    <h2>Willkommen bei IPA Beam</h2>
    <p class="lead">In ${steps.length} Schritten bereit zum Sideloaden – über USB‑C oder WLAN.</p>
    <div class="steps-list">${steps.map(([ic, title, text], i) => `
      <div class="step-item"><span class="num">${icon(ic, 17)}</span><div><span class="title">${i + 1}. ${title}</span><p>${text}</p></div></div>`).join('')}
    </div>
    <div class="modal-actions"><button class="btn primary" data-action="close-help">Los geht’s</button></div>`);
}

function showSettings() {
  const s = state.settings;
  const t = state.tools || {};
  openModal(`
    <h2>Einstellungen</h2>
    <p class="lead">Signierung und Werkzeuge.</p>
    <div class="form-grid">
      <span class="lbl">ZERTIFIKAT (.p12)</span>
      <button class="field" data-action="pick-p12">${icon('key')}<span class="v ${s.p12Path ? '' : 'ph'}">${esc(s.p12Path || 'Nicht gewählt')}</span></button>
      <span class="lbl">PROVISIONING-PROFIL</span>
      <button class="field" data-action="pick-profile">${icon('shield')}<span class="v ${s.profilePath ? '' : 'ph'}">${esc(s.profilePath || 'Nicht gewählt')}</span></button>
      <span class="lbl">OPTIONEN</span>
      <label class="field" style="cursor:pointer">${icon('puzzle')}<span class="v">App-Erweiterungen &amp; Watch-App entfernen (für kostenlose Apple‑IDs nötig)</span>
        <span class="switch"><input type="checkbox" id="extToggle" ${s.removeExtensions !== false ? 'checked' : ''}><span></span></span></label>
      <span class="lbl">ZSIGN</span>
      <button class="field" data-action="pick-zsign">${icon('folder')}<span class="v ${t.zsign ? '' : 'ph'}">${esc(t.zsign || 'Nicht gefunden – Pfad zu zsign wählen …')}</span></button>
      <p class="muted" style="margin-top:6px">IPA Beam nutzt <code>zsign</code> zum Signieren. In den fertigen Builds ist es enthalten, sofern verfügbar; sonst hier den Pfad angeben.</p>
      <span class="lbl">APPLE-GERÄTEDIENST</span>
      <div class="${t.usbmuxd ? 'ok-line' : 'warn-line'}">${icon(t.usbmuxd ? 'shield' : 'alert')}${t.usbmuxd ? 'Verbunden' : isWin ? 'Nicht gefunden – „Apple Devices“ aus dem Microsoft Store installieren.' : 'Nicht erreichbar.'}</div>
    </div>
    <div class="modal-actions"><button class="btn primary" data-action="close-modal">Fertig</button></div>`);
}

/* ---------------- Events ---------------- */

document.addEventListener('click', async (event) => {
  const target = event.target.closest('[data-action]');
  if (!target) {
    if (event.target === $('modal')) closeModal();
    return;
  }
  const action = target.dataset.action;
  switch (action) {
    case 'select-device':
      state.selectedId = target.dataset.id;
      render();
      break;
    case 'pick-ipa':
      loadIpa(await api.pickIpa());
      break;
    case 'open-recent':
      if (state.recentsExist[target.dataset.path] !== false) loadIpa(target.dataset.path);
      break;
    case 'clear-ipa':
      state.ipa = null;
      state.inspectError = null;
      if (state.job && state.job.state !== 'running') state.job = null;
      render();
      break;
    case 'install':
      startInstall();
      break;
    case 'cancel':
      api.cancelInstall();
      break;
    case 'dismiss-job':
      state.job = null;
      render();
      break;
    case 'copy-log':
      if (state.job) navigator.clipboard.writeText(state.job.log.map((l) => l.text).join('\n'));
      break;
    case 'pick-p12': {
      const file = await api.pickFile('p12');
      if (file) await updateSettings({ p12Path: file });
      if ($('modal').classList.contains('show')) showSettings();
      break;
    }
    case 'pick-profile': {
      const file = await api.pickFile('profile');
      if (file) await updateSettings({ profilePath: file });
      if ($('modal').classList.contains('show')) showSettings();
      break;
    }
    case 'pick-zsign': {
      const file = await api.pickFile('zsign');
      if (file) await updateSettings({ zsignPath: file });
      showSettings();
      break;
    }
    case 'close-help':
      try { localStorage.setItem('ipabeam.onboarded', '1'); } catch { /* ignore */ }
      closeModal();
      break;
    case 'close-modal':
      closeModal();
      break;
    default:
      break;
  }
});

document.addEventListener('change', (event) => {
  if (event.target.id === 'signToggle') updateSettings({ signingEnabled: event.target.checked });
  if (event.target.id === 'extToggle') updateSettings({ removeExtensions: event.target.checked });
  if (event.target.id === 'bundleInput') updateSettings({ bundleId: event.target.value.trim() });
  if (event.target.id === 'pwInput' && event.target.value) {
    const password = event.target.value;
    event.target.value = '';
    updateSettings({ password });
  }
});

$('btnOpen').addEventListener('click', async () => loadIpa(await api.pickIpa()));
$('btnRefresh').addEventListener('click', () => refreshDevices());
$('btnHelp').addEventListener('click', showHelp);
$('btnSettings').addEventListener('click', showSettings);

document.addEventListener('keydown', (event) => {
  const mod = isWin ? event.ctrlKey : event.metaKey;
  if (event.key === 'Escape') closeModal();
  if (!mod) return;
  if (event.key.toLowerCase() === 'o') { event.preventDefault(); $('btnOpen').click(); }
  if (event.key.toLowerCase() === 'r') { event.preventDefault(); refreshDevices(); }
  if (event.key === 'Enter') { event.preventDefault(); startInstall(); }
});

// Drag & drop anywhere in the window
let dragDepth = 0;
const dropOverlay = $('dropOverlay');
window.addEventListener('dragenter', (e) => { e.preventDefault(); dragDepth++; dropOverlay.classList.add('show'); });
window.addEventListener('dragover', (e) => e.preventDefault());
window.addEventListener('dragleave', (e) => { e.preventDefault(); if (--dragDepth <= 0) { dragDepth = 0; dropOverlay.classList.remove('show'); } });
window.addEventListener('drop', (e) => {
  e.preventDefault();
  dragDepth = 0;
  dropOverlay.classList.remove('show');
  const file = [...(e.dataTransfer.files || [])].find((f) => /\.ipa$/i.test(f.name));
  if (!file) {
    state.inspectError = 'Nur .ipa-Dateien werden unterstützt.';
    render();
    return;
  }
  loadIpa(api.pathForFile(file));
});

// 3D tilt of the phone following the mouse
const stageEl = $('stage');
stageEl.addEventListener('mousemove', (e) => {
  const rect = stageEl.getBoundingClientRect();
  const x = ((e.clientX - rect.left) / rect.width - 0.5) * 2;
  const y = ((e.clientY - rect.top) / rect.height - 0.5) * 2;
  $('phone').style.transform = `rotateY(${x * 14}deg) rotateX(${-y * 10}deg)`;
});
stageEl.addEventListener('mouseleave', () => { $('phone').style.transform = ''; });

// Phone size follows available height
function sizePhone() {
  const area = document.querySelector('.phone-area');
  const width = Math.max(170, Math.min(250, (area.clientHeight - 20) / 2.05));
  $('phone').style.setProperty('--w', `${width}px`);
  $('phoneGlow').style.top = `${width * 2.05 - 50}px`;
}
window.addEventListener('resize', sizePhone);

// Beam particles
(function beamLoop() {
  const canvas = $('beam');
  const ctx = canvas.getContext('2d');
  const fract = (v) => v - Math.floor(v);
  function frame(now) {
    const t = now / 1000;
    ctx.clearRect(0, 0, canvas.width, canvas.height);
    if (stageEl.classList.contains('installing')) {
      const w = canvas.width;
      const h = canvas.height;
      const core = ctx.createLinearGradient(0, 0, 0, h);
      core.addColorStop(0, 'rgba(64,220,255,0)');
      core.addColorStop(0.4, 'rgba(64,220,255,0.55)');
      core.addColorStop(1, 'rgba(110,97,255,0)');
      ctx.fillStyle = core;
      ctx.filter = 'blur(14px)';
      ctx.fillRect(w / 2 - 34, 0, 68, h);
      ctx.filter = 'none';
      const line = ctx.createLinearGradient(0, 0, 0, h);
      line.addColorStop(0, 'rgba(255,255,255,0)');
      line.addColorStop(0.5, 'rgba(255,255,255,0.9)');
      line.addColorStop(1, 'rgba(255,255,255,0)');
      ctx.fillStyle = line;
      ctx.fillRect(w / 2 - 1.5, 0, 3, h);
      for (let i = 0; i < 50; i++) {
        const seed = i * 7.31;
        const speed = 0.55 + fract(Math.sin(seed) * 913.7) * 0.9;
        const p = fract(t * speed + fract(Math.sin(seed * 1.3) * 471.3));
        const spread = (fract(Math.sin(seed * 2.1) * 311.9) - 0.5) * w * 0.7 * (1 - p * 0.8);
        const r = 1 + fract(Math.sin(seed * 3.7) * 91.1) * 2;
        const alpha = Math.sin(p * Math.PI);
        ctx.fillStyle = i % 3 === 0 ? `rgba(237,84,242,${alpha})` : i % 2 === 0 ? `rgba(64,220,255,${alpha})` : `rgba(255,255,255,${alpha})`;
        ctx.fillRect(w / 2 + spread, p * h, r, r * 3.5);
      }
    }
    requestAnimationFrame(frame);
  }
  requestAnimationFrame(frame);
})();

/* ---------------- Boot ---------------- */

async function boot() {
  hydrateIcons();
  buildPhone();
  sizePhone();
  api.onInstallEvent(handleInstallEvent);
  api.onOpenIpa((file) => loadIpa(file));

  state.settings = await api.getSettings();
  state.tools = await api.toolStatus();
  await loadProfile();
  await refreshRecentsExist();

  if (demo) {
    state.devices = DemoData.devices(demo);
    state.selectedId = state.devices[0] ? state.devices[0].id : null;
    state.history = DemoData.history();
    if (!['idle', 'nodevice', 'drop'].includes(demo)) state.ipa = DemoData.ipa;
    state.job = DemoData.job(demo);
    if (demo === 'drop') dropOverlay.classList.add('show');
    render();
    if (demo === 'help') showHelp();
    if (demo === 'settings') showSettings();
    return;
  }

  render();
  await refreshDevices();
  setInterval(() => {
    if (!state.job || state.job.state !== 'running') refreshDevices();
  }, 3000);

  let onboarded = false;
  try { onboarded = localStorage.getItem('ipabeam.onboarded') === '1'; } catch { /* ignore */ }
  if (!onboarded) showHelp();
}

boot();
