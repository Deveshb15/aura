#!/usr/bin/env python3
"""
Generates the Aura app icon — "Notch Sprite" concept.
Emits a standalone, self-contained SVG (aura-icon.svg) + an HTML wrapper
(preview.html) used to drive a headless-Chrome screenshot.

All artwork is pure vector (no external assets/fonts). 1024x1024 canvas.
"""
import math
import os

SIZE = 1024
CX = CY = SIZE / 2


def sgn(v):
    return (v > 0) - (v < 0)


def squircle(cx, cy, r, n=5.0, steps=192):
    """iOS-style superellipse (continuous-curvature rounded square)."""
    pts = []
    for i in range(steps):
        t = 2 * math.pi * i / steps
        ct, st = math.cos(t), math.sin(t)
        x = cx + r * (abs(ct) ** (2 / n)) * sgn(ct)
        y = cy + r * (abs(st) ** (2 / n)) * sgn(st)
        pts.append((x, y))
    d = "M%.2f,%.2f " % pts[0] + " ".join("L%.2f,%.2f" % p for p in pts[1:]) + " Z"
    return d


def rrect(x, y, w, h, rtl, rtr, rbr, rbl):
    """Rounded rectangle path with independent per-corner radii (circular arcs)."""
    return (
        f"M{x+rtl:.1f},{y:.1f} "
        f"L{x+w-rtr:.1f},{y:.1f} A{rtr:.1f},{rtr:.1f} 0 0 1 {x+w:.1f},{y+rtr:.1f} "
        f"L{x+w:.1f},{y+h-rbr:.1f} A{rbr:.1f},{rbr:.1f} 0 0 1 {x+w-rbr:.1f},{y+h:.1f} "
        f"L{x+rbl:.1f},{y+h:.1f} A{rbl:.1f},{rbl:.1f} 0 0 1 {x:.1f},{y+h-rbl:.1f} "
        f"L{x:.1f},{y+rtl:.1f} A{rtl:.1f},{rtl:.1f} 0 0 1 {x+rtl:.1f},{y:.1f} Z"
    )


def star4(cx, cy, r, w):
    """A 4-point sparkle (concave diamond) centered at cx,cy with outer radius r."""
    return (
        f"M{cx:.1f},{cy-r:.1f} "
        f"Q{cx:.1f},{cy-w:.1f} {cx+w:.1f},{cy:.1f} "
        f"Q{cx:.1f},{cy+w:.1f} {cx:.1f},{cy+r:.1f} "
        f"Q{cx:.1f},{cy+w:.1f} {cx-w:.1f},{cy:.1f} "
        f"Q{cx:.1f},{cy-w:.1f} {cx:.1f},{cy-r:.1f} Z"
    )


# ---- geometry ---------------------------------------------------------------
TILE_R = 466                      # squircle half-size
tile_path = squircle(CX, CY, TILE_R, n=5.0)

# Notch sprite body: wide form, flat-ish top corners, very round bottom (NotchShape)
BW, BH = 470, 342
BX, BY = CX - BW / 2, 314
body_path = rrect(BX, BY, BW, BH, rtl=58, rtr=58, rbr=160, rbl=160)
BODY_CX, BODY_CY = CX, BY + BH / 2

# eyes
EYE_DX, EYE_Y = 100, 470
EYE_RX, EYE_RY = 51, 60
PUP_RX, PUP_RY = 27, 33
PUP_Y = EYE_Y + 8

# ---- svg --------------------------------------------------------------------
svg = f'''<svg xmlns="http://www.w3.org/2000/svg" width="{SIZE}" height="{SIZE}" viewBox="0 0 {SIZE} {SIZE}">
  <defs>
    <linearGradient id="tileGrad" x1="0.12" y1="0" x2="0.88" y2="1">
      <stop offset="0" stop-color="#2c2470"/>
      <stop offset="0.45" stop-color="#171339"/>
      <stop offset="1" stop-color="#070611"/>
    </linearGradient>
    <radialGradient id="auraCore" cx="0.5" cy="0.5" r="0.5">
      <stop offset="0" stop-color="#d6c9ff" stop-opacity="0.92"/>
      <stop offset="0.45" stop-color="#9a7cf8" stop-opacity="0.55"/>
      <stop offset="1" stop-color="#8b6cf8" stop-opacity="0"/>
    </radialGradient>
    <radialGradient id="auraBlue" cx="0.5" cy="0.5" r="0.5">
      <stop offset="0" stop-color="#7fb0ff" stop-opacity="0.9"/>
      <stop offset="0.55" stop-color="#4f7cff" stop-opacity="0.38"/>
      <stop offset="1" stop-color="#4f7cff" stop-opacity="0"/>
    </radialGradient>
    <radialGradient id="auraMag" cx="0.5" cy="0.5" r="0.5">
      <stop offset="0" stop-color="#ef6cf3" stop-opacity="0.88"/>
      <stop offset="0.55" stop-color="#c23cf0" stop-opacity="0.34"/>
      <stop offset="1" stop-color="#c23cf0" stop-opacity="0"/>
    </radialGradient>
    <linearGradient id="bodyDepth" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="#000000" stop-opacity="0"/>
      <stop offset="0.62" stop-color="#000000" stop-opacity="0"/>
      <stop offset="1" stop-color="#000008" stop-opacity="0.55"/>
    </linearGradient>
    <linearGradient id="notchGrad" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="#191926"/>
      <stop offset="0.55" stop-color="#0b0b14"/>
      <stop offset="1" stop-color="#020205"/>
    </linearGradient>
    <linearGradient id="rimGrad" x1="0" y1="0" x2="1" y2="1">
      <stop offset="0" stop-color="#7da7ff"/>
      <stop offset="0.5" stop-color="#9a6cf6"/>
      <stop offset="1" stop-color="#e24ad6"/>
    </linearGradient>
    <radialGradient id="sheen" cx="0.5" cy="0.32" r="0.62">
      <stop offset="0" stop-color="#ffffff" stop-opacity="0.16"/>
      <stop offset="0.55" stop-color="#ffffff" stop-opacity="0.04"/>
      <stop offset="1" stop-color="#ffffff" stop-opacity="0"/>
    </radialGradient>
    <radialGradient id="specGrad" cx="0.5" cy="0.5" r="0.5">
      <stop offset="0" stop-color="#cdd6ff" stop-opacity="0.5"/>
      <stop offset="1" stop-color="#cdd6ff" stop-opacity="0"/>
    </radialGradient>
    <radialGradient id="eyeGlint" cx="0.5" cy="0.5" r="0.5">
      <stop offset="0" stop-color="#b98bff" stop-opacity="1"/>
      <stop offset="1" stop-color="#b98bff" stop-opacity="0"/>
    </radialGradient>

    <filter id="tileShadow" x="-30%" y="-30%" width="160%" height="160%">
      <feDropShadow dx="0" dy="20" stdDeviation="26" flood-color="#000000" flood-opacity="0.55"/>
    </filter>
    <filter id="auraBlur" x="-60%" y="-60%" width="220%" height="220%">
      <feGaussianBlur stdDeviation="40"/>
    </filter>
    <filter id="blur18" x="-60%" y="-60%" width="220%" height="220%">
      <feGaussianBlur stdDeviation="18"/>
    </filter>
    <filter id="blur8" x="-60%" y="-60%" width="220%" height="220%">
      <feGaussianBlur stdDeviation="8"/>
    </filter>
    <filter id="rimGlow" x="-30%" y="-30%" width="160%" height="160%">
      <feGaussianBlur stdDeviation="2.4"/>
    </filter>
    <filter id="sparkGlow" x="-120%" y="-120%" width="340%" height="340%">
      <feGaussianBlur stdDeviation="3"/>
    </filter>

    <clipPath id="tileClip"><path d="{tile_path}"/></clipPath>
    <clipPath id="bodyClip"><path d="{body_path}"/></clipPath>
  </defs>

  <!-- tile + soft studio shadow -->
  <path d="{tile_path}" fill="url(#tileGrad)" filter="url(#tileShadow)"/>

  <g clip-path="url(#tileClip)">
    <!-- top studio sheen -->
    <rect x="0" y="0" width="{SIZE}" height="{SIZE}" fill="url(#sheen)"/>

    <!-- AURA: the hero glow — directional aurora (cool upper-left, warm lower-right) -->
    <circle cx="{BODY_CX-104}" cy="{BODY_CY-72}" r="320" fill="url(#auraBlue)" filter="url(#auraBlur)"/>
    <circle cx="{BODY_CX+120}" cy="{BODY_CY+126}" r="320" fill="url(#auraMag)" filter="url(#auraBlur)"/>
    <circle cx="{BODY_CX}" cy="{BODY_CY+14}" r="300" fill="url(#auraCore)" filter="url(#auraBlur)"/>
    <circle cx="{BODY_CX}" cy="{BODY_CY+18}" r="410" fill="none" stroke="url(#rimGrad)" stroke-width="3" opacity="0.20" filter="url(#rimGlow)"/>
    <circle cx="{BODY_CX}" cy="{BODY_CY+18}" r="454" fill="none" stroke="url(#rimGrad)" stroke-width="2" opacity="0.10" filter="url(#rimGlow)"/>

    <!-- ambient sparkles behind -->
    <path d="{star4(770,322,26,8)}" fill="#dfe6ff" opacity="0.85" filter="url(#sparkGlow)"/>
    <path d="{star4(286,690,30,9)}" fill="#e9c6ff" opacity="0.8" filter="url(#sparkGlow)"/>
    <path d="{star4(742,706,18,6)}" fill="#cdd9ff" opacity="0.7" filter="url(#sparkGlow)"/>

    <!-- contact shadow under sprite -->
    <ellipse cx="{BODY_CX}" cy="{BY+BH-6}" rx="196" ry="40" fill="#05030f" opacity="0.45" filter="url(#blur18)"/>

    <!-- sprite body -->
    <path d="{body_path}" fill="url(#notchGrad)"/>
    <!-- clay volume: top specular highlight + bottom depth (clipped to body) -->
    <g clip-path="url(#bodyClip)">
      <path d="{body_path}" fill="url(#bodyDepth)"/>
      <ellipse cx="{BX+158}" cy="{BY+66}" rx="178" ry="96" fill="url(#specGrad)" opacity="0.95" filter="url(#blur8)"/>
      <ellipse cx="{BX+BW-72}" cy="{BY+38}" rx="84" ry="42" fill="#aab4ff" opacity="0.12" filter="url(#blur8)"/>
    </g>
    <!-- aura rim-light wrapping the black body (signature premium detail) -->
    <path d="{body_path}" fill="none" stroke="url(#rimGrad)" stroke-width="15" opacity="0.40" filter="url(#blur8)"/>
    <path d="{body_path}" fill="none" stroke="url(#rimGrad)" stroke-width="6" opacity="1" filter="url(#rimGlow)"/>
    <path d="{body_path}" fill="none" stroke="#ffffff" stroke-width="1.4" opacity="0.12"/>

    <!-- face -->
    <!-- blush -->
    <ellipse cx="{BODY_CX-EYE_DX-12}" cy="538" rx="24" ry="13" fill="#ff79d6" opacity="0.18"/>
    <ellipse cx="{BODY_CX+EYE_DX+12}" cy="538" rx="24" ry="13" fill="#ff79d6" opacity="0.18"/>
    <!-- eyes -->
    <ellipse cx="{BODY_CX-EYE_DX}" cy="{EYE_Y}" rx="{EYE_RX}" ry="{EYE_RY}" fill="#ffffff"/>
    <ellipse cx="{BODY_CX+EYE_DX}" cy="{EYE_Y}" rx="{EYE_RX}" ry="{EYE_RY}" fill="#ffffff"/>
    <ellipse cx="{BODY_CX-EYE_DX}" cy="{PUP_Y}" rx="{PUP_RX}" ry="{PUP_RY}" fill="#0a0a16"/>
    <ellipse cx="{BODY_CX+EYE_DX}" cy="{PUP_Y}" rx="{PUP_RX}" ry="{PUP_RY}" fill="#0a0a16"/>
    <!-- catchlights -->
    <circle cx="{BODY_CX-EYE_DX-11}" cy="{PUP_Y-13}" r="12" fill="#ffffff"/>
    <circle cx="{BODY_CX+EYE_DX-11}" cy="{PUP_Y-13}" r="12" fill="#ffffff"/>
    <!-- aura glints -->
    <circle cx="{BODY_CX-EYE_DX+14}" cy="{PUP_Y+15}" r="9" fill="url(#eyeGlint)"/>
    <circle cx="{BODY_CX+EYE_DX+14}" cy="{PUP_Y+15}" r="9" fill="url(#eyeGlint)"/>
    <!-- smile -->
    <path d="M{BODY_CX-38},560 Q{BODY_CX},594 {BODY_CX+38},560" fill="none" stroke="#dcc8ff" stroke-width="11" stroke-linecap="round"/>

    <!-- captured spark being pulled into the vault -->
    <path d="{star4(BODY_CX,272,30,9)}" fill="#ffffff" filter="url(#sparkGlow)"/>
    <path d="{star4(BODY_CX,272,22,6)}" fill="#ffffff"/>

    <!-- crisp top rim of tile (echoes the notch's white border) -->
    <path d="{tile_path}" fill="none" stroke="#ffffff" stroke-width="2" opacity="0.07"/>
  </g>
</svg>
'''

OUT_DIR = os.path.dirname(os.path.abspath(__file__))
with open(os.path.join(OUT_DIR, "aura-icon.svg"), "w") as f:
    f.write(svg)

html = f'''<!doctype html><html><head><meta charset="utf-8">
<style>html,body{{margin:0;padding:0;background:transparent}}
#w{{width:{SIZE}px;height:{SIZE}px}}</style></head>
<body><div id="w">{svg}</div></body></html>'''
with open(os.path.join(OUT_DIR, "preview.html"), "w") as f:
    f.write(html)

print("wrote aura-icon.svg + preview.html")
