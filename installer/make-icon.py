"""Build installer/pocket-envelopes.ico from icons/icon-512.png, stdlib only.

The .ico is committed, so users never run this; it exists so the icon can be
regenerated after the PNG changes without installing an image library:

    python installer/make-icon.py

Decodes the 8-bit RGBA, non-interlaced PNG the icon generator writes,
box-downsamples it to the sizes Windows actually asks for, and packs each
size as a PNG-compressed entry (supported since Vista) into one .ico.
"""
import os
import struct
import zlib

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(HERE, "..", "icons", "icon-512.png")
DST = os.path.join(HERE, "pocket-envelopes.ico")
SIZES = [256, 128, 64, 48, 32, 16]


def decode_png(data):
    assert data[:8] == b"\x89PNG\r\n\x1a\n", "not a PNG"
    pos, idat, w, h, color = 8, b"", 0, 0, 6
    while pos < len(data):
        length, ctype = struct.unpack(">I4s", data[pos:pos + 8])
        chunk = data[pos + 8:pos + 8 + length]
        if ctype == b"IHDR":
            w, h, depth, color, _, _, interlace = struct.unpack(">IIBBBBB", chunk)
            assert depth == 8 and color in (2, 6) and interlace == 0, \
                f"expected 8-bit RGB or RGBA, non-interlaced (got depth {depth}, colour type {color}, interlace {interlace})"
        elif ctype == b"IDAT":
            idat += chunk
        pos += 12 + length
    raw = zlib.decompress(idat)
    bpp = 4 if color == 6 else 3
    stride = w * bpp
    rows, prev = [], bytearray(stride)
    for y in range(h):
        f = raw[y * (stride + 1)]
        line = bytearray(raw[y * (stride + 1) + 1:(y + 1) * (stride + 1)])
        for i in range(stride):
            a = line[i - bpp] if i >= bpp else 0
            b = prev[i]
            c = prev[i - bpp] if i >= bpp else 0
            if f == 1: line[i] = (line[i] + a) & 255
            elif f == 2: line[i] = (line[i] + b) & 255
            elif f == 3: line[i] = (line[i] + (a + b) // 2) & 255
            elif f == 4:
                p = a + b - c
                pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
                pred = a if pa <= pb and pa <= pc else (b if pb <= pc else c)
                line[i] = (line[i] + pred) & 255
        prev = line
        if bpp == 3:   # RGB → RGBA, fully opaque
            rgba = bytearray()
            for i in range(0, stride, 3):
                rgba += line[i:i + 3] + b"\xff"
            line = rgba
        rows.append(bytes(line))
    return w, h, rows


def downsample(w, h, rows, size):
    """Box filter with premultiplied alpha, w == h and w % size == 0."""
    k = w // size
    out = []
    for oy in range(size):
        line = bytearray()
        for ox in range(size):
            r = g = b = a = 0
            for y in range(oy * k, (oy + 1) * k):
                row = rows[y]
                for x in range(ox * k, (ox + 1) * k):
                    i = x * 4
                    al = row[i + 3]
                    r += row[i] * al; g += row[i + 1] * al; b += row[i + 2] * al; a += al
            if a:
                line += bytes((r // a, g // a, b // a, a // (k * k)))
            else:
                line += b"\0\0\0\0"
        out.append(bytes(line))
    return out


def encode_png(size, rows):
    def chunk(t, d):
        return struct.pack(">I", len(d)) + t + d + struct.pack(">I", zlib.crc32(t + d) & 0xffffffff)
    raw = b"".join(b"\0" + r for r in rows)
    return (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", size, size, 8, 6, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b""))


def main():
    w, h, rows = decode_png(open(SRC, "rb").read())
    assert w == h == 512, f"expected 512x512, got {w}x{h}"
    images = [(s, encode_png(s, downsample(w, h, rows, s))) for s in SIZES]
    header = struct.pack("<HHH", 0, 1, len(images))
    offset = 6 + 16 * len(images)
    entries, blobs = b"", b""
    for s, png in images:
        entries += struct.pack("<BBBBHHII", s % 256, s % 256, 0, 0, 1, 32, len(png), offset + len(blobs))
        blobs += png
    with open(DST, "wb") as fh:
        fh.write(header + entries + blobs)
    print("wrote", DST, os.path.getsize(DST), "bytes:", ", ".join(f"{s}px" for s, _ in images))
    return images


if __name__ == "__main__":
    main()
