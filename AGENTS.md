# Device installation

- For a normal Nowhere installation, use the latest fetched `origin/main`, unless the user explicitly requests an isolated feature build.
- Before building, verify that the checkout includes the current remote `main` head. A worktree name is not proof that its files are current.
- Preserve dirty worktrees. Publish authorized feature changes on top of the latest `main` head, then build from a clean checkout of that combined revision. Do not install from a historical checkout with only one task's changes.
- After publishing changes to `main`, fast-forward its clean local checkout too. Preserve any dirty work in a named backup commit first; pushing from a detached checkout does not update that local branch.
- Build the `Steps4` app scheme and its embedded extensions together from the same checkout, using a dedicated DerivedData directory. Installing the app replaces its embedded widget and Screen Time extensions too.
- Before installation, verify the signed app, embedded extensions and required resources. Recheck the remote `main` head; if it advanced during the build, inspect the difference and rebuild when it changes the shipped app.
- Record the installed Git revision and actual install/launch results. Keep simulator previews and physical-device UI verification distinct.

# Branch workflow

- `main` is the shared integration and installation branch. Target new feature PRs at `main`; do not recreate `codex/current-integration`.
- Keep unfinished work on feature branches or named backup commits. Do not discard another task's local changes when updating a checkout.
