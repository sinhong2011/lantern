# Lantern Journey Polish — Design

**Date:** 2026-09-10  
**Approach:** Journey polish (small, dense) — copy, feedback, motion, one-click recovery. No engine rewrite.

## Goals

Make every step feel attended-to: empty → add → broadcast → copy → recover from proxy bind failure.

## Scope

| Area | Change |
|------|--------|
| Empty state | Warm OrbStack framing + primary Add + secondary sample `web:8080` |
| Add sheet | Live URL preview, inline validation, clearer hints |
| Service row | Copy → check feedback ~1.2s; keep hover actions |
| Errors | Humanized proxy bind copy; banner CTA **Use 8787** when port 80 fails |
| Toast | Brief confirmation for copy / sample add |
| Status | Pill reflects live / waiting / attention; proxy port when relevant |
| Motion | Soft springs + symbol effects; respect Reduce Motion |
| Settings | Scrollable glass sections (already shipped) |

## Out of scope

Port scanning, first-run tutorial overlay, Raycast, aggressive notifications.
