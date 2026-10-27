// Bends the whole app around an expanding ring: a sneeze's ripple (several
// crests, like water) or a lantern pulse's heat haze (one soft crest with a
// warm glint). Runs as an ImageFilter over everything on screen.

#include <flutter/runtime_effect.glsl>

uniform vec2 uSize;
// Where the ring starts, in pixels.
uniform vec2 uCenter;
// The ring's radius and half width, in pixels.
uniform float uRadius;
uniform float uWidth;
// How far the crests push the picture, in pixels.
uniform float uAmp;
// How many crests fit across the ring's width.
uniform float uWaves;
// A warm glow added along the crest, 0 for none.
uniform float uTint;

uniform sampler2D uTex;

out vec4 fragColor;

vec4 sampleAt(vec2 p) {
  vec2 uv = p / uSize;
#ifdef IMPELLER_TARGET_OPENGLES
  uv.y = 1.0 - uv.y;
#endif
  return texture(uTex, clamp(uv, vec2(0.0), vec2(1.0)));
}

void main() {
  vec2 p = FlutterFragCoord().xy;
  vec2 d = p - uCenter;
  float r = length(d);
  vec2 n = r > 0.001 ? d / r : vec2(0.0);
  float x = (r - uRadius) / max(uWidth, 1.0);
  float env = exp(-x * x * 2.2);
  float wave = sin(x * 3.14159 * uWaves);
  float push = wave * env * uAmp;
  vec2 q = p - n * push;
  // A faint split of red and blue along the crest, like light through water.
  float split = env * abs(uAmp) * 0.12;
  vec4 c = sampleAt(q);
  c.r = sampleAt(q - n * split).r;
  c.b = sampleAt(q + n * split).b;
  // Crests catch the light.
  float lit = max(wave, 0.0) * env;
  c.rgb += vec3(1.0, 0.78, 0.45) * lit * uTint * c.a;
  c.rgb *= 1.0 + 0.06 * wave * env * step(0.001, uAmp);
  fragColor = c;
}
