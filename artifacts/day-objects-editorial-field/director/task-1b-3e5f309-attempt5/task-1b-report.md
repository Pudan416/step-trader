# Day Objects Editorial Field — Task 1B Material Freeze Report

Status: Gate 8 freeze prepared after two independent aesthetic PASS verdicts. This report does not authorize motion until the staged freeze receives an independent review and is committed.

Approval timestamp: `2026-09-04T02:42:18Z`.

## Source and frozen inputs

- Exact accepted source commit: `3e5f3095167889b3a9ae5a8145ef0103489e6e3c` (`test(editorial-field): separate visual measurement mode`).
- Task 1A accepted material source: `5a6931096deeba9ea1efaa29bc1c9418c4da751c`.
- Gate 4 authority-schema commit: `ee7cdf668da15ab97f752f718e5cbd358c5f95b4`.
- Gate 4 measurement-only test-seam correction: `3e5f3095167889b3a9ae5a8145ef0103489e6e3c`.
- Ruling 14 admitted the exact two-file correction after focused GREEN and a clean independent scoped re-review. Attempt 5 then began from a tracked-clean detached checkout with clean unstaged and staged diff checks.
- Visible manifest: `Tools/DayObjectsEditorialField/Manifests/visible-v1.json`; SHA-256 `3ce4e38005b3c262cd76ca58a8cd169e38f0a23aa2df70a8437ebb134bed52c9`.
- Composition approval: `artifacts/day-objects-editorial-field/composition/composition-approved.json`; SHA-256 `c4f4c95c2431701587a3c366dcc4d82ae21b9a5735d840a995a0aae52346124c`.
- Frozen recipes: `artifacts/day-objects-editorial-field/composition/composition-recipes-approved.json`; SHA-256 `7faef26a612768b67b73b520c7889e569594516bde3745f8a75b4ff2a24aeccd`.
- Renderer source SHA-256: `e2170a3f1f3a9798bd857f059fdee9b53b0fb2e1d4f16754f244a62236a2d543`.

The complete producer record is preserved as `producer-progress.md`; its source-byte copy was verified against the detached Attempt 5 worktree before staging.

## Gate 0 — full sandbox

Exact command:

```text
swift test --package-path Tools/DayObjectsEditorialField
```

- Started `2026-09-03T22:06:09Z`; ended `2026-09-03T23:31:27Z`; wrapper duration `5118s`.
- Result: exit `0`; `111/111` tests in `5/5` suites passed; `0` failures/issues; framework duration `5076.237s`; `/usr/bin/time -l` wall time `5108.36s`.
- Maximum resident set size: `4,068,261,888` bytes; process swaps `0`.
- VM monitor: `510` samples, cumulative `Swapouts` stayed exactly `915659` for delta `0`; `Pages throttled` stayed `0`; resource-breach flag `0`.
- Tracked checkout and frozen source/input hashes remained unchanged after the suite; both diff checks remained clean.

Gate 0 immutable logs:

| Evidence | SHA-256 |
| --- | --- |
| `logs/preflight.log` | `86badb5c27b18eb321c50cdac87e8977c5dca585a8587901531fa04b829a4439` |
| `logs/full-suite.log` | `814cd317a1e6c1e9123cdd5021c13b9b0ab3b2742972cfabc8bb60dc94319516` |
| `logs/full-suite.exit` | `d308957c02525d520422f99172fb29412e8c57f42c2d024ac88dbf67df52bd33` |
| `logs/resource-baseline.log` | `95eb5dcc3ea12fb2f5493e06df2bbbce9288e517dee0425683c83b36cf676c99` |
| `logs/resource-monitor.log` | `d18a4f00e23a88eb6688b852a4685a941f4bda3271f8a282fc33e3409a167d8c` |
| `logs/resource-end.log` | `01a814cf5ad375bbbcd5fc87a540829286a5829d0239cb024bfcc79a3b792f34` |
| `logs/postflight.log` | `7f868432e49ba1166dd9f110aeeca84400e24117bdb19ab4936ef1c489e1fd24` |

## Gates 1 and 5 — immutable packages and rerender identity

Each fixed package was created once. Each candidate and rerender passed initial verification, a disposable one-byte tamper rejection, untouched checksum verification, and a final independent untouched verification. The copied package roots were then checked with `diff -qr` against their immutable Attempt 5 sources; all four comparisons exited `0` with no output.

| Package | Files | Package SHA-256 | Recursive inventory SHA-256 | Final verifier output SHA-256 |
| --- | ---: | --- | --- | --- |
| `material/approved-3e5f309-attempt5/scale1-candidate` | 261 | `09c092ed48a969c81145b789da7f123106c21b124020c3122de7fbd2bf508852` | `35d5f7e2b640e010b9e0726237801bc26135b39aff1479a2dd06cd8bf29656c0` | `4802c8eff91c1989ab2be023897a8200032d4a43cad53ede8e548a379d9cca6b` |
| `material/approved-3e5f309-attempt5/scale1-rerender` | 261 | `09c092ed48a969c81145b789da7f123106c21b124020c3122de7fbd2bf508852` | `35d5f7e2b640e010b9e0726237801bc26135b39aff1479a2dd06cd8bf29656c0` | `fdf6f966ac5fb6ee19a005754ed80350cfa3ab0c003952e141e0c31061e23dbc` |
| `material/approved-3e5f309-attempt5/scale3-candidate` | 261 | `5a0c7a2251b1e9119155afc31049e51d280d8e76956a9113b469acc279487f57` | `fc20e175697d53e0ccdb113db3ebb778c5d3d8e25f047ccdffe34f453228fd4b` | `60a37a9382a6736732f57bf9d8cbd2ad4d84f955df048a564a2d4d5c3e70de18` |
| `material/approved-3e5f309-attempt5/scale3-rerender` | 261 | `5a0c7a2251b1e9119155afc31049e51d280d8e76956a9113b469acc279487f57` | `fc20e175697d53e0ccdb113db3ebb778c5d3d8e25f047ccdffe34f453228fd4b` | `86b38eb85591ab75e8f3b607ae7b31fbda39ce70d2c068505493089a3c2775b0` |

Scale-1 and scale-3 candidate/rerender pairs are recursively byte-identical. Their `diff -qr` records have zero output; relative inventories, recursive hashes, package ledgers, package-hash files, manifests, metrics, approval bytes, and recipe bytes agree. The 162 native scene-scale images and the canonical authority objects are also identical across scale-1 and scale-3 candidates.

## Tamper rejection

For each of the four packages, the producer copied the package to `/private/tmp`, changed exactly byte offset `128` of `contact-sheets/material-atlas.png` from decimal `64` to `65`, and confirmed exactly one byte and one file differed. Each tampered verifier invocation returned the expected exit `1` with `Material artifact hash mismatch: contact-sheets/material-atlas.png`. The untouched source package subsequently passed all `259` checksum records and final verification.

The disposable `/private/tmp` package copies are not included in this freeze. Only their mutation and disposition records are preserved under `tamper/`.

## Gates 2–5 — semantic and presentation authority

- Corrected read-only semantic audit: `audit/gates2-5/audit.swift`; SHA-256 `73a9ef304764161b2172c316a254a8b1ca7dc6f961e2b480cd448d89c5e745b2`.
- Accepted audit output: `commands/gates2-5-semantic-audit-v2/output.log`; SHA-256 `f6209030be307fb3cc0e47b365b5471fbda5d0a1e5cfeadd24a476fe0e4b18d4`; exit `0`; `AUDIT: PASS`; resource breach `0`.
- Each package contains exactly `261` files: `81` scene-scale records / `162` native scene PNGs, `18` native outline PNGs, `27` family actor crops, `6` exact-topology crops, `6` canonical outline fixtures, and `5` contact sheets.
- All `81/81` full-to-tile normalized RGBA crop comparisons pass for each candidate; full frames are `393x852`, tiles are `393x393`, crop `{x:0,y:229,width:393,height:393}`.
- Metrics schema: `material-metrics-v9`; authority schema: `outline-presentation-authority-v1`.
- Authority inventory: `90` actor-condition records over `9` same-render invocations, draw orders `0...9`, source scale `2`, presentation scale `1`, exact full/tile paths, crop, actor identity, and trace digests.
- Canonical cross-scale authority aggregate SHA-256: `444e251af9e720ebbc5f44981ed5a0dda9d4a66272f10460d899d035da676ad7`.
- Native scene aggregate SHA-256: `637d31ea0975afd83cc058342a6f345f4ff814062a7a3f916e7b0007718b50d0`.

The first semantic audit failure is preserved. It was a producer-harness enumeration error caused by `.skipsHiddenFiles` on a package inside a hidden worktree, not package drift. Ruling 17 authorized the corrected enumerator after a focused hidden-flag fixture self-test; no package byte was modified or resealed.

## Gate 6 — baseline-only provenance and blind packet

The baseline is comparison evidence only and is not authority evidence. Its package was not copied or staged.

- Exact baseline source commit: `622b7b50e0a4594ab47889a2265748e51e94e523`.
- Baseline renderer SHA-256: `17cca3993bba66866824837996021d36af09820e607eb05c5efa42ba2435dea9`.
- Baseline scale-1 package: 261 files; package SHA-256 `c5fcd68d43b57443c56a7b9934566baf178ed46c5c2ef53d18b90b76b6ba1c51`; recursive inventory SHA-256 `ae826bea53f1415a1c881029d54a05ac82d6c43099c2a59f87884fe34fe56f2d`.
- Baseline `SHA256SUMS`: `259/259` records passed after Ruling 18 authorized one working-directory correction; accepted output SHA-256 `deef38c29a15229d2275ec222d5299b4437bf4b76f83e6c87b10553f712df952`.
- Blind conditions: 9; copied images: 36; source/copy identity `36/36`; full/tile crop equality `18/18`; critic allowlist: 37 files.
- Assignment SHA-256: `af8586f8d58100d3b1a5d377aef8be07fd3b8c6677a51009959a52d574cc38db`.
- Packet-manifest SHA-256: `6d7fe842d5db754a22b6e2be15c55125a2829c4c725cc8fbe163991066aaa268`.
- Critic checksum-ledger SHA-256: `c218fe22a68a7bf79f76ab920b72ad5d6c2aba05102c0cf9a94d1f243eed00bb`.
- Source-copy-ledger SHA-256: `33079817018f252c10176ec5c7ea58717c456b838af87d81962a6a5e47dd497b`.
- Critic allowlist SHA-256: `735098c9e511bf8a70ed99c5cd6b9b50eae1699826e6065d8454804a6838e9f4`.
- Identity-leak scan: PASS; no candidate/baseline identity was exposed before observation locks.

The first baseline checksum command is preserved as a working-directory-only diagnostic failure; it reported missing relative paths, not digest mismatches. Ruling 18 authorized the single corrected command from the immutable package root. Five-package pre/post seal equality then passed.

## Command and output-log digest index

Each directory below preserves its exact `command.txt`, `exit.txt`, resource evidence, output log, and an internal `SHA256SUMS`. The table hashes both the output log and that whole-command evidence ledger.

| Command evidence directory | Output-log SHA-256 | Evidence-ledger SHA-256 |
| --- | --- | --- |
| `commands/scale1-candidate-render` | `c8fffaa3986e1bfd72ea165c37d36dc4a0b53f6e6561caca02f0583d25bff25f` | `16e5e1625d304695b2269d29f8548c040f0c371e8977174c3dc8337ff555eed8` |
| `commands/scale1-candidate-verify-initial` | `6ff5a241de80e0b3a724e08a47feee8482dd071e9cc9b3bf770df6cfe000ef0f` | `87dee230fb9bab2d4261361c298ec8b9be939d41f6df7b3e0a9b16578f85f897` |
| `commands/scale1-candidate-verify-tampered` | `dc8685cd9d3d043371e7466ec39f384ca1e2c193c4ba7862732202a177e72ed6` | `610826f274b1b9ec17270d1889d43cb9e776ab350e1339fc80913cbf87df4926` |
| `commands/scale1-candidate-verify-untouched-final` | `4802c8eff91c1989ab2be023897a8200032d4a43cad53ede8e548a379d9cca6b` | `ca5e34929e66ad907781e1bbd7832d46493978ca9a383cd12b8b1ee6a9e3cee4` |
| `commands/scale1-rerender-render` | `1d793a27038ac0ee3c9bba013f4691b129cbc97ad2b8e95e434f2a0cc28b885b` | `d7c209f35c6fb3b3175f212b7bf1d7f33e3f6b5e891bb2db912adbdc2cccd54c` |
| `commands/scale1-rerender-verify-initial` | `c407f32e9119ffda6510e0a065a039f3a4488ebc40fc9b24d55da757d5ebaf09` | `800c22508a70092371ad0ff6b3ffc1f197e0a0bced54a3cf6608ddbb1a67dd83` |
| `commands/scale1-rerender-verify-tampered` | `59f4cf11ae1b78991d7537b9fd42d04ca213f48a4fb4bb1e6644bc30c93bd060` | `ecc8b371bc0e8f57e89646e97c5ac09df1fa17f6e5400b7cddd00a8b377bebd7` |
| `commands/scale1-rerender-verify-untouched-final` | `fdf6f966ac5fb6ee19a005754ed80350cfa3ab0c003952e141e0c31061e23dbc` | `1fd6c57fd62a92c7f142eee1b4d3511507f824e102e0b82a695ffe1cb0bb2e7a` |
| `commands/scale3-candidate-render` | `17425b0539ff33c4c35e0dec2b432264729a5cb2ef110de013eb97f113c909bf` | `6fd2d00ae92f75810ec7be384dc4c53b1ecf31ef33e34edcbfb013ed16029a36` |
| `commands/scale3-candidate-verify-initial` | `d894f7c4cf9c9666289f7bb5f1ce7df1c11735f52f658aeb5af33254282e2456` | `3efeef9b345b0de40047a64cc31623c9b57e4c306b15725a0a3db3e6597bebb2` |
| `commands/scale3-candidate-verify-tampered` | `3383e3a25aa5afa1da469c61b3c3ed442380a71f9d483b80532595e2573ae2c9` | `4f3eaaad63a49d557ace4048ae398b9e09548c47ccb0ec0a53443d6ef109e73f` |
| `commands/scale3-candidate-verify-untouched-final` | `60a37a9382a6736732f57bf9d8cbd2ad4d84f955df048a564a2d4d5c3e70de18` | `1ebb9b80c98b1db49dec98e5338a054bf8130487d01cea31a80da6ee55a641ca` |
| `commands/scale3-rerender-render` | `81b0c3c6c6f5bfd1ee950eb41b0b45049f1e3050f4791c6a097d772cdd05341f` | `babbcbf7b932311c967255cbf270071ebdaf62a8501de6754613540ed594714b` |
| `commands/scale3-rerender-verify-initial` | `a75087b931b519f413852263eedb5f6df0911964adaa6ed1fa46ee7c6271e124` | `76d43e79d14a15a5034e50c07f740a0e87a298562593e7d03364b53702c10751` |
| `commands/scale3-rerender-verify-tampered` | `4d016e5ade250f1aede12bc8c201de1dc2da02f78e7dc0581a4c954a7d9ac55d` | `0bc403424aa22144e1e04e44cca8f0861ef0c7877857741646e6719dfffb143c` |
| `commands/scale3-rerender-verify-untouched-final` | `86b38eb85591ab75e8f3b607ae7b31fbda39ce70d2c068505493089a3c2775b0` | `7beecc4eced539151dd95029d5109310af142ea64ff49ed04d38953de1fa7f44` |
| `commands/gates2-5-enumerator-self-test` | `df5f764a5344b4b4ee88bcc227f3b975e6984fddf8a34e0a4b7b3d9db7cc8773` | `bfe191b6ab6e4be3483d5e4f75abc5938915814df8b49be2c3285cf5d8833f64` |
| `commands/gates2-5-semantic-audit` | `16990eea95b204f75091e9932929b0be47a5a51f93a1dcdd0c659028046e40d4` | `6e1fbcf17704f6a1f1362be642fcf87417d1cfcfa5f3da620fb2f4a493ecacfe` |
| `commands/gates2-5-semantic-audit-v2` | `f6209030be307fb3cc0e47b365b5471fbda5d0a1e5cfeadd24a476fe0e4b18d4` | `083e2453b4369ac4230cdc32d6ee6bd11ec1dd8f94fa6a2d0bc42aede32f6130` |
| `commands/gate6-baseline-scale1-render` | `0fd21c3ed4b76daf9c531ddf83e56468a947af1ee6efec50137a3523308cdedb` | `0b60157934c026b418304b64095b10b179601b4fdc7c21d93dd5b598731a8f77` |
| `commands/gate6-blind-packet-build` | `5331c27c2585c74cbd66d6fde4ed300d36f902c5f3fcaec1df0fd944dc8dd04d` | `cb4f8be1948b0aced43247b5ac4c39d34a404c0e10f7ae4158a3478050e05ea4` |
| `commands/gate6-baseline-checksums` | `92c791a2e9ec6157c59a4edca5d6646da2c5f0859a33c4187b978535998a9133` | `b048d7bc12fd68d75076b4aac81120ad3b28aced9bf3ed378870d4157769f021` |
| `commands/gate6-pre-checksum-seal-guard` | `bdba21d277f29f16b189f12caa7eb2018db7f30f39e4e2773b53b4988a28833d` | `981caec19186c255ef36f0f93b2ae53e4da771dcd1587ec93208752f645c237f` |
| `commands/gate6-baseline-checksums-from-package-root` | `deef38c29a15229d2275ec222d5299b4437bf4b76f83e6c87b10553f712df952` | `42f59f31abb5e2b1e403cc33c74c4c503f86f6cb0274ad1d331f5ba92a2c811b` |
| `commands/gate6-post-checksum-seal-guard` | `ee60bbf2a6b469ca7d5cd6a85f53447c9863a2fe6e211e5405a6da00256dbeb1` | `534f516d7500451e127d1ca19f76fd1e531695e892249f0d5855d4f6ba96a25f` |

## Independent audit and aesthetic review

- Pre-critic audit: `provenance/task-1b-attempt5-precritic-audit-1.md`; SHA-256 `b0d4c9a9531510cda241c76c38781e5e40a16f7af7157cc9665a61d4681a2879`; result PASS.
- Critic A task: `/root/visual_director_r20/task1b_attempt5_critic_a`.
  - Authoritative blind lock: `critics/critic-a-blind-lock.verbatim.base64`; deterministic base64 payload SHA-256 `a03b606482cd0c71ae8e6d1dae8985246f4f165ee5c81d57483e7ac3874cb674`; decoded-byte SHA-256 `a3e2cc6095ceaafc0cb91d3327d688d761135cad0d897d66319936fb32f90b4b`; decoded bytes compare equal to the untouched central source. `critics/critic-a-blind-lock.transcription.md` is explicitly non-authoritative and uses `<br>` in place of three Markdown hard-break whitespace endings.
  - Final four-line verdict: `critics/critic-a-verdict.md`; SHA-256 `7abe10098cc7df087d889d41b17b7f7ed69f59e97209d69e92b2fd37ae9a56bf`; verdict PASS; largest gap NONE; next acceptance test NONE.
- Critic B task: `/root/visual_director_r20/task1b_attempt5_critic_b`.
  - Blind lock: `critics/critic-b-blind-lock.md`; SHA-256 `0b489e08cdb38b0a3293c8cc3fa9910e0ad0743ff846e391a4f70fc0b907deb3`.
  - Final four-line verdict: `critics/critic-b-verdict.md`; SHA-256 `38945eb15c6a1583308f387ef491c0b4c2e0d3351f735bbc808ea7d40c5c8144`; verdict PASS; largest gap NONE; next acceptance test NONE.

Both critics locked all nine conditions and 36 blind images before separate identity reveal, selected the candidate in all nine comparisons, and then inspected the full required immutable scale-1 and scale-3 evidence. They did not see each other.

## Freeze assembly and limitations

- The four package roots and all 307 pre-existing Attempt 5 director files were copied without re-encoding and verified byte-for-byte against the detached source worktree.
- Rulings 15–21, the pre-critic audit, both blind locks, and both exact verdicts are preserved under this director root. Ruling 21 requires Critic A's lock to be stored as lossless base64 because its three intentional Markdown hard breaks otherwise fail the mandatory staged whitespace check; Critic B's lock and both verdicts remain exact ordinary-file copies.
- `material-approved.json` resolves the accepted source, frozen inputs, candidate/rerender packages, authority aggregate, blind assignment, critic packet, verdicts, and UTC approval time to repository-relative immutable paths and exact hashes.
- The baseline package itself, `/private/tmp` tamper packages, failed Attempt 3/4 roots, UUID scratch roots, losing rounds, and unrelated artifacts are excluded.
- This freeze approves sandbox materials only. It does not approve motion, held-out motion behavior, Metal parity, production integration, the main app canvas, or perceptual-golden updates.
- Day Objects remains Lab-only. Composition and approved material bytes are frozen. Motion may be planned only after independent review and commit of this Gate 8 freeze.
