#!/usr/bin/env bash
#
# svngit.sh - Sync Git main to SVN without rewriting history
#
# Copyright 2025 - Edgar Costa
#
# This script synchronizes commits from a Git repository to SVN using git-svn.
# It walks origin/main using --first-parent to avoid traversing into merged
# side histories (subtree histories live "behind" merge commits).
#
# For each commit on the first-parent chain, it exports the net diff from its
# first parent: diff(commit^1 -> commit). This works for both normal commits
# and merge commits. Commits with empty exported diffs are skipped, as svn does not support empty commits.
#
# Progress is tracked via a remote marker branch (default: origin/svn-synced)
# that records the last origin/main commit successfully exported to SVN.
#

# ShellCheck: disable SC2034 (variable appears unused)
# Many variables here are used indirectly via dynamic references or exported
# shellcheck disable=2034

# Exit on any errors:
set -e

#------------------------------------------------------------------------------
# Configuration defaults:
#------------------------------------------------------------------------------

VERSION=0.0.1
REQUIRED_GIT_VERSION=2.7.0

# Git remote name
REMOTE="${REMOTE:-origin}"

# Main branch to sync from
MAIN="${MAIN:-main}"

# Remote branch used as pointer to "last exported origin/main commit"
# This is NOT main. Moving it does not rewrite main.
MARKER="${MARKER:-svn-marker}"

# git-svn's tracking ref for SVN trunk
# Common values: refs/remotes/trunk, refs/remotes/git-svn
SVN_REMOTE_REF="${SVN_REMOTE_REF:-refs/remotes/git-svn}"

# Local branch pointing at SVN trunk tip
SVN_BRANCH="${SVN_BRANCH:-svn}"

# Local throwaway branch used for dcommit
EXPORT_BRANCH="${EXPORT_BRANCH:-svn-export}"

#------------------------------------------------------------------------------
# Global state variables:
#------------------------------------------------------------------------------

quiet_wanted=false      # Suppress normal output
verbose_wanted=false    # Show verbose step output
debug_wanted=false      # Show commands being run
dry_run=false           # Don't actually push to SVN or update marker

TIP=                    # HEAD commit of origin/main
BASE=                   # Last exported commit (marker position)
COMMITS=                # List of commits to export

original_branch=        # Branch we started on (for cleanup)

#------------------------------------------------------------------------------
# Cleanup and signal handling:
#------------------------------------------------------------------------------

# Cleanup function called on exit or interrupt:
cleanup() {
  local exit_code=$?
  local current_branch

  # Get current branch (might be on export branch)
  current_branch=$(git symbolic-ref --short HEAD 2>/dev/null || echo "")

  # If we're on the export branch, switch away first
  if [[ $current_branch == "$EXPORT_BRANCH" ]]; then
    if [[ $original_branch ]]; then
      git switch "$original_branch" 2>/dev/null || git switch "$SVN_BRANCH" 2>/dev/null || true
    else
      git switch "$SVN_BRANCH" 2>/dev/null || true
    fi
  elif [[ $original_branch ]]; then
    # Restore original branch if we changed it
    git switch "$original_branch" 2>/dev/null || true
  fi

  # On success: delete the temporary export branch
  # On error: leave it for inspection and inform the user
  if [[ $exit_code -eq 0 ]]; then
    git branch -D "$EXPORT_BRANCH" 2>/dev/null || true
  else
    if git branch --list "$EXPORT_BRANCH" | grep -q .; then
      err ""
      err "Export branch '$EXPORT_BRANCH' has been left for inspection."
      err "To clean up manually:  git branch -D $EXPORT_BRANCH"
    fi
  fi

  exit $exit_code
}

# Set up trap for cleanup on exit and signals:
trap cleanup EXIT INT TERM

#------------------------------------------------------------------------------
# Utility functions:
#------------------------------------------------------------------------------

# Print unless quiet mode:
say() {
  $quiet_wanted || echo "$@"
}

# Print verbose step output:
o() {
  if $verbose_wanted; then
    echo "  * $*"
  fi
}

# Print to stderr:
err() {
  echo "$@" >&2
}

# Print error and exit:
error() {
  echo "ERROR: $*" >&2
  exit 1
}

# Smart command runner with debug output:
RUN() {
  $debug_wanted && echo ">>> $*" >&2
  "$@"
}

# Print usage and exit:
usage() {
  cat <<'...'
Usage: svngit.sh [options]

Sync Git main branch to SVN without rewriting Git history.

Options:
  -h, --help      Show this help message
  -v, --verbose   Show verbose step-by-step output
  -q, --quiet     Suppress normal output
  -n, --dry-run   Don't push to SVN or update marker
  -d, --debug     Show git commands as they are executed
  -x              Turn on Bash debugging (set -x)
  --version       Show version information

Environment Variables:
  REMOTE          Git remote name (default: origin)
  MAIN            Main branch to sync from (default: main)
  MARKER          Marker branch for tracking progress (default: svn-marker)
  SVN_REMOTE_REF  git-svn tracking ref (default: refs/remotes/git-svn)
  SVN_BRANCH      Local SVN mirror branch (default: svn)
  EXPORT_BRANCH   Temporary svn-export branch (default: svn-export)

Example:
  svngit.sh --verbose
  svngit.sh --debug --dry-run
  REMOTE=upstream MAIN=master svngit.sh
...
  exit 0
}

# Show version:
version() {
  echo "svngit.sh version $VERSION"
  exit 0
}

#------------------------------------------------------------------------------
# Environment checks:
#------------------------------------------------------------------------------

# Check that system is ready for this script:
assert-environment-ok() {
  # Check git is available
  type git &> /dev/null ||
    error "Can't find 'git' command in PATH."

  # Check git-svn is available
  git svn --version &> /dev/null ||
    error "Can't find 'git svn' command. Is git-svn installed?"

  # Check git version (optional but recommended)
  local git_version
  git_version=$(git --version | cut -d ' ' -f3)
  o "Git version: $git_version"

  # We must be inside a git repo
  git rev-parse --git-dir &> /dev/null ||
    error "Not inside a git repository."

  # Must be in a work-tree
  local in_worktree
  in_worktree=$(git rev-parse --is-inside-work-tree 2>/dev/null || echo "false")
  [[ $in_worktree == true ]] ||
    error "Must be inside a git working tree."
}

#------------------------------------------------------------------------------
# Git wrapper functions:
#------------------------------------------------------------------------------

# Check if a git revision exists:
git:rev-exists() {
  git rev-list "$1" -1 &> /dev/null
}

# Check if a branch exists:
git:branch-exists() {
  git:rev-exists "refs/heads/$1"
}

# Check if a remote ref exists:
git:remote-ref-exists() {
  local ref=$1
  git show-ref --verify --quiet "$ref"
}

# Get short commit hash:
git:short-hash() {
  git rev-parse --short "$1"
}

# Assert working tree is clean:
git:assert-clean-worktree() {
  o "Assert working tree is clean"
  RUN git update-index -q --refresh
  git diff-index --quiet HEAD -- ||
    error "Working tree not clean. Commit or stash first."
}

# Get current branch name:
git:get-current-branch() {
  git symbolic-ref --short HEAD 2>/dev/null || echo ""
}

#------------------------------------------------------------------------------
# Sync command functions:
#------------------------------------------------------------------------------

# Fetch latest Git state from remote:
sync:fetch() {
  o "Fetch latest state from $REMOTE"
  RUN git fetch --prune "$REMOTE"

  TIP="$(git rev-parse "$REMOTE/$MAIN")"
  o "Remote tip: $(git:short-hash "$TIP")"
}

# Update local SVN mirror branch to match SVN trunk:
sync:update-svn-mirror() {
  say "Updating SVN mirror branch '$SVN_BRANCH'..."
  o "Switch to $SVN_BRANCH tracking $SVN_REMOTE_REF"
  RUN git switch -C "$SVN_BRANCH" "$SVN_REMOTE_REF"

  o "Rebase from SVN"
  RUN git svn rebase
}

# Initialize marker branch if it doesn't exist:
sync:init-marker() {
  if ! git:remote-ref-exists "refs/remotes/$REMOTE/$MARKER"; then
    local base_init
    base_init="$(git merge-base "$REMOTE/$MAIN" "$SVN_BRANCH")"
    say "Marker $REMOTE/$MARKER missing; initializing to $(git:short-hash "$base_init")"

    if ! $dry_run; then
      RUN git push "$REMOTE" "$base_init:refs/heads/$MARKER"
      RUN git fetch "$REMOTE" "refs/heads/$MARKER:refs/remotes/$REMOTE/$MARKER"
      BASE="$(git rev-parse "refs/remotes/$REMOTE/$MARKER")"
    else
      o "[dry-run] Would push marker to $base_init"
      # In dry-run mode, use the computed base since marker doesn't exist yet
      BASE="$base_init"
    fi
  else
    BASE="$(git rev-parse "refs/remotes/$REMOTE/$MARKER")"
  fi

  o "Marker position: $(git:short-hash "$BASE")"
}

# Build list of commits to export (first-parent only):
sync:build-commit-list() {
  o "Build commit list: first-parent $BASE..$TIP"

  COMMITS="$(git rev-list --reverse --first-parent "$BASE..$TIP" || true)"

  if [[ -z $COMMITS ]]; then
    say "No new first-parent commits to export ($BASE..$TIP)."
    return 1
  fi

  local count
  count=$(echo "$COMMITS" | wc -l | tr -d ' ')
  say "Found $count commit(s) to export."
  return 0
}

# Prepare the export branch from SVN tip:
sync:prepare-export-branch() {
  o "Create export branch '$EXPORT_BRANCH' from $SVN_BRANCH"
  RUN git switch -C "$EXPORT_BRANCH" "$SVN_BRANCH"

  # Safeguard: ensure export branch starts clean
  RUN git update-index -q --refresh
  git diff-index --quiet HEAD -- ||
    error "Export branch not clean. Something is off."
}

# Export a single commit to the export branch:
sync:export-commit() {
  local commit=$1
  local p1=$2

  o "Export commit $(git:short-hash "$commit")"

  # Apply the patch content (works regardless of subtree prefixes)
  # --binary preserves file mode changes and binary blobs
  RUN git diff --binary "$p1" "$commit" | RUN git apply --index

  # Skip commits with empty exported diff
  if git diff --cached --quiet; then
    RUN git reset --hard -q
    say "  Skip empty export: $(git:short-hash "$commit")"
    return 1
  fi

  # Keep original message and attribution
  local msg author adate cdate
  msg="$(git log -1 --pretty=%B "$commit")"
  author="$(git show -s --format='%an <%ae>' "$commit")"
  adate="$(git show -s --format=%aI "$commit")"
  cdate="$(git show -s --format=%cI "$commit")"

  # Commit the exported patch
  GIT_AUTHOR_DATE="$adate" GIT_COMMITTER_DATE="$cdate" \
    RUN git commit --author="$author" -m "$msg"

  say "  Exported: $(git:short-hash "$commit") -> $(git log -1 --pretty=%s "$commit" | head -c 50)"
  return 0
}

# Export all commits in the list:
sync:export-commits() {
  local commit p1 exported=0

  for commit in $COMMITS; do
    # Parse commit parents to get first parent
    read -ra line <<<"$(git rev-list --parents -n 1 "$commit")"
    p1="${line[1]}"

    if sync:export-commit "$commit" "$p1"; then
      ((exported++)) || true
    fi
  done

  if [[ $exported -eq 0 ]]; then
    say "All commits were empty; nothing to dcommit."
    return 1
  fi

  say "Exported $exported commit(s)."
  return 0
}

# Push commits to SVN via dcommit:
sync:dcommit() {
  if ! git rev-parse --verify -q HEAD >/dev/null; then
    say "Nothing committed on $EXPORT_BRANCH; nothing to dcommit."
    return 1
  fi

  if $dry_run; then
    say "[dry-run] Would run: git svn dcommit"
    return 0
  fi

  say "Pushing to SVN..."
  o "git svn dcommit"
  RUN git svn dcommit

  # Refresh SVN mirror after dcommit
  o "Refresh SVN mirror"
  RUN git switch "$SVN_BRANCH"
  RUN git svn rebase
}

# Advance the marker to the new tip:
sync:advance-marker() {
  if $dry_run; then
    say "[dry-run] Would advance marker to $(git:short-hash "$TIP")"
    return 0
  fi

  o "Advance marker to $TIP"
  RUN git push "$REMOTE" "$TIP:refs/heads/$MARKER"
  say "Marker advanced to $(git:short-hash "$TIP")."
}

# Merge SVN changes back into Git main:
sync:merge-back() {
  if $dry_run; then
    say "[dry-run] Would merge SVN changes back to $MAIN"
    return 0
  fi

  say "Merging SVN changes back to $MAIN..."
  o "Switch to $MAIN from $REMOTE/$MAIN"
  RUN git switch -C "$MAIN" "$REMOTE/$MAIN"

  o "Merge $SVN_BRANCH into $MAIN"
  RUN git merge --no-ff "$SVN_BRANCH" -m "Merge SVN into $MAIN"

  o "Push $MAIN to $REMOTE"
  RUN git push "$REMOTE" "$MAIN"
}

#------------------------------------------------------------------------------
# Option parsing:
#------------------------------------------------------------------------------

get-options() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -h|--help)
        usage
        ;;
      -v|--verbose)
        verbose_wanted=true
        shift
        ;;
      -q|--quiet)
        quiet_wanted=true
        shift
        ;;
      -n|--dry-run)
        dry_run=true
        shift
        ;;
      -d|--debug)
        debug_wanted=true
        shift
        ;;
      -x)
        set -x
        shift
        ;;
      --version)
        version
        ;;
      -*)
        error "Unknown option: $1. Use --help for usage."
        ;;
      *)
        error "Unexpected argument: $1. Use --help for usage."
        ;;
    esac
  done

  # Verbose implies not quiet
  if $verbose_wanted; then
    quiet_wanted=false
  fi

  # Debug implies verbose
  if $debug_wanted; then
    verbose_wanted=true
    quiet_wanted=false
  fi
}

#------------------------------------------------------------------------------
# Main function:
#------------------------------------------------------------------------------

main() {
  get-options "$@"

  say "=== svngit.sh v$VERSION ==="
  $dry_run && say "[DRY RUN MODE]"
  $debug_wanted && say "[DEBUG MODE]"

  # Check environment
  assert-environment-ok

  # Remember original branch for cleanup
  original_branch=$(git:get-current-branch)
  o "Original branch: $original_branch"

  # Require clean working tree
  git:assert-clean-worktree

  # Step 1: Fetch latest Git state
  sync:fetch

  # Step 2: Update SVN mirror
  sync:update-svn-mirror

  # Step 3: Ensure marker exists
  sync:init-marker

  # Step 4: Build commit list
  if ! sync:build-commit-list; then
    exit 0
  fi

  # Step 5: Prepare export branch
  sync:prepare-export-branch

  # Step 6: Export commits
  if ! sync:export-commits; then
    sync:advance-marker
    exit 0
  fi

  # Step 7: Push to SVN
  sync:dcommit

  # Step 8: Advance marker
  sync:advance-marker

  # Step 9: Merge back to main
  sync:merge-back

  # Step 10: Return to original branch
  if [[ $original_branch && $original_branch != "$MAIN" ]]; then
    o "Returning to original branch: $original_branch"
    RUN git switch "$original_branch"
  fi

  # Clear original_branch so cleanup trap doesn't try to switch again
  original_branch=

  say "=== Done: exported $(git:short-hash "$BASE")..$(git:short-hash "$TIP") to SVN ==="
}

#------------------------------------------------------------------------------
# Entry point:
#------------------------------------------------------------------------------

[[ ${BASH_SOURCE[0]} != "$0" ]] || main "$@"
