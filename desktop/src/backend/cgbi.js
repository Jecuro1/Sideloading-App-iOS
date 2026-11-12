'use strict';

// iOS app icons are stored as "CgBI" PNGs (BGRA, premultiplied, raw deflate)
// which browsers cannot display. This converts them back to standard PNGs.

const zlib = require('zlib');

const SIGNATURE = Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);

const CRC_TABLE = (() => {
  const table = new Uint32Array(256);
  for (let n = 0; n < 256; n++) {
    let c = n;
    for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
    table[n] = c >>> 0;
  }
  return table;
})();

function crc32(buffer) {
  let crc = 0xffffffff;
  for (let i = 0; i < buffer.length; i++) crc = CRC_TABLE[(crc ^ buffer[i]) & 0xff] ^ (crc >>> 8);
  return (crc ^ 0xffffffff) >>> 0;
}

function chunk(type, data) {
  const length = Buffer.alloc(4);
  length.writeUInt32BE(data.length);
  const typeAndData = Buffer.concat([Buffer.from(type, 'ascii'), data]);
  const crc = Buffer.alloc(4);
  crc.writeUInt32BE(crc32(typeAndData));
  return Buffer.concat([length, typeAndData, crc]);
}

function paeth(a, b, c) {
  const p = a + b - c;
  const pa = Math.abs(p - a);
  const pb = Math.abs(p - b);
  const pc = Math.abs(p - c);
  if (pa <= pb && pa <= pc) return a;
  if (pb <= pc) return b;
  return c;
}

function unfilter(data, width, height, bpp) {
  const stride = width * bpp;
  const out = Buffer.alloc(stride * height);
  for (let y = 0; y < height; y++) {
    const filter = data[y * (stride + 1)];
    const inRow = y * (stride + 1) + 1;
    const outRow = y * stride;
    for (let x = 0; x < stride; x++) {
      const raw = data[inRow + x];
      const left = x >= bpp ? out[outRow + x - bpp] : 0;
      const up = y > 0 ? out[outRow - stride + x] : 0;
      const upLeft = y > 0 && x >= bpp ? out[outRow - stride + x - bpp] : 0;
      let value;
      switch (filter) {
        case 1: value = raw + left; break;
        case 2: value = raw + up; break;
        case 3: value = raw + ((left + up) >> 1); break;
        case 4: value = raw + paeth(left, up, upLeft); break;
        default: value = raw;
      }
      out[outRow + x] = value & 0xff;
    }
  }
  return out;
}

/** Returns a browser-compatible PNG buffer (unchanged if it already is one). */
function normalizePng(buffer) {
  if (!buffer || buffer.length < 8 || !buffer.subarray(0, 8).equals(SIGNATURE)) return buffer;

  let offset = 8;
  let isCgbi = false;
  let ihdr = null;
  const idat = [];
  const others = [];

  while (offset + 8 <= buffer.length) {
    const length = buffer.readUInt32BE(offset);
    const type = buffer.toString('ascii', offset + 4, offset + 8);
    const data = buffer.subarray(offset + 8, offset + 8 + length);
    offset += 12 + length;
    if (type === 'CgBI') { isCgbi = true; continue; }
    if (type === 'IHDR') { ihdr = data; continue; }
    if (type === 'IDAT') { idat.push(data); continue; }
    if (type === 'IEND') break;
    if (type !== 'iDOT') others.push({ type, data });
  }

  if (!isCgbi || !ihdr) return buffer;
  const width = ihdr.readUInt32BE(0);
  const height = ihdr.readUInt32BE(4);
  const bitDepth = ihdr[8];
  const colorType = ihdr[9];
  if (bitDepth !== 8 || (colorType !== 6 && colorType !== 2)) return buffer;
  const bpp = colorType === 6 ? 4 : 3;

  let inflated;
  try {
    inflated = zlib.inflateRawSync(Buffer.concat(idat));
  } catch {
    return buffer;
  }
  const pixels = unfilter(inflated, width, height, bpp);

  // BGRA -> RGBA and undo premultiplied alpha.
  for (let i = 0; i < pixels.length; i += bpp) {
    const b = pixels[i];
    pixels[i] = pixels[i + 2];
    pixels[i + 2] = b;
    if (bpp === 4) {
      const a = pixels[i + 3];
      if (a > 0 && a < 255) {
        pixels[i] = Math.min(255, Math.round((pixels[i] * 255) / a));
        pixels[i + 1] = Math.min(255, Math.round((pixels[i + 1] * 255) / a));
        pixels[i + 2] = Math.min(255, Math.round((pixels[i + 2] * 255) / a));
      }
    }
  }

  const stride = width * bpp;
  const filtered = Buffer.alloc((stride + 1) * height);
  for (let y = 0; y < height; y++) {
    filtered[y * (stride + 1)] = 0;
    pixels.copy(filtered, y * (stride + 1) + 1, y * stride, (y + 1) * stride);
  }

  return Buffer.concat([
    SIGNATURE,
    chunk('IHDR', ihdr),
    ...others.map((c) => chunk(c.type, c.data)),
    chunk('IDAT', zlib.deflateSync(filtered)),
    chunk('IEND', Buffer.alloc(0)),
  ]);
}

module.exports = { normalizePng };
