#!/usr/bin/env bash
# Renders a flat status badge (shields.io look-alike) as SVG to stdout.
# Self-hosted replacement for shields.io badges, whose GitHub integrations
# intermittently fail with "Unable to select next GitHub token from pool".
#
# Usage: badge.sh LABEL VALUE COLOR     e.g. badge.sh staging passing "#4c1"
set -euo pipefail

[[ $# -eq 3 ]] || { echo "usage: badge.sh LABEL VALUE COLOR" >&2; exit 1; }
label="$1"
value="$2"
color="$3"

# ~7px per character + padding approximates Verdana 11px well enough.
lw=$(( ${#label} * 7 + 14 ))
vw=$(( ${#value} * 7 + 14 ))
w=$(( lw + vw ))

cat <<SVG
<svg xmlns="http://www.w3.org/2000/svg" width="$w" height="20" role="img" aria-label="$label: $value">
  <linearGradient id="g" x2="0" y2="100%">
    <stop offset="0" stop-color="#bbb" stop-opacity=".1"/>
    <stop offset="1" stop-opacity=".1"/>
  </linearGradient>
  <rect rx="3" width="$w" height="20" fill="#555"/>
  <rect rx="3" x="$lw" width="$vw" height="20" fill="$color"/>
  <rect rx="3" width="$w" height="20" fill="url(#g)"/>
  <g fill="#fff" text-anchor="middle" font-family="Verdana,Geneva,sans-serif" font-size="11">
    <text x="$(( lw / 2 ))" y="14">$label</text>
    <text x="$(( lw + vw / 2 ))" y="14">$value</text>
  </g>
</svg>
SVG
