# GSB Pending Engineering Reviews

The app shows these as **Requires Engineering Review** and does not invent geometry for them.

| Code | Item | Current app behaviour |
|---|---|---|
| `HEIGHT_SPLIT_REVIEW` | Height partition for GSB ≥ 5 ft other than 7 / 8 / 10 / 16 ft (e.g. 8×5, 6 ft, 15 ft) | Outer frame only |
| `WIDTH_SPLIT_REVIEW` | Widths > 15 ft other than 16 / 17 / 18 / 20 / 32 / 40 / 50 ft | Outer frame only |
| `SUPPORT_SPACING_REVIEW` | Fractional module widths (10 ft 8 in) or non-whole-foot unsplit widths | No internal verticals |
| `BRACE_BASIS_REVIEW` | 9 / 4 in = diagonal or leg? Brace orientation | Drawn as diagonal, illustrative |
| info | Single: 9-in braces at side-depth / width-support joints | Not generated (locations unknown) |
| `EDGE_BAY_HORIZONTAL_REVIEW` | Edge-bay bracing > 4 ft; extra-horizontal elevation | Extra horizontal at module depth-station level (provisional) |
| `INSERT_FIT_REVIEW` / `INSERT_CLASH` | 0.75 in insert inside 1 in SHS needs real wall thickness | Fit not confirmed / error if too thick |
| `WALL_UNSPECIFIED` | Pipe wall thickness | "Unspecified – requires engineering confirmation" |
| `GI_PLAN_REVIEW` | GI tiers beyond 8×5 / 21×7, including the 8-ft 48+48 vs 6-in lap conflict | No GI plan |
| `DOUBLE_OPTICS_REVIEW` | Both faces lit by one LED set | Illustrative glow + disclaimer |
| `DEPTH_/PROFILE_OVERRIDE_REVIEW` | Vendor overrides | Provisional preview, reason stored, reversible |
| `RECORDED_DEPTH_DIFFERS` | Recorded site depth ≠ 8 in | Kept as recorded and flagged |
| `VARIANT_NOT_CONFIRMED` | Old GSB without explicit choice | Shown as Single until confirmed |
| – | Weld size, grade, loads, anchors, electrical safety | Professional sign-off required |
