"""Regenerate the AetherTV tvOS 3-layer parallax app icon and cinematic Top Shelf images.

Usage: python -I make_tvos_icons.py <path-to-Assets.xcassets>

Writes `App Icon & Top Shelf Image.brandassets`:
  App Icon - Apple TV.imagestack      Front + Middle + Back, 400x240 @1x / 800x480 @2x
  App Icon - App Store.imagestack     Front + Middle + Back, 1280x768 @1x / 2560x1536 @2x
  Top Shelf Image.imageset            1920x720 @1x / 3840x1440 @2x
  Top Shelf Image Wide.imageset       2320x720 @1x / 4640x1440 @2x

Design:
  - Back layer (opaque): deep midnight cinema obsidian backdrop with volumetric projection beams,
    multi-pole sapphire/violet/amber aurora blooms, and subtle optical horizon depth.
  - Middle layer (transparent RGBA): sculpted frosted-glass cinema aperture medallion with precision
    Fresnel rim lighting, concentric metallic lens accents, and floating ambient drop shadow.
  - Front layer (transparent RGBA): multi-faceted luminous crystalline Play prism with top-left
    specular bevel, cyan-to-sapphire-to-violet internal refraction, and crisp edge brilliance.
"""
import json
import math
import os
import shutil
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

INFO = {"info": {"author": "xcode", "version": 1}}
BRAND = "App Icon & Top Shelf Image.brandassets"


def rgb(hex_value):
    return np.array([int(hex_value[i:i + 2], 16) for i in (1, 3, 5)], dtype=np.float32)


def smoothstep(edge0, edge1, x):
    t = np.clip((x - edge0) / max(edge1 - edge0, 1e-6), 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


def alpha_over_rgba(dst_rgba, src_rgba):
    """Straight-alpha Porter-Duff 'source over' compositing on float RGBA arrays (0..255)."""
    sa = np.clip(src_rgba[..., 3:4] / 255.0, 0.0, 1.0)
    da = np.clip(dst_rgba[..., 3:4] / 255.0, 0.0, 1.0)
    out_a = sa + da * (1.0 - sa)
    out_rgb = (src_rgba[..., :3] * sa + dst_rgba[..., :3] * da * (1.0 - sa)) / np.maximum(out_a, 1e-5)
    out = np.zeros_like(dst_rgba, dtype=np.float32)
    out[..., :3] = np.clip(out_rgb, 0.0, 255.0)
    out[..., 3:4] = np.clip(out_a * 255.0, 0.0, 255.0)
    return out


def composite_rgba_over_rgb(bg_rgb, fg_rgba):
    """Composite straight-alpha RGBA onto opaque RGB float array."""
    a = np.clip(fg_rgba[..., 3:4] / 255.0, 0.0, 1.0)
    return np.clip(fg_rgba[..., :3] * a + bg_rgb * (1.0 - a), 0.0, 255.0)


def blur_channel(arr, radius):
    if radius <= 0.1:
        return arr
    img = Image.fromarray(np.clip(arr * 255.0, 0, 255).astype(np.uint8), "L")
    blurred = img.filter(ImageFilter.GaussianBlur(radius))
    return np.asarray(blurred, dtype=np.float32) / 255.0


# ---------------------------------------------------------------- back layer

def make_cinema_backdrop(w, h, focus_x=0.5, focus_y=0.5, beam_angle=-0.42, wide=False):
    ys, xs = np.mgrid[0:h, 0:w].astype(np.float32)
    u = xs / max(w - 1, 1)
    v = ys / max(h - 1, 1)
    aspect = w / float(h)

    # Rich deep obsidian-indigo cinema base gradient
    grad_t = np.clip(0.55 * u + 0.45 * v, 0.0, 1.0)[..., None]
    img = rgb("#0C1229") * (1.0 - grad_t) + rgb("#04060E") * grad_t

    # Atmospheric radial aurora blooms
    glows = [
        (focus_x, focus_y, 0.62 if not wide else 0.72, "#2855E8", 0.42),
        (focus_x - 0.18, focus_y - 0.24, 0.48, "#19C4FF", 0.24),
        (focus_x + 0.22, focus_y + 0.20, 0.56, "#7A3EFF", 0.26),
        (focus_x + 0.30, focus_y - 0.30, 0.44, "#F5B856", 0.08),
    ]
    for gx, gy, radius, color, strength in glows:
        d2 = ((u - gx) * aspect) ** 2 + (v - gy) ** 2
        g = np.exp(-d2 / (2.0 * radius * radius)) * strength
        img += g[..., None] * rgb(color)

    # Volumetric cinema projector rays radiating softly behind the focal point
    dx = (u - focus_x) * aspect
    dy = v - focus_y
    dist = np.sqrt(dx * dx + dy * dy)
    angle = np.arctan2(dy, dx)

    def angular_diff(a, target):
        return ((a - target + math.pi) % (2.0 * math.pi)) - math.pi

    ray1 = np.exp(-(angular_diff(angle, beam_angle) ** 2) / (2.0 * 0.24 ** 2))
    ray2 = np.exp(-(angular_diff(angle, beam_angle + math.pi) ** 2) / (2.0 * 0.28 ** 2))
    ray3 = np.exp(-(angular_diff(angle, beam_angle + 0.45) ** 2) / (2.0 * 0.14 ** 2))
    radial_fade = np.exp(-(dist ** 2) / (2.0 * (0.95 if not wide else 1.25) ** 2))
    beam_energy = (ray1 * 0.20 + ray2 * 0.14 + ray3 * 0.10) * radial_fade
    img += beam_energy[..., None] * rgb("#6BD6FF")

    # Subtle large concentric cinema optical rings engraved in deep background
    for ring_r, ring_w, alpha_v, col in (
        (0.46, 0.0045, 0.12, "#80C8FF"),
        (0.60, 0.0035, 0.07, "#9B80FF"),
        (0.76, 0.0030, 0.045, "#64B8FF"),
    ):
        ring_mask = np.exp(-((dist - ring_r) ** 2) / (2.0 * ring_w ** 2))
        # Modulate around the ring so it catches light asymmetrically
        sheen = 0.45 + 0.55 * np.clip(np.cos(angle + 2.35), 0.0, 1.0)
        img += (ring_mask * sheen * alpha_v)[..., None] * rgb(col)

    # Subtle horizon light streak for Top Shelf widescreen elegance
    if wide:
        streak = np.exp(-((v - focus_y) ** 2) / (2.0 * 0.008 ** 2)) * np.exp(-((u - focus_x) ** 2) / (2.0 * 0.38 ** 2))
        img += (streak * 0.22)[..., None] * rgb("#5CE4FF")

    # Refined cinema vignette
    du = (u - 0.5) * aspect
    dv = v - 0.5
    r2 = (du * du + dv * dv) / (0.25 * aspect * aspect + 0.25)
    img *= (1.0 - 0.36 * np.clip(r2, 0.0, 1.0))[..., None]

    # Ordered Bayer 4x4 dithering to prevent any 8-bit banding on 4K HDR/OLED TVs
    bayer = np.array([[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]], dtype=np.float32)
    img += (bayer[ys.astype(int) % 4, xs.astype(int) % 4] / 16.0 - 0.5)[..., None] * 0.85
    return np.clip(img, 0.0, 255.0)


# ---------------------------------------------------------------- middle layer (optical glass medallion)

def make_optical_medallion_layer(w, h, cx, cy, outer_r):
    """Transparent RGBA layer: sculpted dark frosted-glass optical aperture ring & specular rim."""
    ys, xs = np.mgrid[0:h, 0:w].astype(np.float32)
    dx = xs - cx
    dy = ys - cy
    dist = np.sqrt(dx * dx + dy * dy)
    angle = np.arctan2(dy, dx)

    layer = np.zeros((h, w, 4), dtype=np.float32)

    # 1. Soft elevated drop shadow beneath the medallion (separates Middle from Back in parallax)
    sdx = xs - cx
    sdy = ys - (cy + outer_r * 0.09)
    sdist = np.sqrt(sdx * sdx + sdy * sdy)
    shadow_a = (1.0 - smoothstep(outer_r * 0.88, outer_r * 1.24, sdist)) * 0.58
    shadow = np.zeros((h, w, 4), dtype=np.float32)
    shadow[..., :3] = rgb("#02040B")
    shadow[..., 3] = shadow_a * 255.0
    layer = alpha_over_rgba(layer, shadow)

    # 2. Translucent frosted sapphire-obsidian glass disc
    aa = max(1.2, outer_r * 0.012)
    disc_mask = 1.0 - smoothstep(outer_r - aa, outer_r + aa, dist)
    nx = dx / max(outer_r, 1.0)
    ny = dy / max(outer_r, 1.0)
    # Subtle domed glass shading: cooler luminous top-left, deeper obsidian bottom-right
    dome_t = np.clip(0.5 - 0.36 * nx - 0.36 * ny, 0.0, 1.0)[..., None]
    disc_col = rgb("#0B1126") * (1.0 - dome_t) + rgb("#23376B") * dome_t
    # Inner concave radial glow near center
    inner_glow = np.exp(-((dist / max(outer_r, 1.0)) ** 2) / (2.0 * 0.52 ** 2))
    disc_col += (inner_glow * 0.22)[..., None] * rgb("#38C8FF")
    # Crisp curved glass sheen across upper crescent
    crescent = np.clip(1.0 - ((nx + 0.12) ** 2 + (ny + 0.52) ** 2) / 0.72, 0.0, 1.0)
    crescent = (crescent ** 2.2) * disc_mask
    disc_col += (crescent * 0.30)[..., None] * rgb("#D6F4FF")

    disc = np.zeros((h, w, 4), dtype=np.float32)
    disc[..., :3] = np.clip(disc_col, 0.0, 255.0)
    disc[..., 3] = disc_mask * 0.80 * 255.0
    layer = alpha_over_rgba(layer, disc)

    # 3. Precision bevel outer metallic-glass rim (Fresnel top-left bright silver-cyan, bottom-right violet)
    rim_thickness = max(2.0, outer_r * 0.032)
    rim_mask = np.exp(-((dist - (outer_r - rim_thickness * 0.45)) ** 2) / (2.0 * (rim_thickness * 0.55) ** 2))
    top_left_light = np.clip(np.cos(angle + 2.35), 0.0, 1.0)
    bottom_right_light = np.clip(np.cos(angle - 0.79), 0.0, 1.0)
    rim_col = (
        rgb("#E8F8FF") * (0.25 + 0.75 * top_left_light[..., None])
        + rgb("#7C68FF") * (0.45 * bottom_right_light[..., None])
        + rgb("#36E0FF") * 0.25
    )
    rim_alpha = np.clip(rim_mask * (0.38 + 0.62 * np.maximum(top_left_light, bottom_right_light * 0.65)), 0.0, 1.0)
    rim = np.zeros((h, w, 4), dtype=np.float32)
    rim[..., :3] = np.clip(rim_col, 0.0, 255.0)
    rim[..., 3] = rim_alpha * 255.0
    layer = alpha_over_rgba(layer, rim)

    # 4. Inner fine aperture ring (cinematic lens detail)
    inner_r = outer_r * 0.78
    inner_w = max(1.1, outer_r * 0.011)
    inner_ring = np.exp(-((dist - inner_r) ** 2) / (2.0 * inner_w ** 2))
    ring_col = rgb("#9CE8FF") * (0.45 + 0.55 * top_left_light[..., None]) + rgb("#A78BFA") * (0.35 * bottom_right_light[..., None])
    ring_rgba = np.zeros((h, w, 4), dtype=np.float32)
    ring_rgba[..., :3] = np.clip(ring_col, 0.0, 255.0)
    ring_rgba[..., 3] = np.clip(inner_ring * (0.28 + 0.36 * top_left_light), 0.0, 1.0) * 255.0
    layer = alpha_over_rgba(layer, ring_rgba)

    return layer


# ---------------------------------------------------------------- front layer (crystalline 3D play prism)

def rounded_triangle_sdf_mask(w, h, points, corner_radius, supersample=4):
    """High-precision anti-aliased rounded play triangle mask (0..1)."""
    sw, sh = w * supersample, h * supersample
    mask = Image.new("L", (sw, sh), 0)
    ImageDraw.Draw(mask).polygon([(x * supersample, y * supersample) for x, y in points], fill=255)
    mask = mask.filter(ImageFilter.GaussianBlur(corner_radius * supersample))
    mask = mask.point(lambda p: 255 if p >= 128 else 0)
    return np.asarray(mask.resize((w, h), Image.LANCZOS), dtype=np.float32) / 255.0


def make_play_prism_layer(w, h, cx, cy, circumradius):
    """Transparent RGBA front layer: sculpted crystalline 3D play prism with bevel & aura."""
    cos30 = 0.8660254
    # Optical centroid nudge so the right-pointing triangle looks perfectly centered in the lens
    gx = cx + circumradius * 0.075
    gy = cy
    reach = circumradius * 1.04
    points = [
        (gx + reach, gy),
        (gx - reach * cos30, gy - reach * 0.88),
        (gx - reach * cos30, gy + reach * 0.88),
    ]

    corner_r = circumradius * 0.19
    alpha = rounded_triangle_sdf_mask(w, h, points, corner_r)

    layer = np.zeros((h, w, 4), dtype=np.float32)

    # 1. Crisp floating drop shadow (makes Front layer pop off Middle lens in Apple TV 3D parallax)
    shift_y = int(round(circumradius * 0.14))
    shifted_alpha = np.roll(alpha, shift_y, axis=0)
    if shift_y > 0:
        shifted_alpha[:shift_y, :] = 0.0
    shadow_blur = blur_channel(shifted_alpha, circumradius * 0.18)
    shadow = np.zeros((h, w, 4), dtype=np.float32)
    shadow[..., :3] = rgb("#020512")
    shadow[..., 3] = np.clip(shadow_blur * 0.65, 0.0, 1.0) * 255.0
    layer = alpha_over_rgba(layer, shadow)

    # 2. Luminous cyan-indigo optical aura around the prism
    aura_blur = blur_channel(alpha, circumradius * 0.30)
    aura = np.zeros((h, w, 4), dtype=np.float32)
    aura[..., :3] = rgb("#47D1FF")
    aura[..., 3] = np.clip(aura_blur * (1.0 - alpha) * 0.55, 0.0, 1.0) * 255.0
    layer = alpha_over_rgba(layer, aura)

    # 3. Sculpted multi-faceted crystalline face shading
    ys, xs = np.mgrid[0:h, 0:w].astype(np.float32)
    left_x = gx - reach * cos30
    top_y = gy - reach * 0.88
    u_tri = np.clip((xs - left_x) / max(reach * (1.0 + cos30), 1.0), 0.0, 1.0)
    v_tri = np.clip((ys - top_y) / max(2.0 * reach * 0.88, 1.0), 0.0, 1.0)

    # Primary diagonal crystalline gradient: ice-cyan -> azure -> luminous indigo-violet
    t_diag = np.clip(0.58 * u_tri + 0.42 * v_tri, 0.0, 1.0)[..., None]
    c_top = rgb("#7DF9FF")
    c_mid = rgb("#2AB8FF")
    c_bot = rgb("#7E5BFF")
    face = np.where(
        t_diag < 0.5,
        c_top * (1.0 - t_diag * 2.0) + c_mid * (t_diag * 2.0),
        c_mid * (1.0 - (t_diag - 0.5) * 2.0) + c_bot * ((t_diag - 0.5) * 2.0),
    )

    # Subtle internal glass facet split (upper facet catches crisp specular sheen)
    facet_line = smoothstep(-0.08, 0.14, (v_tri - 0.48) - 0.18 * (u_tri - 0.35))
    face = face * (1.14 - 0.18 * facet_line[..., None])

    # Top-left internal glass sheen highlight
    sheen = np.clip(1.0 - ((u_tri - 0.20) ** 2 / 0.22 + (v_tri - 0.22) ** 2 / 0.16), 0.0, 1.0) ** 1.8
    face += (sheen * 0.38)[..., None] * rgb("#FFFFFF")

    # Inner bevel edge highlight computed from blurred alpha gradient
    inner_eroded = blur_channel(alpha, max(1.5, circumradius * 0.055))
    edge_band = np.clip((alpha - inner_eroded) * 2.6, 0.0, 1.0) * alpha
    # Stronger specular white along top/left edges, subtle warm-violet rim on bottom edge
    bevel_top = np.clip(1.0 - v_tri * 1.25, 0.0, 1.0)
    bevel_bot = np.clip((v_tri - 0.55) * 1.8, 0.0, 1.0)
    face += (edge_band * bevel_top * 0.72)[..., None] * rgb("#FFFFFF")
    face += (edge_band * bevel_bot * 0.22)[..., None] * rgb("#C4B5FD")

    prism = np.zeros((h, w, 4), dtype=np.float32)
    prism[..., :3] = np.clip(face, 0.0, 255.0)
    prism[..., 3] = alpha * 255.0
    layer = alpha_over_rgba(layer, prism)

    return layer


# ---------------------------------------------------------------- layouts

def icon_layers(w, h):
    """Returns (back_rgb, middle_rgba, front_rgba) for 3-layer Apple TV parallax stack."""
    cx, cy = w * 0.5, h * 0.5
    back = make_cinema_backdrop(w, h, focus_x=0.5, focus_y=0.5, wide=False)
    middle = make_optical_medallion_layer(w, h, cx=cx, cy=cy, outer_r=h * 0.375)
    front = make_play_prism_layer(w, h, cx=cx, cy=cy, circumradius=h * 0.215)
    return back, middle, front


def top_shelf_image(w, h, wide):
    """Cinematic widescreen Top Shelf banner (opaque RGB)."""
    fx = 0.725 if wide else 0.695
    fy = 0.50
    back = make_cinema_backdrop(w, h, focus_x=fx, focus_y=fy, beam_angle=-0.28, wide=True)
    middle = make_optical_medallion_layer(w, h, cx=w * fx, cy=h * fy, outer_r=h * 0.37)
    front = make_play_prism_layer(w, h, cx=w * fx, cy=h * fy, circumradius=h * 0.21)

    # Subtle ambient cinema bokeh accents floating in mid-right depth
    ys, xs = np.mgrid[0:h, 0:w].astype(np.float32)
    aspect = w / float(h)
    u = xs / max(w - 1, 1)
    v = ys / max(h - 1, 1)
    for bx, by, br, col, st in (
        (fx - 0.24, 0.24, 0.065, "#38BDF8", 0.14),
        (fx - 0.17, 0.78, 0.045, "#818CF8", 0.12),
        (fx + 0.18, 0.22, 0.050, "#FBBF24", 0.08),
    ):
        d = np.sqrt(((u - bx) * aspect) ** 2 + (v - by) ** 2)
        orb = np.exp(-(d ** 2) / (2.0 * br ** 2)) * st
        back = np.clip(back + orb[..., None] * rgb(col), 0.0, 255.0)

    merged = composite_rgba_over_rgb(back, middle)
    merged = composite_rgba_over_rgb(merged, front)
    return merged


# ---------------------------------------------------------------- writing

def save_png(array, path, opaque):
    data = np.clip(array, 0, 255).astype(np.uint8)
    image = Image.fromarray(data[..., :3] if opaque else data, "RGB" if opaque else "RGBA")
    image.save(path, "PNG", optimize=True)


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
        images.append({"filename": filename, "idiom": "tv", "scale": scale})
    write_json(os.path.join(imageset_dir, "Contents.json"), {"images": images, **INFO})


def write_stack(brand_dir, name, layers):
    stack_dir = os.path.join(brand_dir, f"{name}.imagestack")
    if os.path.exists(stack_dir):
        shutil.rmtree(stack_dir)
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
        # tvOS imagestack order: Front (topmost) -> Middle -> Back (bottommost)
        stack = write_stack(brand_dir, name, ["Front", "Middle", "Back"])
        rendered = {}
        for scale, (w, h) in (("1x", one_x), ("2x", (one_x[0] * 2, one_x[1] * 2))):
            rendered[scale] = icon_layers(w, h)
        for index, layer in enumerate(("Back", "Middle", "Front")):
            write_layer(stack, layer, {
                scale: (f"{layer.lower()}{'' if scale == '1x' else '@2x'}.png", images[index])
                for scale, images in rendered.items()
            })

    icon_stack("App Icon - Apple TV", (400, 240))
    icon_stack("App Icon - App Store", (1280, 768))

    write_imageset(brand_dir, "Top Shelf Image", {
        "1x": ("top-shelf.png", top_shelf_image(1920, 720, wide=False)),
        "2x": ("top-shelf@2x.png", top_shelf_image(3840, 1440, wide=False)),
    })
    write_imageset(brand_dir, "Top Shelf Image Wide", {
        "1x": ("top-shelf-wide.png", top_shelf_image(2320, 720, wide=True)),
        "2x": ("top-shelf-wide@2x.png", top_shelf_image(4640, 1440, wide=True)),
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

    # Write a flattened preview of the 2x Apple TV icon into scratch/temp only if requested via env
    preview_path = os.environ.get("AETHER_ICON_PREVIEW")
    if preview_path:
        b, m, f = icon_layers(800, 480)
        flat = composite_rgba_over_rgb(composite_rgba_over_rgb(b, m), f)
        save_png(flat, preview_path, opaque=True)

    print("wrote 3-layer parallax brandassets:", brand_dir)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1]))
