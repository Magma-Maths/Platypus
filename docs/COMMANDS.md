# Platypus Commands Reference

This document explains the logic behind each Platypus command with diagrams
showing repository states before and after each operation.

## Table of Contents

- [Subtree Commands](#subtree-commands)
  - [Configuration Tracking](#configuration-tracking)
  - [subtree add](#subtree-add)
  - [subtree pull](#subtree-pull)
  - [subtree push](#subtree-push)
  - [subtree sync](#subtree-sync)
- [SVN Commands](#svn-commands)
  - [svn pull](#svn-pull)
  - [svn push](#svn-push)
- [Common Scenarios](#common-scenarios)
  - [Divergent Histories](#divergent-histories)
  - [Conflict Resolution](#conflict-resolution)

---

## Subtree Commands

Subtree commands manage Git subtrees - embedding external repositories as
subdirectories in your monorepo. Configuration is stored in `.gitsubtrees`.

### Conceptual Overview

```
┌─────────────────────────────────────────────────────────────────────┐
│                          MONOREPO                                    │
│  ┌──────────────────────────────────────────────────────────────┐   │
│  │  README.md                                                    │   │
│  │  src/                                                         │   │
│  │  lib/                                                         │   │
│  │  └── foo/  ◄─── SUBTREE (from upstream repo)                  │   │
│  │       ├── file.txt                                            │   │
│  │       └── lib-file.txt                                        │   │
│  │  .gitsubtrees  ◄─── Configuration file                        │   │
│  └──────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────┘
                              ▲
                              │ pull/push
                              ▼
┌─────────────────────────────────────────────────────────────────────┐
│                       UPSTREAM REPO                                  │
│  ┌──────────────────────────────────────────────────────────────┐   │
│  │  file.txt                                                     │   │
│  │  lib-file.txt                                                 │   │
│  └──────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────┘
```

---

### Configuration Tracking

The `.gitsubtrees` file tracks three important SHA values for each subtree:

```ini
[subtree "lib/foo"]
    remote = git@github.com:owner/foo.git
    branch = main
    upstream = abc123...         # Last synced upstream commit
    preMergeParent = def456... # Monorepo commit BEFORE last sync  
    splitSha = 789abc...         # Last split result (for incremental push)
```

| Field | Purpose | Set By |
|-------|---------|--------|
| `upstream` | Points to the upstream repo commit we last synced with | `add`, `pull` |
| `preMergeParent` | Points to the monorepo commit BEFORE the sync operation | `add`, `pull`, `push` |
| `splitSha` | Points to the extracted subtree history branch tip | `push` only |

**Why track these?**

- `upstream`: Tells us "what upstream commit is our subtree based on?" Used to detect if upstream has new changes.
- `preMergeParent`: Tells us "where was the monorepo before this sync?" This is a **stable reference** that doesn't change when we amend the merge commit to include config. Used for detecting new changes since last sync.
- `splitSha`: Enables **incremental push optimization**. Without it, `git subtree split` must walk the entire repo history. With it, we can use `--rejoin` to mark split points, making subsequent splits much faster.

---

### subtree add

**Purpose:** Add a new subtree from a remote repository.

**Usage:**
```bash
platypus subtree add <prefix> <repo> [<ref>]
```

**What it does:**
1. Fetches the remote repository
2. Adds the content at the specified prefix using `git subtree add`
3. Creates configuration in `.gitsubtrees`
4. Records the upstream commit SHA for tracking

**Before:**
```
Mono:     A ─────────────────────────────────────
                                                  
Upstream: X (content we want)                     
```

**After:**
```
Mono:     A ───── B (Add lib/foo subtree)
                 /
Upstream: X ────┘
```

**Config state after `add`:**
```ini
[subtree "lib/foo"]
    remote = git@github.com:owner/foo.git
    branch = main
    upstream = X              # ← The upstream commit we added
    preMergeParent = A      # ← Mono commit BEFORE the merge (stable!)
    splitSha = (none)         # ← Not set until first push
```

---

### subtree pull

**Purpose:** Pull upstream changes into the subtree.

**Usage:**
```bash
platypus subtree pull <prefix>
```

**What it does:**
1. Fetches from the configured remote
2. Merges upstream changes into the subtree prefix using `git subtree merge`
3. Updates the `upstream` and `parent` config values
4. Amends the merge commit to include config changes

**Before:**
```
Mono:     A ─── B ─── C (mono work)
             ╱
Upstream: X ─── Y ─── Z (new commits)

Config: upstream=X, preMergeParent=A, splitSha=(none)
```

**After:**
```
Mono:     A ─── B ─── C ─── D (Merge subtree from Z)
             ╱             ╱
Upstream: X ─── Y ─── Z ──┘

Config: upstream=Z, preMergeParent=C, splitSha=(none)
                 ▲                   ▲
                 │                   └── Captured BEFORE the merge (stable!)
                 └── Updated to fetched upstream tip
```

The merge commit D contains:
- All files from Z in the `lib/foo/` prefix
- Updated `.gitsubtrees` with new `upstream` and `preMergeParent` SHAs

**Config changes:**
| Field | Before | After |
|-------|--------|-------|
| `upstream` | X | Z (new upstream tip) |
| `preMergeParent` | A | C (mono HEAD before merge) |
| `splitSha` | (none) | (unchanged) |

---

### subtree push

**Purpose:** Push local subtree changes to the upstream repository.

**Usage:**
```bash
platypus subtree push <prefix>
```

**What it does:**
1. Runs `git subtree split --rejoin` to extract subtree history
2. Pushes the split branch to the upstream remote
3. Records the `splitSha` for incremental optimization
4. Amends the rejoin commit to include config update

**Before:**
```
Mono:     A ─── B ─── C (changed lib/foo/file.txt)
             ╱
Upstream: X ───────────

Config: upstream=X, preMergeParent=B, splitSha=(none)
```

**The split operation extracts subtree commits:**
```
Full mono history:        Extracted subtree history:
A ─── B ─── C             X ─── C' (just the lib/foo changes)
     ╱                         │
    X                          └── This becomes splitSha
```

**After:**
```
Mono:     A ─── B ─── C ─── D (rejoin merge)
             ╱             ╲
Upstream: X ─────────────── C' (pushed)
                            │
                            └── splitSha points here

Config: upstream=X, preMergeParent=C, splitSha=C'
                                    ▲            ▲
                                    │            └── NEW: tracks split result
                                    └── Captured BEFORE rejoin (stable!)
```

The `--rejoin` creates a merge commit marking where we split. This makes
subsequent pushes faster because `git subtree split` can skip already-processed history.

**Config changes:**
| Field | Before | After |
|-------|--------|-------|
| `upstream` | X | X (unchanged - we pushed TO upstream, not pulled) |
| `preMergeParent` | B | C (mono HEAD before rejoin) |
| `splitSha` | (none) | C' (the extracted subtree branch tip) |

**Why splitSha matters:**

Without splitSha tracking (first push):
```
git subtree split --prefix=lib/foo
# Must walk ENTIRE repo history to find subtree commits
# On a 50k commit repo, this can take minutes
```

With splitSha tracking (subsequent pushes):
```
git subtree split --prefix=lib/foo --rejoin
# The --rejoin merge commit marks the split point
# Subsequent splits only process new commits
# Takes seconds instead of minutes
```

---

### subtree sync

**Purpose:** Bidirectional sync - pull then push.

**Usage:**
```bash
platypus subtree sync <prefix>
```

**What it does:**
1. Executes `subtree pull` (get upstream changes)
2. Executes `subtree push` (send local changes)

This is useful when both the monorepo and upstream have new commits.

**Before (divergent state):**
```
Mono:     A ─── B ─── C (mono change)
             ╱
Upstream: X ─── Y (upstream change)

Config: upstream=X, preMergeParent=A, splitSha=(none)
```

**After pull phase:**
```
Mono:     A ─── B ─── C ─── D (merge from upstream)
             ╱             ╱
Upstream: X ─── Y ────────┘

Config: upstream=Y, preMergeParent=C, splitSha=(none)
```

**After push phase:**
```
Mono:     A ─── B ─── C ─── D ─── E (rejoin)
             ╱             ╱     ╲
Upstream: X ─── Y ────────┴───── C' (mono change pushed)
                                  │
                                  └── splitSha

Config: upstream=Y, preMergeParent=D, splitSha=C'
```

**Full config evolution during sync:**

| Phase | upstream | preMergeParent | splitSha |
|-------|----------|------------------|----------|
| Before | X | A | (none) |
| After pull | Y | C | (none) |
| After push | Y | D | C' |

After sync, both repos have all changes:
- Upstream has: X → Y → C' (both upstream's Y and mono's C)
- Mono has: merged Y from upstream, plus its own C

---

## SVN Commands

SVN commands sync the Git monorepo with an SVN repository using `git-svn`.
Changes flow: Git → SVN, and SVN metadata flows back into Git.

### Conceptual Overview

```
┌────────────────────────────────────────────────────────────────────────┐
│                              GIT                                        │
│                                                                         │
│   origin/main ──────────────────────────────────────────► TIP          │
│                                                                         │
│   origin/svn-marker ──► Last exported commit                           │
│                                                                         │
│   svn branch ──────────────────────────────────────────► SVN mirror    │
│                         (tracks refs/remotes/git-svn)                   │
└────────────────────────────────────────────────────────────────────────┘
                              │
                              │ git svn dcommit / rebase
                              ▼
┌────────────────────────────────────────────────────────────────────────┐
│                              SVN                                        │
│                                                                         │
│   trunk ─────────────────────────────────────────────────────────────  │
│                                                                         │
└────────────────────────────────────────────────────────────────────────┘
```

---

### svn pull

**Purpose:** Pull latest changes from SVN into the local mirror.

**Usage:**
```bash
platypus svn pull
```

**What it does:**
1. Fetches from the Git remote (`origin`)
2. Updates the SVN mirror branch using `git svn rebase`
3. Reports how many commits are pending to push

**Before:**
```
Git main:   A ─── B ─────────────────────
                                          
SVN mirror: A ───────────────────────────
                                          
SVN trunk:  r1 ─── r2 (new SVN commit)   
```

**After:**
```
Git main:   A ─── B ─────────────────────
                                          
SVN mirror: A ─── C (from r2) ───────────
                  │                       
                  └── git svn rebase pulled this
                                          
SVN trunk:  r1 ─── r2                    
```

The `svn` branch now has the new SVN revision as a Git commit.

---

### svn push

**Purpose:** Push Git commits to SVN and merge back.

**Usage:**
```bash
platypus svn push [--push-conflicts]
```

**What it does:**
1. Fetches from Git remote
2. Updates SVN mirror (`git svn rebase`)
3. Builds list of commits to export (first-parent only)
4. For each commit: applies diff to export branch, commits with original metadata
5. Runs `git svn dcommit` to push to SVN
6. Advances the marker branch
7. Merges SVN changes back to main

**Why first-parent only?**

When you have subtrees, their history lives "behind" merge commits:

```
main (first-parent path): A ─── B ─── C
                                │
                                └──┬── L1 ─── L2 (subtree history)
                                   │
                                   └── subtree merge brings in L1, L2
```

Walking `--first-parent` gives: A → B → C (3 commits)
Walking all parents gives: A → B → L1 → L2 → C (5 commits)

We only want to export the net changes, not replay subtree internal history.

**Before:**
```
Git main:   A ─── B ─── C ──────────────── (marker at A)
                                           
SVN trunk:  r1 ─────────────────────────── 
```

**After:**
```
Git main:   A ─── B ─── C ─── D (merge SVN back)  (marker at C)
                             ╱                     
SVN trunk:  r1 ─── r2 ─── r3 ────────────────────
            │      │      │
            │      │      └── from C
            │      └── from B
            └── from A (initial)
```

The marker now points to C, and main has a merge commit with SVN metadata.

---

## Common Scenarios

### Divergent Histories

When both the monorepo and upstream have made changes since the last sync:

```
Mono:     ... ─── B ─── C (mono adds feature)
                 │
                 └── last sync point
                 
Upstream: ... ─── X ─── Y (upstream fixes bug)
                 │
                 └── last sync point (same as B's subtree content)
```

**Resolution with `subtree sync`:**

1. **Pull phase** merges Y into mono:
   ```
   Mono: ... ─── B ─── C ─── D (merge)
                            ╱
   Upstream: X ─── Y ──────┘
   ```

2. **Push phase** sends C to upstream:
   ```
   Upstream: X ─── Y ─── C' (from mono's C)
   ```

After sync, both repos have both changes.

### Conflict Resolution

**Subtree conflicts:**

If pull creates conflicts:
```bash
platypus subtree pull lib/foo
# Conflict detected!
# Resolve manually, then:
git add <resolved-files>
git commit
```

**SVN conflicts:**

If push fails to apply a patch:
```bash
platypus svn push
# Patch apply failed!
# Options:
#   1. Fix manually and run: platypus svn push --continue
#   2. Abort: platypus svn push --abort
#   3. Force through: platypus svn push --push-conflicts
```

The `--push-conflicts` option will:
- Apply patches with conflict markers where needed
- Prefix commit messages with `[CONFLICT]`
- Log conflicts to `.git/svngit-conflicts.log`
- Exit with code 2 (success with conflicts)

---

## Configuration Files

### .gitsubtrees

Tracks subtree configuration (like `.gitmodules` for submodules):

```ini
[subtree "lib/foo"]
    remote = git@github.com:owner/foo.git
    branch = main
    upstream = abc123...         # Last synced upstream commit
    preMergeParent = def456... # Monorepo commit BEFORE last sync
    splitSha = 789abc...         # Last split SHA (for incremental push)
```

**Config field lifecycle:**

```
                    ┌───────────────────────────────────────────────────────────┐
                    │                Config Field Updates                        │
                    ├─────────────┬─────────────┬─────────────┬─────────────────┤
                    │   add       │   pull      │   push      │   sync          │
┌───────────────────┼─────────────┼─────────────┼─────────────┼─────────────────┤
│ upstream          │  SET        │  UPDATE     │  -          │  UPDATE         │
│ (upstream tip)    │  (fetched)  │  (fetched)  │             │  (pull phase)   │
├───────────────────┼─────────────┼─────────────┼─────────────┼─────────────────┤
│ preMergeParent    │  SET        │  UPDATE     │  UPDATE     │  UPDATE         │
│ (before merge)    │  (pre-add)  │  (pre-merge)│  (pre-join) │  (both phases)  │
├───────────────────┼─────────────┼─────────────┼─────────────┼─────────────────┤
│ splitSha          │  -          │  -          │  SET/UPDATE │  UPDATE         │
│ (split result)    │             │             │  (split)    │  (push phase)   │
└───────────────────┴─────────────┴─────────────┴─────────────┴─────────────────┘
```

### Environment Variables (SVN)

| Variable | Default | Description |
|----------|---------|-------------|
| `REMOTE` | `origin` | Git remote name |
| `MAIN` | `main` | Main branch to sync from |
| `MARKER` | `svn-marker` | Progress tracking branch |
| `SVN_REMOTE_REF` | `refs/remotes/git-svn` | git-svn tracking ref |
| `SVN_BRANCH` | `svn` | Local SVN mirror branch |
| `EXPORT_BRANCH` | `svn-export` | Temporary export branch |

---

## Command Quick Reference

| Command | Purpose |
|---------|---------|
| `platypus subtree add <prefix> <repo> [ref]` | Add new subtree |
| `platypus subtree pull <prefix>` | Pull upstream → mono |
| `platypus subtree push <prefix>` | Push mono → upstream |
| `platypus subtree sync <prefix>` | Pull then push |
| `platypus subtree status [prefix]` | Show sync status |
| `platypus subtree list` | List configured subtrees |
| `platypus svn pull` | Pull from SVN |
| `platypus svn push` | Push to SVN |
| `platypus svn push --continue` | Resume after conflict |
| `platypus svn push --abort` | Abort in-progress push |
