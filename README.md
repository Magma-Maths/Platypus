# Platypus

Platypus keeps three worlds in sync using a Git monorepo as the hub:

```text
SVN <─────> Git monorepo <─────> Git subtrees
              (hub)           (vendored as subtree paths)
```

## Installation

Clone this repository and source the `.rc` file in your shell startup:

```bash
# Add to ~/.bashrc or ~/.zshrc:
source /path/to/Platypus/.rc
```

This will:
- Add `platypus` command to your PATH
- Set up `PLATYPUS_ROOT` environment variable
- Enable tab completion (when available)

Alternatively, you can just add the lib directory to your PATH:

```bash
export PATH="/path/to/Platypus/lib:$PATH"
```

## Usage

```bash
platypus <command> [options]

Commands:
  svn       Sync Git main to SVN
  subtree   Manage Git subtrees
  sync      Run full sync (TODO)
  help      Show help message
  version   Show version information
```

## Commands

### `platypus svn` - Git to SVN Sync

Synchronizes commits from a Git repository to SVN using `git-svn`.

**Key features:**

- Keeps history linear by walking `origin/main` using `--first-parent` to avoid traversing merged side histories
- Exports the net diff for each commit: `diff(commit^1 -> commit)`
- Works with both normal commits and merge commits
- Skips empty commits (SVN doesn't support them)
- Tracks progress via a marker branch (default: `origin/svn-marker`)
- Never rewrites Git history
- Supports conflict handling with `--push-conflicts`
- Resume interrupted operations with `--continue` / `--abort`
- Automation-friendly exit codes and conflict logging

**Options:**

```bash
platypus svn [options]

  -h, --help         Show help message
  -v, --verbose      Show verbose step-by-step output
  -q, --quiet        Suppress normal output
  -n, --dry-run      Don't push to SVN or update marker
  -d, --debug        Show git commands as they are executed
  -x                 Turn on Bash debugging (set -x)
  --push-conflicts   Continue through conflicts, push with conflict markers
  --continue         Resume after resolving a conflict
  --abort            Abort in-progress operation and clean up
  --version          Show version information
```

**Environment Variables:**

| Variable | Default | Description |
|----------|---------|-------------|
| `REMOTE` | `origin` | Git remote name |
| `MAIN` | `main` | Main branch to sync from |
| `MARKER` | `svn-marker` | Marker branch for tracking progress |
| `SVN_REMOTE_REF` | `refs/remotes/git-svn` | git-svn tracking ref |
| `SVN_BRANCH` | `svn` | Local SVN mirror branch |
| `EXPORT_BRANCH` | `svn-export` | Temporary export branch |
| `CONFLICT_LOG` | `.git/svngit-conflicts.log` | Conflict log file |

**Exit Codes:**

| Code | Meaning |
|------|---------|
| `0` | Success - no conflicts |
| `1` | Error - operation failed |
| `2` | Success with conflicts - needs attention |

**Examples:**

```bash
# Basic sync
platypus svn

# Verbose mode
platypus svn --verbose

# Push through conflicts (for automation)
platypus svn --push-conflicts

# Custom remote and branch
REMOTE=upstream MAIN=master platypus svn
```

### `platypus subtree` - Git Subtree Management

Manage Git subtrees in the monorepo using native `git subtree` commands.

**Design rationale:**

- **Configuration at root (`.gitsubtrees`)**: Unlike git-subrepo's in-directory `.gitrepo`, we store config at the repository root (like `.gitmodules`). This allows direct use of `git subtree` without filtering. With 50k+ commits, in-directory config would require `filter-branch` on every push (hours of rewriting). Root config = zero filtering overhead.
- **Uses native `git subtree`**: Mature, handles edge cases. We add value through config management and incremental split optimization.
- **Tracks `splitSha` for fast pushes**: First push does full split (slow). Subsequent pushes use `--onto=<splitSha>` (fast!).

**Commands:**

```bash
platypus subtree <command> [options]

Commands:
  init <prefix> [-r <remote>] [-b <branch>]
                    Register an existing directory as a subtree
  add <prefix> <repo> [<ref>]
                    Add a new subtree from a remote repository
  pull <prefix>     Pull upstream changes into subtree
  push <prefix>     Push subtree changes to upstream
  status [<prefix>] Show sync status of subtree(s)
  list              List all configured subtrees

Options:
  -h, --help        Show help message
  -v, --verbose     Show verbose output
  -q, --quiet       Suppress normal output
  -n, --dry-run     Show what would be done
  -d, --debug       Show debug output
  --version         Show version information
```

**Configuration file (`.gitsubtrees`):**

Stored at repository root, uses git-config INI format:

```ini
# Platypus subtree configuration

[subtree "lib/foo"]
    remote = git@github.com:owner/foo.git
    branch = main
    upstream = abc123...    # Last synced upstream commit
    parent = def456...      # Monorepo commit at last sync
    splitSha = 789abc...    # Last split result (for incremental push)
```

**Examples:**

```bash
# Register existing lib/foo directory as a subtree
platypus subtree init lib/foo -r git@github.com:owner/foo.git

# Add a new subtree from a remote
platypus subtree add lib/bar git@github.com:owner/bar.git main

# Pull upstream changes
platypus subtree pull lib/foo

# Push local changes to upstream (uses incremental split)
platypus subtree push lib/foo

# Show status of all subtrees
platypus subtree status

# List all configured subtrees
platypus subtree list
```

**Workflow:**

```text
1. Add subtree:      platypus subtree add lib/foo <repo> main
                     (creates directory, adds to .gitsubtrees)

2. Work on code:     Edit files in lib/foo/ as normal

3. Pull upstream:    platypus subtree pull lib/foo
                     (fetches + git subtree merge)

4. Push changes:     platypus subtree push lib/foo
                     (git subtree split --onto=<cached> + push)
```

## Conflict Handling

When a patch or merge fails to apply cleanly:

**Interactive mode (default):**

```bash
platypus svn
# ... fails on conflict ...
# Fix the conflict manually, then:
platypus svn --continue
# Or abort:
platypus svn --abort
```

**Automation mode (`--push-conflicts`):**

The script continues through conflicts, marking them for later resolution:

- Commit messages are prefixed with `[CONFLICT]`
- Git notes are added to commits with conflicts
- Conflicts are logged to `CONFLICT_LOG`
- Exit code `2` indicates conflicts occurred

```bash
platypus svn --push-conflicts --quiet
case $? in
  0) echo "Success - no conflicts" ;;
  1) echo "Error - check logs" ;;
  2) echo "Conflicts pushed - needs review" ;;
esac
```

## Automation / Scheduled Runs

For cron jobs or CI/CD hooks:

```bash
#!/bin/bash
# sync-all.sh - Run periodically via cron

cd /path/to/repo

# Run sync, pushing through any conflicts
platypus svn --push-conflicts --quiet 2>&1

exit_code=$?

if [[ $exit_code -eq 2 ]]; then
  # Conflicts occurred - send notification
  echo "SVN sync completed with conflicts" | mail -s "Platypus Alert" admin@example.com
  cat .git/svngit-conflicts.log
fi

exit $exit_code
```

**Finding commits with conflicts:**

```bash
# Via commit message prefix
git log --grep='\[CONFLICT\]' --oneline

# Via git notes
git log --show-notes --oneline

# Via conflict log
cat .git/svngit-conflicts.log
```

## Project Structure

```text
Platypus/
├── .rc                   # Shell initialization (source this)
├── lib/
│   ├── platypus          # Main entry point
│   ├── platypus-svn      # SVN sync module
│   └── platypus-subtree  # Subtree sync module
├── share/                # Completion scripts (future)
├── .gitsubtrees          # Subtree configuration (in your repo)
└── README.md
```

## Requirements

- Bash 4.0+
- Git 2.7.0+
- git-svn (for SVN sync)

### For running tests

- [bats-core](https://github.com/bats-core/bats-core) - Bash testing framework

```bash
# macOS
brew install bats-core

# Ubuntu/Debian
apt install bats

# Or install from source
git clone https://github.com/bats-core/bats-core.git
cd bats-core && ./install.sh /usr/local
```

## License

Copyright 2025 - Edgar Costa
