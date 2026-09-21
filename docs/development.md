# Development

## Local setup

1. Use the integrated `main` branch; keep unfinished work on feature branches.
2. Copy `Config/Secrets.xcconfig.template` to ignored `Config/Secrets.xcconfig` and
   supply your public Supabase client configuration. Do not commit credentials.
   An optional `Config/Secrets-Dev.xcconfig` overrides Debug configuration.
3. Open `Nowhere.xcodeproj`, resolve Swift packages and select the **Nowhere** scheme.
   The app product is **Nowhere**. The project contains the four extension targets.
4. Use a simulator for ordinary UI/unit tests. HealthKit authorization, Family Controls,
   real shielding and widget behavior need physical-device verification.

The project uses Swift/SwiftUI, Metal and Swift Package Manager. App deployment
starts at iOS 17; unit/UI test targets require iOS 18. Use an installed simulator
shown by `xcodebuild -showdestinations -project Nowhere.xcodeproj -scheme Nowhere`.

## Build and test

Choose a simulator available on your Mac; keep build products outside the checkout.

```sh
xcodebuild -project Nowhere.xcodeproj -scheme Nowhere \
  -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17' \
  -derivedDataPath /tmp/nowhere-debug build

xcodebuild -project Nowhere.xcodeproj -scheme Nowhere \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -derivedDataPath /tmp/nowhere-tests -only-testing:NowhereTests test

xcodebuild -project Nowhere.xcodeproj -scheme Nowhere \
  -configuration Release -destination 'generic/platform=iOS' \
  -derivedDataPath /tmp/nowhere-release CODE_SIGNING_ALLOWED=NO build

python3 Scripts/check_canvas_audio_bundle.py \
  /tmp/nowhere-release/Build/Products/Release-iphoneos/Nowhere.app
python3 -m unittest discover -s Scripts -p 'test_usage_budget_*.py'
bash Scripts/check-secrets-config.sh
```

The Screen Time contract checks run the production session and registration code
against a deterministic daemon substitute. They cover delayed thresholds, concurrent
top-ups/recovery, callback delivery during registration, failed purchases and rollback
of widget balances. They do not validate delivery timing on a physical iPhone.

The unsigned Release command verifies compilation and resources; it does not make
an installable signed build. For device installation follow [AGENTS.md](../AGENTS.md):
fetch current `main`, build the app and all embedded extensions together, verify
signing/resources, recheck the remote revision, and record install/launch results.
Never install a simulator/test-host bundle. Measure distribution size from matching
archive/device variants, not a reused Debug output folder.

For the **NowhereDevicePerformance** scheme, compile the test host as an internal
Release build. Existing tests use `@testable` imports and helpers guarded by
`INTERNAL_BUILD`; supply these flags only for testing, keeping distribution Release
settings unchanged:

```sh
xcodebuild -project Nowhere.xcodeproj -scheme NowhereDevicePerformance \
  -configuration Release -destination 'generic/platform=iOS' \
  -derivedDataPath /tmp/nowhere-performance CODE_SIGNING_ALLOWED=NO \
  ENABLE_CODE_COVERAGE=NO ENABLE_TESTABILITY=YES \
  'OTHER_SWIFT_FLAGS=$(inherited) -D INTERNAL_BUILD' build-for-testing
```

This checks test compilation. Performance measurements require a separate signed
run on a physical device.

## Tools and adjacent projects

| Directory | Purpose and entry point |
| --- | --- |
| `Scripts/day_objects_audio/` | Reproducible sample preparation and mix analysis; [instructions](../Scripts/day_objects_audio/README.md) |
| `Tools/DayObjectsEditorialField/` | Standalone visual corpus/render tooling; [instructions](../Tools/DayObjectsEditorialField/README.md). Frozen authority data is in its `Fixtures/` directory |
| `Tools/LLMChatIndex/` | Local chat knowledge index; [instructions](../Tools/LLMChatIndex/README.md). Unrelated to the app build |
| `admin-panel/` | Next.js admin dashboard; [instructions](../admin-panel/README.md) |
| `tg-admin/` | Telegram admin worker; use its package scripts and configuration |
| `supabase/` | Database migrations, edge functions and their tests. Preserve migration history |
| `web/` | Standalone web pages/prototypes, outside the iOS target |

Run tool tests from the tool's own directory when its README says so. Do not
search or change unrelated tools/backend projects for an ordinary iOS UI task.

## Resources

- Image references may come from asset names, enum raw values, Xcode build settings,
  Info.plist or runtime catalogs. A text search alone is not proof of non-use.
- `ShieldIcon`, AppIcon, launch colors, current fonts and notices are required resources.
- App and extension bundles are separate; shared artwork/fonts can intentionally be copied
  into both. Removing one copy may break the extension even if the main app works.
- Old Canvas texture options remain for saved artwork. Preserve them unless a separately
  tested compatibility migration explicitly replaces them.
- Keep `Package.resolved` committed for reproducible transitive Swift dependencies.

## History and housekeeping

The repository keeps source, required resources, tests/fixtures and maintained docs.
Generated screenshots, videos, audio auditions, installation records, scratch plans,
chat exports and one-off reviews go into ignored `artifacts/` or `outputs/`.
Do not create an ever-growing checked-in archive directory.

Historical plans/specifications/reviews and obsolete design references were retired
from the working tree in the repository-housekeeping change. They remain in Git:

```sh
git log --all -- path/to/old-file.md
git show 4ee8e464:path/to/old-file.md
```

The second example retrieves the integrated snapshot immediately before housekeeping.
It is historical context, not the current implementation contract. Use the code map
first and retrieve a specific old document only when the question requires it.

Update existing maintained pages rather than adding a new report for each change.
Never commit personal chat archives or machine-specific output paths. Do not rewrite
shared Git history or delete dirty worktrees to reclaim disk space.
