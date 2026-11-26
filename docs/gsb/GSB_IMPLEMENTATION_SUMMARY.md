# GSB Implementation Summary

## Changes by feature
1. **GSB board type popup.** Tapping GSB opens *Select GSB Board Type* (Single / Double cards; Continue is enabled only after a choice; Cancel changes nothing). The saved choice is restored when the sheet reopens. The old bottom control is replaced for GSB by a summary card with **Change**. NLB is unchanged.
2. **State mapping.** `Board.doubleSided` stays the stored field. `GSB_SINGLE` / `GSB_DOUBLE` is derived (`Board.gsbVariantKey`, `GsbBoard.variantOf`). Media category stays `GSB`.
3. **Rule engine.** `gsb/gsb_rules.dart` covers modules, supports, braces, depth stations, inserts, trim, GI and review issues (see the rule mapping doc).
4. **Live Preview.** The distortion fixes are in the audit doc. **Render View** (Day/Night, GSB only) sits next to the unit chips. Night is a photo colour grade plus darker sky plus glow on the lit faces, with the same transforms. On Save (GSB) the existing capture is kept, plus day PNG, night PNG and a 4-page PDF (original, day with dimensions, night, side-by-side). Progress text, Retry on failure, and an OPEN PDF action are included. The viewer has a PDF button.
5. **Camera AR.** Render View button (GSB, ARCore engine). Native night grade on the camera background and models (lit faces stay bright). The GSB capture renders ONE camera frame as original / day / night and saves all three plus the same 4-page PDF. Labelled as world-tracked ARCore.
6. **3D Preview.** Exact `ft in` field beside Width, Height and Mounting height. Parse, validate, sync with the slider; the range grows instead of clamping; only Apply commits; Cancel restores. A note about stale previews appears after a size change. GSB gets: Day/Night toggle (soft blue, camera kept), **Fabrication frame** view built from the engine members, and a GSB panel showing depth, profile, wall thickness (unspecified), modules, members, cladding and review items.
7. **Overrides.** *Edit / Override*: field, default and current values, proposed value, mandatory reason (with suggestions), "Requires Engineering Review" status, provisional preview, history, Revert. Stored in `Board.gsbOverrides` with user, project, task, shop, board, timestamp and rule version.
8. **Defaults.** GSB depth 8 in (catalog was 9 in), GSB frame 1 in (was 40 mm).

## Data / API compatibility
No backend exists. New JSON fields are optional (`gsbOverrides`, derived `boardVariant`, extra `PreviewCapture.info` keys `renderMode`, `boardVariant`, `sizeIn`, `dayPath`, `nightPath`, `originalPath`, `comparisonPdf`). Older data parses unchanged. No schema version bump was needed.

## Engineering assumptions (flagged in-app)
Braces drawn with the nominal size as the diagonal. Extra horizontal sits at the module depth-station level. Double seam braces lie in the depth plane. Modules of whole-foot widths use the module-local even/odd rule (derived). AR night has no sky gradient (whole-frame grade only).
