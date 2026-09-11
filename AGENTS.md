# Device installation

- For a normal Nowhere installation, use the latest fetched `origin/codex/current-integration` (the combined PR), unless the user explicitly requests an isolated feature build.
- Before building, verify that the checkout includes the current remote integration head. A worktree named `current-integration` is not proof that its files are current.
- Preserve dirty worktrees. Publish authorized feature changes on top of the latest integration head, then build from a clean checkout of that combined revision. Do not install from a historical checkout with only one task's changes.
- Build the `Steps4` app scheme and its embedded extensions together from the same checkout, using a dedicated DerivedData directory. Installing the app replaces its embedded widget and Screen Time extensions too.
- Before installation, verify the signed app, embedded extensions and required resources. Recheck the remote integration head; if it advanced during the build, inspect the difference and rebuild when it changes the shipped app.
- Record the installed Git revision and actual install/launch results. Keep simulator previews and physical-device UI verification distinct.
