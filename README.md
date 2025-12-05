# Platypus

Platypus is a set of scripts that keeps three worlds in sync, using a Git monorepo as the hub:

```text
SVN <─────> Git monorepo <─────> Git subrepos
              (hub)           (vendored as subtree paths)
```

## Overview

- **SVN ↔ Git**: Sync commits between SVN and Git without rewriting Git history
- **Git subrepos**: Manage external Git repositories as subtrees inside the monorepo

## Scripts

### `svngit.sh` - Git to SVN Sync

Synchronizes commits from a Git repository to SVN using `git-svn`.

**Key features:**

- Walks `origin/main` using `--first-parent` to avoid traversing into merged side histories
- Exports the net diff for each commit: `diff(commit^1 -> commit)`
- Works with both normal commits and merge commits
- Skips empty commits (SVN doesn't support them)
- Tracks progress via a marker branch (default: `origin/svn-marker`)
- Never rewrites Git history

**Usage:**

```bash
./svngit.sh [options]

Options:
  -h, --help      Show help message
  -v, --verbose   Show verbose step-by-step output
  -q, --quiet     Suppress normal output
  -n, --dry-run   Don't push to SVN or update marker
  -d, --debug     Show git commands as they are executed
  -x              Turn on Bash debugging (set -x)
  --version       Show version information
```

**Environment Variables:**

| Variable | Default | Description |
|----------|---------|-------------|
| `REMOTE` | `origin` | Git remote name |
| `MAIN` | `main` | Main branch to sync from |
| `MARKER` | `svn-marker` | Marker branch for tracking progress |
| `SVN_REMOTE_REF` | `refs/remotes/git-svn` | git-svn tracking ref |
| `SVN_BRANCH` | `svn` | Local SVN mirror branch |
| `EXPORT_BRANCH` | `export` | Temporary export branch |

**Example:**

```bash
# Basic sync
./svngit.sh

# Verbose mode
./svngit.sh --verbose

# Debug mode (show all git commands)
./svngit.sh --debug --dry-run

# Custom remote and branch
REMOTE=upstream MAIN=master ./svngit.sh
```

