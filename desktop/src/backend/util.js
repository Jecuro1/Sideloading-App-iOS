'use strict';

const { spawn } = require('child_process');

/**
 * Runs a command and streams every output line to `onLine`.
 * Resolves with { code, stdout, stderr }. Honours an AbortSignal.
 */
function run(command, args, { onLine, signal, cwd } = {}) {
  return new Promise((resolve, reject) => {
    const child = spawn(command, args, { cwd, windowsHide: true });
    let stdout = '';
    let stderr = '';
    let pending = '';

    const handle = (chunk, isErr) => {
      const text = chunk.toString('utf8');
      if (isErr) stderr += text; else stdout += text;
      if (!onLine) return;
      pending += text;
      const parts = pending.split(/\r?\n|\r/);
      pending = parts.pop();
      for (const line of parts) {
        if (line.trim()) onLine(line.trim());
      }
    };

    child.stdout.on('data', (c) => handle(c, false));
    child.stderr.on('data', (c) => handle(c, true));

    const onAbort = () => child.kill();
    if (signal) {
      if (signal.aborted) child.kill();
      signal.addEventListener('abort', onAbort, { once: true });
    }

    child.on('error', (err) => {
      if (signal) signal.removeEventListener('abort', onAbort);
      reject(err);
    });
    child.on('close', (code) => {
      if (signal) signal.removeEventListener('abort', onAbort);
      if (onLine && pending.trim()) onLine(pending.trim());
      if (signal && signal.aborted) {
        const err = new Error('Abgebrochen');
        err.name = 'AbortError';
        return reject(err);
      }
      resolve({ code, stdout, stderr });
    });
  });
}

function withTimeout(promise, ms, message) {
  let timer;
  return Promise.race([
    promise,
    new Promise((_, reject) => {
      timer = setTimeout(() => reject(new Error(message || 'Zeitüberschreitung')), ms);
    }),
  ]).finally(() => clearTimeout(timer));
}

module.exports = { run, withTimeout };
