#!/usr/bin/env bash
#
# platypus-common.bash - Shared utilities for Platypus commands
#
# Copyright 2025 - Edgar Costa
#
# This file contains common functions and variables shared between
# platypus-svn and platypus-subtree modules.
#
# Usage:
#   source "$(dirname "${BASH_SOURCE[0]}")/platypus-common.bash"
#

#------------------------------------------------------------------------------
# Global state variables (shared across modules):
#------------------------------------------------------------------------------

# These should be initialized before sourcing if you want different defaults
: "${quiet_wanted:=false}"
: "${verbose_wanted:=false}"
: "${debug_wanted:=false}"
: "${dry_run:=false}"

#------------------------------------------------------------------------------
# Output functions:
#------------------------------------------------------------------------------

# Print unless quiet mode is enabled
# Usage: say "message"
say() {
  $quiet_wanted || echo "$@"
}

# Print verbose/step output (indented with *)
# Usage: o "step description"
o() {
  if $verbose_wanted; then
    echo "  * $*"
  fi
}

# Print debug output
# Usage: debug "debug message"
debug() {
  if $debug_wanted; then
    echo "DEBUG: $*" >&2
  fi
}

# Print to stderr
# Usage: err "message"
err() {
  echo "$@" >&2
}

# Print error message and exit with status 1
# Usage: error "error message"
error() {
  printf "ERROR: %s\n" "$*" >&2
  exit 1
}

#------------------------------------------------------------------------------
# Command runner:
#------------------------------------------------------------------------------

# Run a command with optional debug/verbose output
# In dry-run mode, shows what would be run but doesn't execute
# Usage: RUN command [args...]
RUN() {
  if $debug_wanted; then
    echo ">>> $*" >&2
  elif $verbose_wanted; then
    echo "  > $*" >&2
  fi
  
  if $dry_run; then
    return 0
  fi
  
  "$@"
}

#------------------------------------------------------------------------------
# Git utility functions:
#------------------------------------------------------------------------------

# Check if a git revision exists
# Usage: git:rev-exists <ref>
git:rev-exists() {
  git rev-list "$1" -1 &> /dev/null
}

# Check if a local branch exists
# Usage: git:branch-exists <branch-name>
git:branch-exists() {
  git:rev-exists "refs/heads/$1"
}

# Check if a remote ref exists
# Usage: git:remote-ref-exists <ref>
git:remote-ref-exists() {
  local ref=$1
  git show-ref --verify --quiet "$ref"
}

# Get short commit hash (7 characters)
# Usage: git:short-hash <ref>
git:short-hash() {
  git rev-parse --short "$1"
}

# Get current branch name (empty string if detached HEAD)
# Usage: git:get-current-branch
git:get-current-branch() {
  git symbolic-ref --short HEAD 2>/dev/null || echo ""
}

# Assert the working tree is clean (no unstaged or staged changes)
# Usage: git:assert-clean-worktree
git:assert-clean-worktree() {
  git update-index -q --ignore-submodules --refresh
  
  # Check for unstaged changes
  if ! git diff-files --quiet --ignore-submodules; then
    error "Working tree has unstaged changes. Please commit or stash them first."
  fi
  
  # Check for staged but uncommitted changes
  if ! git diff-index --quiet --ignore-submodules HEAD -- 2>/dev/null; then
    error "Working tree has staged but uncommitted changes. Please commit or stash them first."
  fi
}

# Find and validate we're in a git repository
# Sets REPO_ROOT to the repository root
# Usage: git:find-repo-root
git:find-repo-root() {
  # shellcheck disable=SC2034  # REPO_ROOT is used by caller
  REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null) ||
    error "Not in a git repository."
}

# Assert we're inside a git repository working tree
# Usage: git:assert-in-repo
git:assert-in-repo() {
  git rev-parse --git-dir &> /dev/null ||
    error "Not inside a git repository."
  
  local in_worktree
  in_worktree=$(git rev-parse --is-inside-work-tree 2>/dev/null || echo "false")
  [[ $in_worktree == true ]] ||
    error "Must be inside a git working tree."
}

# Assert we're at the repository root
# Usage: git:assert-at-root
git:assert-at-root() {
  [[ -z $(git rev-parse --show-prefix 2>/dev/null) ]] ||
    error "Must run from top level directory (root) of the repository."
}

#------------------------------------------------------------------------------
# Common option parsing:
#------------------------------------------------------------------------------

# Parse common global options and return remaining arguments
# Sets: quiet_wanted, verbose_wanted, debug_wanted, dry_run
# Usage: eval "set -- $(common:parse-options "$@")"
#
# Note: This is a helper - each module should still handle its own
# module-specific options in addition to these common ones.
common:parse-options() {
  local args=()
  
  while [[ $# -gt 0 ]]; do
    case "$1" in
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
        verbose_wanted=true
        shift
        ;;
      -x)
        set -x
        shift
        ;;
      --)
        shift
        args+=("$@")
        break
        ;;
      *)
        args+=("$1")
        shift
        ;;
    esac
  done
  
  # Output remaining args in a format that can be used with eval set --
  printf '%q ' "${args[@]}"
}

#------------------------------------------------------------------------------
# Utility helpers:
#------------------------------------------------------------------------------

# Check if a command exists
# Usage: command:exists <command>
command:exists() {
  type "$1" &> /dev/null
}

