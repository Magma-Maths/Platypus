# Platypus Commands Reference

This document explains the logic behind each Platypus command with diagrams
showing repository states before and after each operation.

## Table of Contents

- [Subtree Commands](#subtree-commands)
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
    MONOREPO                     UPSTREAM
        │                            │
        A (Initial commit)           X (Upstream content)
        │                            │
```

**After:**
```
    MONOREPO                     UPSTREAM
        │                            │
        A                            X
        │                            │
        B (Add lib/foo subtree)      │
        │\___________________________│
        │  (subtree merge)
```

**Configuration created:**
```ini
[subtree "lib/foo"]
    remote = git@github.com:owner/foo.git
    branch = main
    upstream = <sha of X>
    parent = <sha of B>
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
    MONOREPO                     UPSTREAM
        │                            │
        A                            X
        │                            │
        B (has subtree)              Y (new commit)
        │                            │
        C (mono work)                Z (another commit)
```

**After:**
```
    MONOREPO                     UPSTREAM
        │                            │
        A                            X
        │                            │
        B                            Y
        │                            │
        C                            Z
        │\___________________________│
        D (Merge subtree)
```

The merge commit D contains:
- All files from Z in the `lib/foo/` prefix
- Updated `.gitsubtrees` with new `upstream` SHA

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
    MONOREPO                     UPSTREAM
        │                            │
        B (has subtree)              X
        │                            │
        C (changed lib/foo/file.txt) │
        │                            │
```

**After:**
```
    MONOREPO                     UPSTREAM
        │                            │
        B                            X
        │                            │
        C                            │
        │\                           │
        D (rejoin merge)             Y (pushed from mono)
                                     │
```

The `--rejoin` creates a merge commit that marks where we split. This makes
subsequent pushes faster (incremental split).

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
    MONOREPO                     UPSTREAM
        │                            │
        B (has subtree)              X (initial)
        │                            │
        C (mono change)              Y (upstream change)
        │                            │
```

**After pull phase:**
```
    MONOREPO                     UPSTREAM
        │                            │
        B                            X
        │                            │
        C                            Y
        │\___________________________│
        D (merge from upstream)
```

**After push phase:**
```
    MONOREPO                     UPSTREAM
        │                            │
        B                            X
        │                            │
        C                            Y
        │\                           │
        D (merge from upstream)      Z (mono change pushed)
        │\                           │
        E (rejoin)
```

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
    GIT main          SVN mirror          SVN trunk
        │                 │                   │
        A                 A                   r1
        │                 │                   │
        B                 │                   r2 (new SVN commit)
        │                 │                   │
```

**After:**
```
    GIT main          SVN mirror          SVN trunk
        │                 │                   │
        A                 A                   r1
        │                 │                   │
        B                 C ◄─────────────── r2
        │                 │
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
    main (first-parent path)
        │
        A
        │
        B ◄──────┐ (subtree merge)
        │        │
        │        L1 (lib commit 1)
        │        │
        │        L2 (lib commit 2)
        │
        C
```

Walking `--first-parent` gives: A → B → C (3 commits)
Walking all parents gives: A → B → L1 → L2 → C (5 commits)

We only want to export the net changes, not replay subtree internal history.

**Before:**
```
    GIT main          SVN marker          SVN trunk
        │                 │                   │
        A ◄───────────────┤                   r1
        │                                     │
        B                                     │
        │                                     │
        C                                     │
```

**After:**
```
    GIT main          SVN marker          SVN trunk
        │                 │                   │
        A                 │                   r1
        │                 │                   │
        B                 │                   r2 (from B)
        │                 │                   │
        C ◄───────────────┤                   r3 (from C)
        │\                                    │
        D (merge SVN back)
```

The marker now points to C, and main has a merge commit with SVN metadata.

---

## Common Scenarios

### Divergent Histories

When both the monorepo and upstream have made changes since the last sync:

```
    MONOREPO                     UPSTREAM
        │                            │
        B (last sync)                X (last sync)
        │                            │
        C (mono adds feature)        Y (upstream fixes bug)
        │                            │
```

**Resolution with `subtree sync`:**

1. **Pull phase** merges Y into mono:
   ```
       C
       │\
       │ Y
       │/
       D (merge)
   ```

2. **Push phase** sends C to upstream:
   ```
       UPSTREAM
           │
           X
           │
           Y
           │
           Z (from mono's C)
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
    upstream = abc123...    # Last synced upstream commit
    parent = def456...      # Monorepo commit at last sync
    splitSha = 789abc...    # Last split SHA (for incremental push)
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

