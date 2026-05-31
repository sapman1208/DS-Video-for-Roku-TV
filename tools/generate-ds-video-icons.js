const fs = require("fs");
const zlib = require("zlib");

const font = {
  " ": ["000","000","000","000","000","000","000"],
  "D": ["1110","1001","1001","1001","1001","1001","1110"],
  "S": ["1111","1000","1000","1110","0001","0001","1110"],
  "v": ["0000","0000","1001","1001","1001","0110","0110"],
  "i": ["1","0","1","1","1","1","1"],
  "d": ["0001","0001","0111","1001","1001","1001","0111"],
  "e": ["0000","0000","0110","1001","1111","1000","0111"],
  "o": ["0000","0000","0110","1001","1001","1001","0110"]
};

function crc32(buf) {
  let c = ~0;
  for (const b of buf) {
    c ^= b;
    for (let k = 0; k < 8; k++) c = (c >>> 1) ^ (0xedb88320 & -(c & 1));
  }
  return ~c >>> 0;
}

function chunk(type, data) {
  const out = Buffer.alloc(12 + data.length);
  out.writeUInt32BE(data.length, 0);
  out.write(type, 4, 4, "ascii");
  data.copy(out, 8);
  out.writeUInt32BE(crc32(out.subarray(4, 8 + data.length)), 8 + data.length);
  return out;
}

function png(width, height, pixels) {
  const raw = Buffer.alloc((width * 4 + 1) * height);
  for (let y = 0; y < height; y++) {
    raw[y * (width * 4 + 1)] = 0;
    pixels.copy(raw, y * (width * 4 + 1) + 1, y * width * 4, (y + 1) * width * 4);
  }
  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(width, 0);
  ihdr.writeUInt32BE(height, 4);
  ihdr[8] = 8;
  ihdr[9] = 6;
  return Buffer.concat([
    Buffer.from([137,80,78,71,13,10,26,10]),
    chunk("IHDR", ihdr),
    chunk("IDAT", zlib.deflateSync(raw, { level: 9 })),
    chunk("IEND", Buffer.alloc(0))
  ]);
}

function canvas(width, height, bg) {
  const p = Buffer.alloc(width * height * 4);
  for (let i = 0; i < width * height; i++) {
    p[i * 4] = bg[0]; p[i * 4 + 1] = bg[1]; p[i * 4 + 2] = bg[2]; p[i * 4 + 3] = 255;
  }
  return { width, height, p };
}

function rect(c, x, y, w, h, color) {
  x = Math.round(x); y = Math.round(y); w = Math.round(w); h = Math.round(h);
  for (let yy = Math.max(0, y); yy < Math.min(c.height, y + h); yy++) {
    for (let xx = Math.max(0, x); xx < Math.min(c.width, x + w); xx++) {
      const i = (yy * c.width + xx) * 4;
      c.p[i] = color[0]; c.p[i + 1] = color[1]; c.p[i + 2] = color[2]; c.p[i + 3] = color[3] ?? 255;
    }
  }
}

function roundedRect(c, x, y, w, h, r, color) {
  for (let yy = Math.floor(y); yy < y + h; yy++) {
    for (let xx = Math.floor(x); xx < x + w; xx++) {
      const dx = xx < x + r ? x + r - xx : xx >= x + w - r ? xx - (x + w - r - 1) : 0;
      const dy = yy < y + r ? y + r - yy : yy >= y + h - r ? yy - (y + h - r - 1) : 0;
      if (dx * dx + dy * dy <= r * r) rect(c, xx, yy, 1, 1, color);
    }
  }
}

function textWidth(text, scale) {
  let w = 0;
  for (const ch of text) w += ((font[ch] || font[" "])[0].length + 1) * scale;
  return w - scale;
}

function drawText(c, text, x, y, scale, color) {
  let cx = x;
  for (const ch of text) {
    const glyph = font[ch] || font[" "];
    for (let gy = 0; gy < glyph.length; gy++) {
      for (let gx = 0; gx < glyph[gy].length; gx++) {
        if (glyph[gy][gx] === "1") rect(c, cx + gx * scale, y + gy * scale, scale, scale, color);
      }
    }
    cx += (glyph[0].length + 1) * scale;
  }
}

function filmIcon(c, cx, y, size) {
  const white = [255,255,255,255];
  const red = [223,53,64,255];
  const x = cx - size / 2;
  roundedRect(c, x, y, size, size * 0.72, size * 0.07, white);
  roundedRect(c, x + size * 0.27, y + size * 0.08, size * 0.46, size * 0.27, size * 0.02, red);
  roundedRect(c, x + size * 0.27, y + size * 0.43, size * 0.46, size * 0.22, size * 0.02, red);
  for (const sx of [x + size * 0.09, x + size * 0.82]) {
    for (const sy of [y + size * 0.10, y + size * 0.25, y + size * 0.43, y + size * 0.57]) {
      roundedRect(c, sx, sy, size * 0.11, size * 0.08, size * 0.02, red);
    }
  }
}

function squareIcon(path) {
  const c = canvas(512, 512, [223,53,64]);
  filmIcon(c, 256, 48, 250);
  const text = "DS video";
  const scale = 14;
  drawText(c, text, (512 - textWidth(text, scale)) / 2, 402, scale, [255,255,255,255]);
  fs.writeFileSync(path, png(c.width, c.height, c.p));
}

function sideIcon(path) {
  const c = canvas(540, 290, [223,53,64]);
  filmIcon(c, 142, 42, 165);
  const text = "DS video";
  const scale = 12;
  drawText(c, text, 245, 125, scale, [255,255,255,255]);
  fs.writeFileSync(path, png(c.width, c.height, c.p));
}

squareIcon("images/icon-hd.png");
squareIcon("images/icon-sd.png");
sideIcon("images/icon-side.png");
