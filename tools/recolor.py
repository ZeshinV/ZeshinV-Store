#!/usr/bin/env python3
"""ZeshinV - generatore di temi "cambio colore d'accento" per Samsung serie E.

NON contiene immagini Samsung: lavora su una COPIA delle tue cartelle scaricata dalla TV.
  python3 recolor.py --images ./Images --smarttv ./SmartTV --out ./zeshin-green --hue 135

Cambia solo i pixel blu (tonalita' 165-260 gradi, saturi): grigi, bianchi, neri e
trasparenza (alpha) restano identici. Dimensioni e header dei file non cambiano.
Crea una cartella tema con "manifest" (percorso_TV|cartella_nel_tema), una riga per cartella
modificata, pronto per "zv.sh theme apply".
"""
import argparse, os, shutil, struct
import numpy as np
from PIL import Image

LO, HI, CENTER = 165.0, 260.0, 215.0


def shift_rgb(rgb, delta):
    """rgb: uint8 array (...,3). Ruota la tonalita' dei soli pixel blu saturi."""
    x = rgb.astype(np.float32) / 255.0
    r, g, b = x[..., 0], x[..., 1], x[..., 2]
    mx = x.max(-1); mn = x.min(-1); d = mx - mn
    safe = np.where(d == 0, 1, d)
    h = np.where(mx == r, ((g - b) / safe) % 6,
        np.where(mx == g, (b - r) / safe + 2, (r - g) / safe + 4)) * 60.0
    s = np.where(mx == 0, 0, d / np.where(mx == 0, 1, mx))
    mask = (s > 0.25) & (mx > 0.12) & (h >= LO) & (h <= HI)
    if not mask.any():
        return rgb, 0
    h2 = np.where(mask, (h + delta) % 360.0, h)
    c = mx * s
    hp = h2 / 60.0
    xx = c * (1 - np.abs(hp % 2 - 1))
    z = np.zeros_like(c)
    idx = np.floor(hp).astype(int) % 6
    R = np.choose(idx, [c, xx, z, z, xx, c])
    G = np.choose(idx, [xx, c, c, xx, z, z])
    B = np.choose(idx, [z, z, xx, c, c, xx])
    m = mx - c
    out = np.stack([R + m, G + m, B + m], -1)
    out = np.clip(np.rint(out * 255), 0, 255).astype(np.uint8)
    res = np.where(mask[..., None], out, rgb)
    return res, int(mask.sum())


def recolor_bmp(data, delta):
    if data[:2] != b'BM':
        return data, 0
    off = struct.unpack_from('<I', data, 10)[0]
    hs = struct.unpack_from('<I', data, 14)[0]
    if hs != 40:
        return data, 0
    w, h, _pl, bpp, comp = struct.unpack_from('<iiHHI', data, 18)
    if comp != 0:
        return data, 0
    h = abs(h)
    buf = bytearray(data)
    if bpp in (24, 32):
        bp = bpp // 8
        stride = (w * bp + 3) & ~3
        arr = np.frombuffer(bytes(buf[off:off + stride * h]), np.uint8).reshape(h, stride)
        px = arr[:, :w * bp].reshape(h, w, bp).copy()
        rgb = px[..., [2, 1, 0]]  # BGR -> RGB
        new, n = shift_rgb(rgb, delta)
        if n == 0:
            return data, 0
        px[..., 2], px[..., 1], px[..., 0] = new[..., 0], new[..., 1], new[..., 2]
        arr = arr.copy(); arr[:, :w * bp] = px.reshape(h, w * bp)
        buf[off:off + stride * h] = arr.tobytes()
        return bytes(buf), n
    if bpp == 8:
        pal = np.frombuffer(bytes(buf[54:off]), np.uint8).reshape(-1, 4).copy()
        if len(pal) == 0:
            return data, 0
        rgb = pal[:, [2, 1, 0]].reshape(1, -1, 3)
        new, n = shift_rgb(rgb, delta)
        if n == 0:
            return data, 0
        pal[:, 2], pal[:, 1], pal[:, 0] = new[0, :, 0], new[0, :, 1], new[0, :, 2]
        buf[54:off] = pal.tobytes()
        return bytes(buf), n
    return data, 0


def recolor_png(path, out, delta):
    im = Image.open(path); im.load()
    if im.mode not in ('RGB', 'RGBA'):
        im = im.convert('RGBA')
    a = np.array(im)
    new, n = shift_rgb(a[..., :3], delta)
    if n == 0:
        return False
    a[..., :3] = new
    Image.fromarray(a, im.mode).save(out, 'PNG')
    return True


def process_dir(src, dst, delta):
    changed = 0
    for root, _d, files in os.walk(src):
        rel = os.path.relpath(root, src)
        os.makedirs(os.path.join(dst, rel), exist_ok=True)
        for f in files:
            sp, dp = os.path.join(root, f), os.path.join(dst, rel, f)
            low = f.lower()
            if low.endswith('.bmp'):
                data = open(sp, 'rb').read()
                new, n = recolor_bmp(data, delta)
                open(dp, 'wb').write(new)
                changed += 1 if n else 0
            elif low.endswith('.png'):
                if recolor_png(sp, dp, delta):
                    changed += 1
                else:
                    shutil.copy2(sp, dp)
            else:
                shutil.copy2(sp, dp)
    return changed


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--images', help='copia di /mtd_rocommon/Images')
    ap.add_argument('--smarttv', help='copia di /mtd_appext/SmartTV')
    ap.add_argument('--out', required=True)
    ap.add_argument('--hue', type=float, default=135.0, help='tonalita\' di arrivo 0-360 (135=verde, 20=arancio, 280=viola)')
    ap.add_argument('--skip', default='MenuAnimation,MultiMedia_TV', help='cartelle Images da ignorare')
    a = ap.parse_args()
    delta = a.hue - CENTER
    os.makedirs(a.out, exist_ok=True)
    lines = []
    jobs = []
    if a.images:
        for d in sorted(os.listdir(a.images)):
            p = os.path.join(a.images, d)
            if os.path.isdir(p) and d not in a.skip.split(','):
                jobs.append((p, 'Images_' + d, '/mtd_rocommon/Images/' + d))
    if a.smarttv:
        for d in sorted(os.listdir(a.smarttv)):
            p = os.path.join(a.smarttv, d, 'icon')
            if os.path.isdir(p):
                jobs.append((p, 'SmartTV_%s_icon' % d, '/mtd_appext/SmartTV/%s/icon' % d))
    for src, name, target in jobs:
        tmp = os.path.join(a.out, name)
        n = process_dir(src, tmp, delta)
        if n == 0:
            shutil.rmtree(tmp)
            continue
        lines.append('%s|%s' % (target, name))
        print('%-32s file modificati: %d' % (name, n))
    open(os.path.join(a.out, 'manifest'), 'w', newline='\n').write('\n'.join(lines) + '\n')
    print('Manifest: %d cartelle' % len(lines))


if __name__ == '__main__':
    main()
