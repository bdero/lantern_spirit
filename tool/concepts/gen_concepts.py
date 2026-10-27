#!/usr/bin/env python3
"""Concept art for the park map, the friend's room, and the dark app, from
Gemini's image model. Key from env GEMINI_API_KEY, GOOGLE_API_KEY, or
~/.gemini_key (never printed). Output in tool/concepts/out/<slug>.png (kept
out of the repo; the chosen concepts live with the mockups in the notes).

When Gemini is out of credits, the same PROMPTS work with Codex's built-in
image generation: codex exec -C tool/concepts --sandbox workspace-write
"Use your built-in image generation tool to create ONE image ... Brief: <prompt>".

Usage: gen_concepts.py [slug ...]   (no slugs = every missing one)
"""
import base64
import json
import os
import sys
import urllib.error
import urllib.request
from concurrent.futures import ThreadPoolExecutor
from io import BytesIO
from pathlib import Path

from PIL import Image

HERE = Path(__file__).resolve().parent
OUT = HERE / "out"
ENDPOINT = "https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent"
MODEL = "gemini-3.1-flash-image"

LOOK = (
    "Stylized real-time 3D game art, a handcrafted miniature diorama, soft "
    "tilt-shift depth of field, built from simple rounded primitive shapes "
    "(spheres, capsules, cylinders, rounded boxes) with soft clay and candy "
    "materials, gentle ambient occlusion, warm practical lights, cohesive "
    "limited palette, the polish of a Nintendo or Monument Valley title. "
    "Portrait phone framing, 9:16. No text, no UI, no watermark. "
)

CONCEPTS = {
    "map_a_dusk_lagoon": "9:16",
    "map_b_lantern_garden": "9:16",
    "map_c_storybook": "9:16",
    "room_a_cozy_nook": "9:16",
    "room_b_attic_observatory": "9:16",
    "room_c_lantern_greenhouse": "9:16",
    "app_dark_home": "9:16",
}

PROMPTS = {
    "map_a_dusk_lagoon": LOOK + (
        "A tiny theme park on a round floating island in a calm lagoon at blue "
        "hour, seen from above at 45 degrees. Bespoke ride landmarks: a red "
        "looping coaster with a little cart, a ferris wheel strung with warm "
        "bulbs, a tall slender drop tower topped with a glowing moon, a "
        "carousel under a striped canopy, a log flume river curling around a "
        "rock, spinning teacups. Winding cobbled paths with lamp posts, a "
        "welcome gate with an arch, small wooden bridges over a stream, "
        "picket fences, flower beds, layered round trees, park benches, food "
        "carts with awnings. The lagoon reflects every light. Palette: deep "
        "teal water, sage and moss greens, cream stone, coral red, warm "
        "lantern gold, dusky violet sky."),
    "map_b_lantern_garden": LOOK + (
        "A theme park map as a garden of paper lanterns: an island park at "
        "night with hundreds of small warm lanterns strung along winding "
        "paths and over the rides. Rides: a coaster loop, a ferris wheel, a "
        "drop tower with a moon on top, a carousel, a water flume, teacups. "
        "Each ride sits on its own little plinth of terraced grass and stone, "
        "with hedges, topiary, a fountain plaza in the middle, and a gate. "
        "Soft fog on the water, fireflies. Palette: midnight navy, deep "
        "forest green, warm amber light, cream, a touch of rose."),
    "map_c_storybook": LOOK + (
        "A storybook-style miniature park island in early evening, gentle "
        "pastel palette under a peach and lilac sky, seen from above. "
        "Winding sand paths with stepping stones, round bushy trees, a "
        "lighthouse at the edge, a carousel, a ferris wheel, a coaster loop, "
        "a moon drop tower, a log flume, teacups, little striped tents, "
        "bunting flags strung between lamp posts, a dock with tiny boats. "
        "Soft rim light, every surface rounded and toy-like."),
    "room_a_cozy_nook": LOOK + (
        "A cozy little bedroom nook for a glowing blue spirit character made "
        "of spheres (a translucent glowing blue head and body with orange "
        "ember hands), standing at the center. The room is a round floating "
        "platform with warm wooden floorboards and a soft round rug, a curved "
        "back wall with a big round window showing the moon and stars, "
        "string fairy lights draped along the wall, a small shelf with three "
        "hats on it (a beanie with a pom, a flower crown, a party hat), a "
        "plush round cushion bed with a folded blanket, a paper lantern floor "
        "lamp, potted plants, a small framed pinboard, a stack of books, "
        "floating dust motes in warm light. Night, warm and calm. Palette: "
        "deep navy and indigo, warm honey wood, peach, soft gold light."),
    "room_b_attic_observatory": LOOK + (
        "An attic observatory bedroom for a glowing blue spirit character "
        "made of spheres, standing at the center: a round floor of wooden "
        "planks under a sloped roof with a circular skylight full of stars, "
        "a small brass telescope on a tripod, a hammock cushion, a shelf of "
        "hats, a pinboard with star charts, a globe lamp, a rug, plants, "
        "fairy lights, a soft beam of moonlight with dust in it. Palette: "
        "midnight blue, warm walnut, brass, cream, soft gold."),
    "room_c_lantern_greenhouse": LOOK + (
        "A tiny round greenhouse room at night for a glowing blue spirit "
        "character made of spheres, standing at the center: curved glass "
        "panes framed in white iron, hanging plants, paper lanterns, a "
        "cushion bed among potted ferns, a shelf of hats, a little watering "
        "can, a rug, the moon outside the glass, fireflies. Palette: deep "
        "teal night, leafy greens, cream, warm lantern gold."),
    "app_dark_home": (
        "A polished dark-mode mobile app home screen mockup for a theme park "
        "app called Parkday, flat UI design straight on, phone portrait. Top: "
        "a tall rounded header showing a glowing blue cute spirit character "
        "made of spheres floating in a starry night gradient, with 'Good "
        "evening' in white. Below on a deep navy-charcoal background, "
        "elegant dark cards with subtle borders and soft glows: a 'Tonight' "
        "fireworks card with a photo, a 'Lagoon Key' reward card with a gold "
        "coin and a Collect button, a 'Play' card with two game tiles, a "
        "'Park map' card, and a 'Wait times' list. Tasteful, restrained, "
        "premium, Apple-quality typography, warm gold and cool blue accents. "
        "No watermark."),
}


def api_key():
    for env in ("GEMINI_API_KEY", "GOOGLE_API_KEY"):
        if os.environ.get(env):
            return os.environ[env].strip()
    p = Path.home() / ".gemini_key"
    return p.read_text().strip() if p.exists() else None


def generate(key, slug):
    dest = OUT / f"{slug}.png"
    body = json.dumps({
        "contents": [{"parts": [{"text": PROMPTS[slug]}]}],
        "generationConfig": {
            "responseModalities": ["IMAGE"],
            "imageConfig": {"aspectRatio": CONCEPTS[slug], "imageSize": "1K"},
        },
    }).encode()
    req = urllib.request.Request(
        ENDPOINT.format(model=MODEL), data=body,
        headers={"x-goog-api-key": key, "Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=300) as r:
            data = json.load(r)
    except urllib.error.HTTPError as e:
        return f"{slug}: FAILED HTTP {e.code}: {e.read()[:200].decode(errors='replace')}"
    except Exception as e:  # noqa: BLE001
        return f"{slug}: FAILED {e}"
    parts = data.get("candidates", [{}])[0].get("content", {}).get("parts", [])
    blob = next((p["inlineData"]["data"] for p in parts if p.get("inlineData")), None)
    if not blob:
        return f"{slug}: no image {json.dumps(data)[:200]}"
    Image.open(BytesIO(base64.b64decode(blob))).convert("RGB").save(dest, "PNG")
    return f"{slug}: ok"


def main():
    OUT.mkdir(exist_ok=True)
    key = api_key()
    if not key:
        print("no Gemini key")
        sys.exit(2)
    slugs = sys.argv[1:] or [s for s in CONCEPTS if not (OUT / f"{s}.png").exists()]
    with ThreadPoolExecutor(4) as ex:
        for line in ex.map(lambda s: generate(key, s), slugs):
            print(line)


if __name__ == "__main__":
    main()
