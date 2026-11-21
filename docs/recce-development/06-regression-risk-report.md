# 06 - Regression and integration risks

| Risk | Impact | Control |
|---|---|---|
| Project A is an offline Provider app; the live flow is server-backed | Two data models side by side | Live flow in new folders with its own models; old screens untouched; offline demo link kept on login (user to confirm) |
| `RootGate` change | Could break existing widget tests that expect the PIN login | Gate change minimal; existing tests run before/after and results compared |
| New enum values / optional fields in backend | Older clients (B, web) | Only additive; no removed values; defaults keep old behaviour; installation required only at submit for new field data (existing web must be checked: web recce-review page hard-coded category lists) |
| Installation required at submit | Existing in-flight drafts from B cannot submit until installation is answered | B has no installation UI yet; decide whether to relax for clients that do not send `installation` (flagged in report) |
| `requireGps` | Blocks submit when GPS missing | Off by default; Admin config |
| Security | Mobile UI is not the boundary | Backend `mineFilter`/`mySite` and role checks; 404 for other vendor's shop |
| Tests touching Atlas | Real data damage | New tests follow the existing guard (memory rule) |
| 22 stale older tests (known) | Noise | Compare before/after counts |
| PHP vendor mail, IMAP | Unrelated, unchanged | Not touched |
| Project B | Must stay unchanged | Read-only; verified by file timestamps at the end |
