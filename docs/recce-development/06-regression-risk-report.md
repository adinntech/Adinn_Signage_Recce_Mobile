# 06 - Regression and integration risks

| Risk | Impact | Control |
|---|---|---|
| Project A has an offline Provider flow and a live server flow | Two data models side by side | Live flow in its own folders with its own models; old screens untouched |
| `RootGate` change | Could break widget tests that expect the PIN login | Minimal change; tests run before / after |
| New enum values and optional fields in the backend | Older clients (B, web) | Additive only; defaults keep old behaviour. Web `/recce-review` hard-coded category lists need a check |
| Installation required at submit | In-flight drafts from B cannot submit until installation is answered | B has no installation UI yet; decide whether to relax for clients that do not send `installation` |
| `requireGps` | Blocks submit when GPS is missing | Off by default; Admin config |
| **Review mode default changed to parallel (2026-11-23)** | New databases differ from existing ones; existing Atlas config still has `sequential: true` | Admin sends `PUT /recce-review/config {"sequential": false}` once; each version stores its own flag; `tests/recce-review.test.ts` forces `sequential: true` for its ordered cases |
| **Required photos default** | Out of the box only `SHOP_FRONT` + `NAME_BOARD` are required, not the six angles | Same one-time config call with `requiredPhotos.default` (09 section 0) |
| **Embedded model (one document per shop)** | Data from before 2026-11-23 is not read | `npx tsx scripts/purge-legacy-recce.ts` (dry run) then `--apply`; shops start fresh |
| Simultaneous decisions by both stages | Lost update / rollback | One compare-and-set update guarded by `rev` plus an "agreed" check; tested (approve + approve, reject + reject, approve + reject, approve + rework) |
| Thread message in parallel mode | Only the `pendingStage` (first stage) is notified | Known limit; both stages see the message in the thread |
| `change-decision` | Voids the other stage's waiting review and reopens the shop | Atomic update, history kept, tested; no mobile UI |
| Two editors in one file area (code or docs) | Half-converted code gave 500 errors on 2026-11-23 | One owner per file; run the suite after the other session finishes |
| Tests touching Atlas | Real data damage | Tests use in-memory MongoDB only (guard in place) |
| Vitest from Git Bash | "failed to find the runner" | Run tests from PowerShell |
| 22 older stale tests (known, not recce) | Noise | Compare before / after counts |
| PHP vendor mail, IMAP | Unrelated, unchanged | Not touched |
| Project B | Must stay unchanged | Read-only |
