"""Builds the browser version of the game (Godot "Web" preset) with lighter textures, from a
temporary copy of the project, so the desktop project keeps its full-quality assets.

  python tools/build_web.py [--godot PATH] [--work DIR] [--out build/web]

What the copy gets (the desktop project is never modified):
  * sci-fi scans (assets/textures/scifi, 2k)      -> 1024 px
  * garden scans (assets/textures/<set>, 1k)      -> 512 px
  * any other texture larger than 1024 px         -> 1024 px
  * terrain texture arrays (1024 px layers, BPTC) -> 768 px layers, standard compression
  * ETC2/ASTC import off (desktop browsers use S3TC/BPTC)
  * directional shadow map 4096 -> 2048
  * shader "instance uniforms" that browsers cannot afford become shared uniforms: WebGL's
    renderer has room for only ~250 objects with per-object shader values, and the sci-fi
    panels alone use ~550 (facility power on panels then simply stays on)
  * sci-fi panels: no parallax seams, and scan colours normalised so walls are not washed out
  * shared effect particles: no turbulence or soft depth fade (minute-long WebGL compile)
Then it imports, exports the Web preset (single-threaded, no special server headers needed)
into --out, and checks that no file is over GitHub's 100 MB limit.
"""
import argparse
import os
import re
import shutil
import subprocess
import sys
import tempfile

from PIL import Image

PROJECT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
SKIP_DIRS = {".git", "build", "backups", "docs", "tests"}
GARDEN_SETS = {"bark_brown_02", "dark_rock", "mossy_rock", "rock_boulder_dry", "rough_wood",
               "rusty_metal_02", "rusty_painted_metal", "sandstone_cracks"}
TERRAIN_LAYER = 768
LIMIT_FILE_MB = 95.0


def log(*a):
    print("[build_web]", *a, flush=True)


def copy_project(work):
    if os.path.isdir(work):
        shutil.rmtree(work)
    os.makedirs(work)
    for name in os.listdir(PROJECT):
        if name in SKIP_DIRS:
            continue
        src = os.path.join(PROJECT, name)
        dst = os.path.join(work, name)
        if os.path.isdir(src):
            ignore = shutil.ignore_patterns("*.exe", "*.etc2.ctex", "*.etc2.ctexarray", "*.astc.ctex") if name in ("tools", ".godot") else None
            shutil.copytree(src, dst, ignore=ignore)
        else:
            shutil.copy2(src, dst)


def set_param(text, key, value):
    pattern = re.compile(r"^%s=.*$" % re.escape(key), re.M)
    if pattern.search(text):
        return pattern.sub("%s=%s" % (key, value), text)
    return text.rstrip("\n") + "\n%s=%s\n" % (key, value)


def forget_import(work, import_text):
    """Delete a resource's imported files in the copy so Godot re-imports it."""
    for m in re.finditer(r'"res://(\.godot/imported/[^"]+)"', import_text):
        base = os.path.join(work, m.group(1).replace("/", os.sep))
        stem = base.rsplit("-", 1)[0]
        folder = os.path.dirname(base)
        prefix = os.path.basename(stem) + "-"
        if os.path.isdir(folder):
            for f in os.listdir(folder):
                if f.startswith(prefix):
                    os.remove(os.path.join(folder, f))


def lighten_textures(work):
    changed = 0
    for root, _dirs, files in os.walk(work):
        if os.sep + ".godot" in root:
            continue
        for f in files:
            if not f.endswith(".import"):
                continue
            path = os.path.join(root, f)
            src = path[: -len(".import")]
            text = open(path, encoding="utf-8").read()
            rel = os.path.relpath(src, work).replace(os.sep, "/")
            if 'importer="2d_array_texture"' in text and rel.startswith("assets/textures/terrain/"):
                img = Image.open(src)
                w, h = img.size
                if w > TERRAIN_LAYER:
                    img.resize((TERRAIN_LAYER, h * TERRAIN_LAYER // w), Image.LANCZOS).save(src)
                text = set_param(text, "compress/high_quality", "false")
            elif 'importer="texture"' in text and os.path.exists(src):
                try:
                    w, h = Image.open(src).size
                except Exception:
                    continue
                parts = rel.split("/")
                limit = 0
                if rel.startswith("assets/textures/scifi/"):
                    limit = 1024
                elif len(parts) >= 3 and parts[0] == "assets" and parts[1] == "textures" and parts[2] in GARDEN_SETS:
                    limit = 512
                elif max(w, h) > 1024:
                    limit = 1024
                if not limit or max(w, h) <= limit:
                    continue
                text = set_param(text, "process/size_limit", str(limit))
            else:
                continue
            forget_import(work, text)
            open(path, "w", encoding="utf-8").write(text)
            changed += 1
    return changed


# (file, original text, browser replacement)
WEB_PATCHES = [
    # Per-object values become shared ones (the renderer's per-object buffer overflows).
    ("shaders/scifi_panel.gdshader", "instance uniform float power_level = 1.0;", "uniform float power_level = 1.0;"),
    ("shaders/hologram.gdshader", "instance uniform float visibility = 1.0;", "uniform float visibility = 1.0;"),
    # Shared by every robot; per-object it only drove the shell shimmer while boosting.
    ("shaders/robot_candy.gdshader", "instance uniform float energy_boost = 0.0;", "uniform float energy_boost = 0.0;"),
    # Speed: no parallax ray-march in the sci-fi panels (the seams stay, without depth).
    ("shaders/scifi_panel.gdshader", "float depth = groove_depth * (1.0 - smoothstep(14.0, 24.0, view_dist));", "float depth = 0.0;"),
    # The WebGL renderer hands the panels their scan colours without sRGB decoding, so
    # dividing by the (linear) scan_lum made the walls ~5x too bright (washed-out white).
    # Normalise by the texture's own average (its smallest mip) instead: right either way.
    ("shaders/scifi_panel.gdshader",
     "\t\tfloat sl = luma(s_alb);\n"
     "\t\tvec3 tinted = col * mix(1.0, sl / max(scan_lum, 0.01), scan_detail);\n"
     "\t\tvec3 raw = s_alb * (luma(col) / max(scan_lum, 0.01));",
     "\t\tfloat sl = luma(s_alb);\n"
     "\t\tfloat avg_l = max(luma(textureLod(scan_albedo, vec2(0.5), 14.0).rgb), 0.01);\n"
     "\t\tvec3 tinted = col * mix(1.0, sl / avg_l, scan_detail);\n"
     "\t\tvec3 raw = s_alb * (luma(col) / avg_l);"),
    # Shared effect particles (energy fragments, power nodes, ...): no turbulence, whose noise
    # shader takes about a minute to compile under WebGL and freezes the page meanwhile, and no
    # soft depth fade (WebGL cannot copy the depth buffer it reads). The sci-fi effects do the
    # same through OS.has_feature("web") in scifi_fx.gd.
    ("scripts/gameplay/fx_factory.gd", "\tpm.turbulence_enabled = true\n", "\tpm.turbulence_enabled = false\n"),
    ("scripts/gameplay/fx_factory.gd", "\tm.proximity_fade_enabled = true\n", "\tm.proximity_fade_enabled = false\n"),
    # Pond mist: fog volumes need Forward+, so browsers skip the fog material (which otherwise
    # logs "shader type fog not supported"); the mist was never drawn there anyway.
    ("scripts/world/water_bodies.gd", "\tfog.size = size\n\tvar fm := FogMaterial.new()\n",
     "\tfog.size = size\n\tif OS.has_feature(\"web\"):\n\t\tadd_child(fog)\n\t\treturn fog\n\tvar fm := FogMaterial.new()\n"),
]


def patch_files(work):
    for rel, old, new in WEB_PATCHES:
        p = os.path.join(work, rel.replace("/", os.sep))
        s = open(p, encoding="utf-8").read()
        if old not in s:
            log("warning: %s no longer contains %r" % (rel, old))
            continue
        open(p, "w", encoding="utf-8").write(s.replace(old, new))


def web_project_settings(work):
    p = os.path.join(work, "project.godot")
    s = open(p, encoding="utf-8").read()
    s = s.replace("textures/vram_compression/import_etc2_astc=true\n", "")
    s = s.replace("lights_and_shadows/directional_shadow/size=4096", "lights_and_shadows/directional_shadow/size=2048")
    open(p, "w", encoding="utf-8").write(s)


def run(godot, args, log_path):
    with open(log_path, "w", encoding="utf-8", errors="replace") as fh:
        r = subprocess.run([godot] + args, stdout=fh, stderr=subprocess.STDOUT)
    return r.returncode


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--godot", default=os.path.join(PROJECT, "tools", "Godot_v4.7.2-stable_win64_console.exe"))
    ap.add_argument("--work", default=os.path.join(tempfile.gettempdir(), "lbbw_web_project"))
    ap.add_argument("--out", default=os.path.join(PROJECT, "build", "web"))
    ap.add_argument("--test", action="store_true",
                    help="also export debug builds that start in the garden and the facility (build/web_test)")
    a = ap.parse_args()
    log("copying the project to", a.work)
    copy_project(a.work)
    n = lighten_textures(a.work)
    web_project_settings(a.work)
    patch_files(a.work)
    log("lightened", n, "textures; importing (this takes a few minutes)")
    run(a.godot, ["--headless", "--path", a.work, "--import"], os.path.join(a.work, "import.log"))
    if os.path.isdir(a.out):
        shutil.rmtree(a.out)
    os.makedirs(a.out)
    log("exporting the Web preset")
    code = run(a.godot, ["--headless", "--path", a.work, "--export-release", "Web", os.path.join(a.out, "index.html")],
               os.path.join(a.work, "export.log"))
    if code != 0 or not os.path.exists(os.path.join(a.out, "index.pck")):
        log("export failed, see", os.path.join(a.work, "export.log"))
        sys.exit(1)
    total = 0
    too_big = []
    for f in sorted(os.listdir(a.out)):
        size = os.path.getsize(os.path.join(a.out, f)) / 1048576
        total += size
        log("  %8.2f MB  %s" % (size, f))
        if size > LIMIT_FILE_MB:
            too_big.append(f)
    log("total %.1f MB" % total)
    if too_big:
        log("files over %.0f MB (GitHub rejects files over 100 MB):" % LIMIT_FILE_MB, too_big)
        sys.exit(2)
    write_site_files(a.out)
    if a.test:
        export_test_builds(a)


VERCEL_JSON = """{
  "$schema": "https://openapi.vercel.sh/vercel.json",
  "framework": null,
  "buildCommand": null
}
"""


def write_site_files(out):
    """Static-hosting extras: GitHub Pages serves the folder as-is (no Jekyll), Vercel deploys
    it as a plain static site with no build step."""
    open(os.path.join(out, ".nojekyll"), "w").close()
    open(os.path.join(out, "vercel.json"), "w", encoding="utf-8").write(VERCEL_JSON)


def export_test_builds(a):
    """Builds whose start scene is the garden or the facility (release engines ignore scene
    arguments), for checking a scene in a browser: debug ones (script errors in the console)
    and a release one of the facility (realistic frame rate). Never deploy these."""
    test_root = os.path.join(PROJECT, "build", "web_test")
    if os.path.isdir(test_root):
        shutil.rmtree(test_root)
    proj = os.path.join(a.work, "project.godot")
    original = open(proj, encoding="utf-8").read()
    try:
        for scene, mode in (("world", "debug"), ("facility", "debug"), ("facility", "release")):
            name = scene if mode == "debug" else scene + "_release"
            out = os.path.join(test_root, name)
            os.makedirs(out)
            open(proj, "w", encoding="utf-8").write(re.sub(r'^run/main_scene=.*$', 'run/main_scene="res://scenes/%s/%s.tscn"' % (scene, scene), original, flags=re.M))
            code = run(a.godot, ["--headless", "--path", a.work, "--export-" + mode, "Web", os.path.join(out, "index.html")],
                       os.path.join(a.work, "export_test_%s.log" % name))
            log("test build %s: %s" % (name, "ok" if code == 0 else "FAILED"))
    finally:
        open(proj, "w", encoding="utf-8").write(original)


if __name__ == "__main__":
    main()
