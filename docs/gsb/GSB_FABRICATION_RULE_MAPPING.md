# GSB Fabrication Rule Mapping (rulebook → Dart)

Engine: `lib/features/gsb/gsb_rules.dart`, `GsbRules.plan(GsbBoardInput)`. It is pure and deterministic and works in exact inches. `kGsbRuleVersion = 'SFR-1.0 (21 Nov 2026)'`.

| Section | Rule | Dart | Status |
|---|---|---|---|
| 01 | Inches; X width, Y height, Z depth (front = 0) | `In3`, `*In` fields | SPECIFIED |
| 01 | One member = one stable id | `GsbMember.id` (`M1.F.top`, `M2.V3.BRT` …) | SPECIFIED |
| 02/04/05 | 1 × 1 in MS SHS, 8 in depth | `GsbSpec` | SPECIFIED |
| 02 | Wall thickness not stated | `null` → `WALL_UNSPECIFIED` | REVIEW |
| 04 | Single: verticals on rear plane | z = depth − p/2 | SPECIFIED |
| 05 | Double: verticals at centre depth, tied to rails | z = depth/2 + `Vn.DT/DB` depth connectors | SPECIFIED |
| 04 | Single 9-in braces at top/bottom junctions | `brace`, nominal 9 | SPECIFIED (orientation REVIEW) |
| 05 | Double 4 + 4 in paired braces | 2 × `brace`, nominal 4 | SPECIFIED (orientation REVIEW) |
| 04/05 | Modular seam braces 4 in | `seamBrace` on seam rails only | SPECIFIED |
| 12 | Brace basis | `BRACE_BASIS_REVIEW` | REVIEW |
| 10 | Even ft → 24-in bays; odd ft → 18/24…/18 | `supportStations()` | SPECIFIED |
| 10 | 20×7, 18×7, 17×7 (mirrored, no 0.5-ft bay) | reference handling | EXAMPLE |
| 10 | Fractional modules (10 ft 8 in) | `SUPPORT_SPACING_REVIEW`, no verticals | REVIEW |
| 09 | Height split ≥ 5 ft, width > 15 ft, reference layouts win | `widthColumns()` / `heightRows()` | EXAMPLE |
| 09/21 | Unlisted partitions | `HEIGHT/WIDTH_SPLIT_REVIEW`, outer frame only | REVIEW |
| 11 | Extra horizontal when module H > 4 ft | `extraHorizontal` | SPECIFIED (elevation REVIEW) |
| 11 | Depth stations <3 ft / H/2 / H/3 + 2H/3 | `depthStations()` | SPECIFIED |
| 12 | Insert 0.75 × 0.75 × 24, 12 in each side | `GsbCouplingInsert`, `INSERT_FIT_REVIEW` / `INSERT_CLASH` | SPECIFIED + REVIEW |
| 13 | Rear GI (Single), 24/30/36/48, 6-in laps | `giTiersIn` (8×5 → 30+36, 21×7 → 30+30+36) | EXAMPLE / `GI_PLAN_REVIEW` |
| 14 | Trim 99-in max, 2-in overlap, 4 sides | `trimPieces()` | SPECIFIED |
| 05/15 | One physical LED set, never doubled | `physicalLedSets == 1` | SPECIFIED |
| 15 | Both faces glowing from one set | `DOUBLE_OPTICS_REVIEW` | REVIEW |
| 03 | Keys `GSB_SINGLE` / `GSB_DOUBLE` | `GsbVariant.key`, `Board.gsbVariantKey` | SPECIFIED |

Not implemented (not requested or not specified): LED tube planner, wiring, GLB fasteners, BOM export, Separated View, Lit / Non Lit / Non-Lit Box, standees.
