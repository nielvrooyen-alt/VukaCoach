// Generates icon-192.png and icon-512.png: deep-charcoal rounded square,
// teal "V" chevron. Pure Node (zlib), no dependencies.
const zlib = require('zlib');
const fs = require('fs');
const path = require('path');

function crc32(buf) {
  let table = crc32.table;
  if (!table) {
    table = crc32.table = [];
    for (let n = 0; n < 256; n++) {
      let c = n;
      for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
      table[n] = c >>> 0;
    }
  }
  let crc = 0xffffffff;
  for (let i = 0; i < buf.length; i++) crc = table[(crc ^ buf[i]) & 0xff] ^ (crc >>> 8);
  return (crc ^ 0xffffffff) >>> 0;
}

function chunk(type, data) {
  const len = Buffer.alloc(4);
  len.writeUInt32BE(data.length);
  const body = Buffer.concat([Buffer.from(type, 'ascii'), data]);
  const crc = Buffer.alloc(4);
  crc.writeUInt32BE(crc32(body));
  return Buffer.concat([len, body, crc]);
}

function makeIcon(size) {
  const bg = [18, 20, 24, 255];      // #121418 charcoal
  const fg = [45, 212, 191, 255];    // #2dd4bf teal
  const rows = [];
  const cx = size / 2;
  const half = size * 0.26;          // chevron half-width
  const top = size * 0.32;
  const bottom = size * 0.68;
  const thickness = size * 0.09;

  for (let y = 0; y < size; y++) {
    const row = Buffer.alloc(1 + size * 4);
    row[0] = 0; // filter none
    for (let x = 0; x < size; x++) {
      // rounded-corner mask
      const r = size * 0.18;
      const dx = Math.max(r - x, x - (size - 1 - r), 0);
      const dy = Math.max(r - y, y - (size - 1 - r), 0);
      const corner = dx * dx + dy * dy > r * r;
      let px = bg;
      if (!corner) {
        // V chevron: two strokes from top arms down to center bottom
        const t = (y - top) / (bottom - top); // 0..1 down the V
        if (t >= 0 && t <= 1) {
          const armL = cx - half + t * half;   // left arm x at this y
          const armR = cx + half - t * half;   // right arm x at this y
          const near = Math.min(Math.abs(x - armL), Math.abs(x - armR));
          if (near <= thickness / 2) px = fg;
        }
      }
      const o = 1 + x * 4;
      row[o] = px[0]; row[o + 1] = px[1]; row[o + 2] = px[2]; row[o + 3] = px[3];
    }
    rows.push(row);
  }

  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(size, 0);
  ihdr.writeUInt32BE(size, 4);
  ihdr[8] = 8;  // bit depth
  ihdr[9] = 6;  // RGBA
  const png = Buffer.concat([
    Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
    chunk('IHDR', ihdr),
    chunk('IDAT', zlib.deflateSync(Buffer.concat(rows))),
    chunk('IEND', Buffer.alloc(0)),
  ]);
  return png;
}

const dir = __dirname;
for (const s of [192, 512]) {
  const p = path.join(dir, `icon-${s}.png`);
  fs.writeFileSync(p, makeIcon(s));
  console.log('wrote', p, fs.statSync(p).size, 'bytes');
}
