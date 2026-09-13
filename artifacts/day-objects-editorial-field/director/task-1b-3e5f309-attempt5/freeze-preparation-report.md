# Task 1B Attempt 5 — Gate 8 Freeze Preparation

Status: `READY_FOR_INDEPENDENT_READ_ONLY_REVIEW`; no commit has been created.

Prepared at source HEAD `3e5f3095167889b3a9ae5a8145ef0103489e6e3c` in the clean `codex/editorial-gate4-authority-trace` worktree. No render, verifier rerun, full test rerun, source/material behavior edit, motion, Metal, main-canvas, or golden action occurred during freeze assembly.

## Ruling 21 preservation result

- The untouched central Critic A lock remains SHA-256 `a3e2cc6095ceaafc0cb91d3327d688d761135cad0d897d66319936fb32f90b4b`.
- The authoritative staged representation is `critics/critic-a-blind-lock.verbatim.base64`, deterministically wrapped at 76 columns with no trailing whitespace; payload SHA-256 `a03b606482cd0c71ae8e6d1dae8985246f4f165ee5c81d57483e7ac3874cb674`.
- Decoding the staged payload reproduces SHA-256 `a3e2cc6095ceaafc0cb91d3327d688d761135cad0d897d66319936fb32f90b4b`; byte comparison with the untouched central source exits `0`.
- `critics/critic-a-blind-lock.transcription.md` is explicitly marked non-authoritative and uses `<br>` in place of the three intentional trailing-space Markdown hard breaks.
- Critic B's lock and both exact verdicts remain ordinary byte-for-byte copies.
- Ruling 21 is preserved at `provenance/task-1b-ruling-21.md`; SHA-256 `ff2e04533ea1bdf7cac2c9b8f47d3ef6465859d459963b978fd3b573b279dc40`.

## Ruling 22 evidence-log closure

- Exactly `113` existing ignored `.log` files totaling `606700` bytes were force-added under this already allowlisted Attempt 5 director root.
- Every staged log compares byte-for-byte equal to its detached Attempt 5 source; no log was regenerated or edited.
- The staged checksum-reference resolver now reports `0` dead references; the prior review counterexample was exactly `105` dead references before these logs were added.

## Source-copy and immutable-package checks

- All four approved package roots pass `diff -qr` against the detached Attempt 5 source with exit `0` and no output.
- All 307 files that existed in the source Attempt 5 director root compare byte-equal to their copied paths.
- Candidate/rerender pair `diff -qr` passes independently at scale 1 and scale 3.
- Each package contains exactly 261 files.
- Scale-1 candidate/rerender package SHA-256: `09c092ed48a969c81145b789da7f123106c21b124020c3122de7fbd2bf508852`.
- Scale-3 candidate/rerender package SHA-256: `5a0c7a2251b1e9119155afc31049e51d280d8e76956a9113b469acc279487f57`.
- Scale-1 candidate/rerender recursive inventory SHA-256: `35d5f7e2b640e010b9e0726237801bc26135b39aff1479a2dd06cd8bf29656c0`.
- Scale-3 candidate/rerender recursive inventory SHA-256: `fc20e175697d53e0ccdb113db3ebb778c5d3d8e25f047ccdffe34f453228fd4b`.

## Approval and critic hashes

- `material-approved.json`: SHA-256 `0d6b21aff5c77096cd62b71cc5dd86a984e68db06ce761432eaef5e877fa5f65`; valid JSON; already in lexicographically sorted canonical form.
- `task-1b-report.md`: SHA-256 `78468dc7f34c176bfc89aa55b4d4856da432f569e9c48ee1cc7722e509c06a17`.
- Append-only `decision-ledger.md`: SHA-256 `c4f29123d2559b38f48b55b822188feb3758b734ca2bb8e501885c9206c5f083`.
- Critic A decoded lock SHA-256: `a3e2cc6095ceaafc0cb91d3327d688d761135cad0d897d66319936fb32f90b4b`.
- Critic A verdict SHA-256: `7abe10098cc7df087d889d41b17b7f7ed69f59e97209d69e92b2fd37ae9a56bf`.
- Critic B lock SHA-256: `0b489e08cdb38b0a3293c8cc3fa9910e0ad0743ff846e391a4f70fc0b907deb3`.
- Critic B verdict SHA-256: `38945eb15c6a1583308f387ef491c0b4c2e0d3351f735bbc808ea7d40c5c8144`.

## Exact staged allowlist and size

- Allowed roots only: the four package directories under `material/approved-3e5f309-attempt5/`, the copied `director/task-1b-3e5f309-attempt5/` root, `material/material-approved.json`, and the append-only `director/decision-ledger.md` update.
- Final staged paths: `1370` total; `1369` added and `1` modified.
- Final staged numstat: `157269` added lines, `000000` deleted lines, `1370` files.
- Final staged filesystem bytes: `191417554`.
- Final staged path-list SHA-256: `0941021807673d2a29abb74d2f0bd10de03199570fca4e23205c311445c9b557`.
- Largest individual file: `1,362,256` bytes, `scale3-rerender/renders/glass/11-glass-colors-03-lowContrast-layout-11-full@3x.png`.
- Files larger than 100 MB: `0`.
- Paths outside the strict allowlist: `0`.
- Forbidden baseline-package, `/private/tmp`, Attempt 3/4, Metal, canvas, and golden paths: `0`.
- Unstaged or untracked paths outside the index: `0`.
- `git diff --cached --check`: exit `0`, no output.

## Review boundary

The staged set is intentionally paused before commit. A fresh independent read-only review must verify the exact allowlist, canonical approval references, decoded Critic A bytes, both verdict hashes, copied package identity, report completeness, append-only ledger change, and no-production scope. Only a review PASS may authorize the thematic freeze commit and subsequent motion planning.
