"""Regenerate the AetherTV tvOS layered app icon and top shelf images.

Usage: python -I make_tvos_icons.py <path-to-Assets.xcassets>

Writes the `App Icon & Top Shelf Image.brandassets` bundle that
`ASSETCATALOG_COMPILER_APPICON_NAME = "App Icon & Top Shelf Image"` points at:

  App Icon - Apple TV.imagestack      Back + Front, 400x240 @1x / 800x480 @2x
  App Icon - App Store.imagestack     Back + Front, 1280x768 @1x / 2560x1536 @2x
  Top Shelf Image.imageset            1920x720 @1x / 3840x1440 @2x
  Top Shelf Image Wide.imageset       2320x720 @1x / 4640x1440 @2x

tvOS masks the rounded corners itself, so every layer is a full-bleed rectangle.
The layout follows two App Store shipped catalogs (Swiftfin, Moonfin): each
.imagestacklayer holds a Content.imageset, and the stack lists Front then Back.
"""
import json
import os
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

INFO = {"info": {"author": "xcode", "version": 1}}
BRAND = "App Icon & Top Shelf Image.brandassets"


def rgb(hex_value):
    return np.array([int(hex_value[i:i + 2], 16) for i in (1, 3, 5)], dtype=np.float32)


# ---------------------------------------------------------------- backdrop

def backdrop(w, h, base_from, base_to, glows, vignette=0.34):
    """Diagonal base gradient plus soft radial glows. Glows are (x, y, radius, color, strength)
    with x, y normalized to the canvas and radius in multiples of the canvas height."""
    ys, xs = np.mgrid[0:h, 0:w].astype(np.float32)
    u = xs / max(w - 1, 1)
    v = ys / max(h - 1, 1)
    aspect = w / h

    t = np.clip(0.62 * u + 0.38 * (1.0 - v), 0.0, 1.0)[..., None]
    img = rgb(base_from) * (1.0 - t) + rgb(base_to) * t

    for gx, gy, radius, color, strength in glows:
        d2 = ((u - gx) * aspect) ** 2 + (v - gy) ** 2
        g = np.exp(-d2 / (2.0 * radius * radius)) * strength
        img += g[..., None] * rgb(color)

    # vignette: distance from the canvas centre, measured against its half diagonal
    du = (u - 0.5) * aspect
    dv = v - 0.5
    r2 = (du * du + dv * dv) / (0.25 * aspect * aspect + 0.25)
    img *= (1.0 - vignette * np.clip(r2, 0.0, 1.0))[..., None]

    # ordered dither so the dark gradients do not band in 8 bit
    bayer = np.array([[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]], dtype=np.float32)
    img += (bayer[ys.astype(int) % 4, xs.astype(int) % 4] / 16.0 - 0.5)[..., None]
    return np.clip(img, 0, 255)


# ---------------------------------------------------------------- glyph

def rounded_polygon_mask(box, points, radius, supersample=4):
    """Anti-aliased mask (0..1) of a polygon with rounded corners, in final pixel units."""
    sw, sh = int(box[0] * supersample), int(box[1] * supersample)
    mask = Image.new("L", (sw, sh), 0)
    ImageDraw.Draw(mask).polygon([(x * supersample, y * supersample) for x, y in points], fill=255)
    # blurring a hard corner and cutting at 50% rounds it with roughly the blur radius
    mask = mask.filter(ImageFilter.GaussianBlur(radius * supersample))
    mask = mask.point(lambda p: 255 if p >= 128 else 0)
    return np.asarray(mask.resize(box, Image.LANCZOS), dtype=np.float32) / 255.0


def play_glyph(cx, cy, circumradius, corner_radius, glow_radius, glow_strength):
    """A right pointing play triangle with a cyan-to-violet gradient and a soft glow.
    Returns (rgba float array, top, left) of a patch sized to hold the glow."""
    size = int(round(circumradius * 3.2))
    box = (size, size)
    # the centroid of the triangle sits a third of the way from the edge to the tip;
    # nudge it right so the glyph reads as centred
    gx, gy = size / 2.0 + circumradius * 0.045, size / 2.0
    reach = circumradius * 1.02
    points = [
        (gx + reach, gy),
        (gx - reach * math_cos30, gy - reach * 0.5),
        (gx - reach * math_cos30, gy + reach * 0.5),
    ]
    alpha = rounded_polygon_mask(box, points, corner_radius)
    blurred = np.asarray(
        Image.fromarray((alpha * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(glow_radius)),
        dtype=np.float32,
    ) / 255.0

    ys, xs = np.mgrid[0:size, 0:size].astype(np.float32)
    left, top = reach * math_cos30, gy - reach * 0.5
    t = np.clip(0.55 * (xs - left) / (2 * reach * math_cos30) + 0.45 * (ys - top) / reach, 0.0, 1.0)[..., None]
    face = rgb("#3FE6FF") * (1.0 - t) + rgb("#8F6DFF") * t
    face *= (1.0 + 0.16 * np.clip(1.0 - (ys - top) / reach, 0.0, 1.0))[..., None]
    face *= (1.0 - 0.10 * np.clip(((ys - top) / reach - 0.72) / 0.28, 0.0, 1.0))[..., None]

    glow = blurred * glow_strength * (1.0 - alpha)   # the glow shows around the face, not on it
    a_out = alpha + glow
    premultiplied = face * alpha[..., None] + rgb("#6FB4FF") * glow[..., None]
    # PNG wants straight (non-premultiplied) alpha
    color = premultiplied / np.maximum(a_out, 1e-5)[..., None]
    out = np.zeros((size, size, 4), dtype=np.float32)
    out[..., :3] = color
    out[..., 3] = a_out * 255.0
    return out, int(round(cy - size / 2.0)), int(round(cx - size / 2.0))


math_cos30 = 0.8660254


def paste(target, patch, top, left):
    """Put a glyph patch onto a float canvas, clipped to the canvas.
    An opaque RGB canvas gets a real alpha blend; a fully transparent RGBA canvas (the front
    layer) takes the patch as it is, since blending over nothing would premultiply its colours."""
    h, w = target.shape[:2]
    gh, gw = patch.shape[:2]
    x0, y0 = max(left, 0), max(top, 0)
    x1, y1 = min(left + gw, w), min(top + gh, h)
    region = patch[y0 - top:y1 - top, x0 - left:x1 - left]
    if target.shape[2] == 4:
        target[y0:y1, x0:x1] = region
    else:
        a = region[..., 3:4] / 255.0
        target[y0:y1, x0:x1] = region[..., :3] * a + target[y0:y1, x0:x1] * (1.0 - a)
    return np.clip(target, 0, 255)


def save_png(array, path, opaque):
    data = array.astype(np.uint8)
    image = Image.fromarray(data[..., :3] if opaque else data, "RGB" if opaque else "RGBA")
    image.save(path, "PNG", optimize=True)


# ---------------------------------------------------------------- layouts

def icon_layers(w, h):
    """Home screen and App Store artwork share one 5:3 composition.
    Returns (opaque back, transparent front with the glyph) as float arrays."""
    cx, cy = w * 0.5, h * 0.5
    glows = [
        (0.50, 0.50, 0.62, "#4A3ACF", 0.30),   # violet bloom behind the glyph
        (0.16, 0.10, 0.50, "#1F7FD8", 0.20),   # cool light from the top left
        (0.90, 0.96, 0.55, "#7A4BE0", 0.13),   # a warmer floor bottom right
    ]
    back = backdrop(w, h, "#191A38", "#05050C", glows)
    glyph, top, left = play_glyph(
        cx=cx, cy=cy + h * 0.012,
        circumradius=h * 0.295, corner_radius=h * 0.062,
        glow_radius=h * 0.10, glow_strength=0.46,
    )
    front = paste(np.zeros((h, w, 4), dtype=np.float32), glyph, top, left)
    return back, front


def shelf(w, h, wide):
    """Top shelf banner: kept dark on the left where tvOS writes the app name,
    with the bloom and the glyph on the right. Returns an opaque RGB image."""
    gx = 0.735 if wide else 0.70
    glows = [
        (gx, 0.50, 0.72, "#4A3ACF", 0.34),
        (gx - 0.28, 0.08, 0.55, "#1F7FD8", 0.17),
    ]
    back = backdrop(w, h, "#1B1C40", "#04040A", glows, vignette=0.42)
    glyph, top, left = play_glyph(
        cx=w * gx, cy=h * 0.5 + h * 0.012,
        circumradius=h * 0.31, corner_radius=h * 0.066,
        glow_radius=h * 0.11, glow_strength=0.50,
    )
    return paste(back, glyph, top, left)


# ---------------------------------------------------------------- writing

def write_json(path, payload):
    with open(path, "w", encoding="utf-8", newline="\n") as handle:
        json.dump(payload, handle, indent=2, ensure_ascii=False)
        handle.write("\n")


def write_layer(stack_dir, name, scale_files):
    layer_dir = os.path.join(stack_dir, f"{name}.imagestacklayer")
    imageset_dir = os.path.join(layer_dir, "Content.imageset")
    os.makedirs(imageset_dir, exist_ok=True)
    write_json(os.path.join(layer_dir, "Contents.json"), INFO)
    images = []
    for scale, (filename, array) in scale_files.items():
        save_png(array, os.path.join(imageset_dir, filename), opaque=(array.shape[2] == 3))
        # Every entry needs an explicit scale. A bitmap entry without one means "Any",
        # which actool rejects next to an explicit child: "Image set has a child with
        # bitmap content and the "Any" scale. ..." (seen in the first CI run).
        images.append({"filename": filename, "idiom": "tv", "scale": scale})
    write_json(os.path.join(imageset_dir, "Contents.json"), {"images": images, **INFO})


def write_stack(brand_dir, name, layers):
    stack_dir = os.path.join(brand_dir, f"{name}.imagestack")
    os.makedirs(stack_dir, exist_ok=True)
    write_json(os.path.join(stack_dir, "Contents.json"), {
        **INFO,
        "layers": [{"filename": f"{layer}.imagestacklayer"} for layer in layers],
    })
    return stack_dir


def write_imageset(brand_dir, name, scale_files):
    imageset_dir = os.path.join(brand_dir, f"{name}.imageset")
    os.makedirs(imageset_dir, exist_ok=True)
    images = []
    for scale, (filename, array) in scale_files.items():
        save_png(array, os.path.join(imageset_dir, filename), opaque=True)
        images.append({"filename": filename, "idiom": "tv", "scale": scale})
    write_json(os.path.join(imageset_dir, "Contents.json"), {"images": images, **INFO})


def main(assets_dir):
    brand_dir = os.path.join(assets_dir, BRAND)
    os.makedirs(brand_dir, exist_ok=True)

    def icon_stack(name, one_x):
        stack = write_stack(brand_dir, name, ["Front", "Back"])
        rendered = {}
        for scale, (w, h) in (("1x", one_x), ("2x", (one_x[0] * 2, one_x[1] * 2))):
            rendered[scale] = icon_layers(w, h)
        for index, layer in enumerate(("Back", "Front")):
            write_layer(stack, layer, {
                scale: (f"{layer.lower()}{'' if scale == '1x' else '@2x'}.png", images[index])
                for scale, images in rendered.items()
            })

    # Home screen icon: 400x240 @1x, 800x480 @2x
    icon_stack("App Icon - Apple TV", (400, 240))
    # App Store icon: 1280x768 @1x, 2560x1536 @2x
    icon_stack("App Icon - App Store", (1280, 768))

    write_imageset(brand_dir, "Top Shelf Image", {
        "1x": ("top-shelf.png", shelf(1920, 720, wide=False)),
        "2x": ("top-shelf@2x.png", shelf(3840, 1440, wide=False)),
    })
    write_imageset(brand_dir, "Top Shelf Image Wide", {
        "1x": ("top-shelf-wide.png", shelf(2320, 720, wide=True)),
        "2x": ("top-shelf-wide@2x.png", shelf(4640, 1440, wide=True)),
    })

    write_json(os.path.join(brand_dir, "Contents.json"), {
        "assets": [
            {"filename": "App Icon - App Store.imagestack", "idiom": "tv",
             "role": "primary-app-icon", "size": "1280x768"},
            {"filename": "App Icon - Apple TV.imagestack", "idiom": "tv",
             "role": "primary-app-icon", "size": "400x240"},
            {"filename": "Top Shelf Image Wide.imageset", "idiom": "tv",
             "role": "top-shelf-image-wide", "size": "2320x720"},
            {"filename": "Top Shelf Image.imageset", "idiom": "tv",
             "role": "top-shelf-image", "size": "1920x720"},
        ],
        **INFO,
    })
    print("wrote", brand_dir)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1]))
