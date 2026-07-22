# ScreenScribe workspace instructions

@/Users/ray/.codex/RTK.md

## Git lifecycle

When the user says **"进行 git 管理"** (or clearly asks for the equivalent Git
management action), treat it as authorization to perform this repository's
complete, scoped Git lifecycle. Do not treat it as a request for advice only.

1. Inspect the live state first: `git status`, the relevant diff, current
   branch, remotes, upstream, and `git fetch --prune origin`. Preserve
   unrelated uncommitted work and never stage it merely to make the tree clean.
2. Do not commit directly on `main`. If the current branch is not named
   `develop/<major>.<minor>`, create and switch to an appropriate development
   branch before committing the intended work.
3. Commit only the intended, reviewed changes. Use Conventional Commit-style
   messages, run relevant targeted verification, and run `git diff --check`
   before the commit.
4. Push the finished current development branch to `origin` and establish its
   upstream when needed (normally `git push -u origin <branch>`). Never force
   push, rewrite shared history, or resolve an unexpected remote divergence
   without first reporting it to the user.
5. Only after the push succeeds and the intended work is cleanly committed,
   create and switch to the next active development branch. Do not push an
   empty next branch solely for bookkeeping; publish it with its first finished
   work item during the next Git-management pass.
6. After the Git lifecycle succeeds, build the just-pushed commit as a Release
   macOS app and replace `/Applications/ScreenScribe.app` with that built app.
   Build from the published commit, not from later uncommitted work on the next
   development branch. If ScreenScribe is running, quit only that app before
   replacing its bundle. Verify that the copied app bundle exists; a build or
   installation failure means Git management is not complete and must be
   reported clearly.

### Development branch names and version selection

Use exactly `develop/<major>.<minor>` (for example, `develop/1.1`), without a
`v` prefix or a third version component. These are development milestones, not
release tags.

- Default: keep the same major version and increment the minor version for the
  next compatible feature, significant refactor, or independently deliverable
  work batch.
- Major change: increment the major version and reset the minor version to
  zero only for a user-visible breaking change, incompatible persisted-data
  change, or a genuinely new product-generation boundary.
- Small fixes, documentation-only work, and chores normally stay on the active
  development branch; if they form a separate deliverable, use the next minor
  branch instead.

The agent decides the version from the actual scope and explains the choice in
the handoff. If scope is unclear enough that the choice could change release
meaning, ask before creating the branch.

### Current baseline

The current local development branch is `develop/1.0`. At the next explicit
Git-management request, finish and publish its intended work first (recreating
its missing remote tracking branch if appropriate), then switch to
`develop/1.1` by default. Escalate directly to `develop/2.0` only if the
completed work crosses the major-change boundary above.
