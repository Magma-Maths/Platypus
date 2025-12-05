#!/usr/bin/env bash
#
# test_helper.bash - Common setup for all bats tests
#
# This file is loaded by bats tests via:
#   load test_helper
#

# shellcheck disable=SC2164  # cd in test setup is fine without error handling

# Get the directory of the test file
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLATYPUS_ROOT="$(dirname "$TEST_DIR")"

# Source the .rc to set up platypus
export PLATYPUS_ROOT
export PATH="$PLATYPUS_ROOT/lib:$PATH"

# Temp directory for test repos (cleaned up after each test)
# Use /tmp to ensure we're outside the Platypus repo (for "not in git repo" tests)
export TEST_TMP="/tmp/platypus-test-$$"

# Git user config for tests
export GIT_AUTHOR_NAME="Test User"
export GIT_AUTHOR_EMAIL="test@example.com"
export GIT_COMMITTER_NAME="Test User"
export GIT_COMMITTER_EMAIL="test@example.com"

# Default branch name
export DEFAULT_BRANCH="main"

#------------------------------------------------------------------------------
# Setup/teardown functions
#------------------------------------------------------------------------------

# Called before each test
setup() {
  # Create fresh temp directory
  rm -rf "$TEST_TMP"
  mkdir -p "$TEST_TMP"
  
  # Change to temp directory
  cd "$TEST_TMP"
}

# Called after each test
teardown() {
  # Return to test dir
  cd "$TEST_DIR"
  
  # Clean up temp directory
  rm -rf "$TEST_TMP"
}

#------------------------------------------------------------------------------
# Helper functions for creating test repositories
#------------------------------------------------------------------------------

# Create a new git repository
# Usage: create_repo <name>
create_repo() {
  local name=$1
  local dir="$TEST_TMP/$name"
  
  mkdir -p "$dir"
  (
    cd "$dir"
    git init -b "$DEFAULT_BRANCH"
    git config user.name "$GIT_AUTHOR_NAME"
    git config user.email "$GIT_AUTHOR_EMAIL"
  ) >/dev/null
  
  echo "$dir"
}

# Create a bare git repository (for simulating remotes)
# Usage: create_bare_repo <name>
create_bare_repo() {
  local name=$1
  local dir="$TEST_TMP/$name.git"
  
  mkdir -p "$dir"
  (
    cd "$dir"
    git init --bare -b "$DEFAULT_BRANCH"
  ) >/dev/null
  
  echo "$dir"
}

# Create a monorepo with initial commit
# Usage: create_monorepo <name>
create_monorepo() {
  local name=${1:-monorepo}
  local dir
  dir=$(create_repo "$name")
  
  (
    cd "$dir"
    echo "# Monorepo" > README.md
    git add README.md
    git commit -m "Initial commit"
  ) >/dev/null
  
  echo "$dir"
}

# Create an upstream repo with some content
# Usage: create_upstream <name>
create_upstream() {
  local name=$1
  local bare_dir
  local work_dir
  
  # Create bare repo (the "remote")
  bare_dir=$(create_bare_repo "$name")
  
  # Create working repo to populate it
  work_dir=$(create_repo "${name}_work")
  
  (
    cd "$work_dir"
    echo "# $name" > README.md
    echo "content" > file.txt
    git add README.md file.txt
    git commit -m "Initial $name commit"
    git remote add origin "$bare_dir"
    git push -u origin "$DEFAULT_BRANCH"
  ) >/dev/null
  
  # Return the bare repo path (the "upstream")
  echo "$bare_dir"
}

# Add and commit files
# Usage: add_and_commit <message> <file1> [file2...]
add_and_commit() {
  local message=$1
  shift
  
  for file in "$@"; do
    git add "$file"
  done
  git commit -m "$message"
}

# Create a file, add it, and commit in one step
# Usage: add_commit <file> [content] [message]
add_commit() {
  local file=$1
  local content=${2:-"content"}
  local message=${3:-"Add $file"}
  
  echo "$content" > "$file"
  git add "$file"
  git commit -m "$message"
}

# Create a file with content
# Usage: create_file <path> [content]
create_file() {
  local path=$1
  local content=${2:-"content of $path"}
  
  mkdir -p "$(dirname "$path")"
  echo "$content" > "$path"
}

#------------------------------------------------------------------------------
# Assertion helpers
#------------------------------------------------------------------------------

# Assert a file exists
# Usage: assert_file_exists <path>
assert_file_exists() {
  local path=$1
  if [[ ! -f "$path" ]]; then
    echo "Expected file to exist: $path" >&2
    return 1
  fi
}

# Assert a file does not exist
# Usage: assert_file_not_exists <path>
assert_file_not_exists() {
  local path=$1
  if [[ -f "$path" ]]; then
    echo "Expected file to NOT exist: $path" >&2
    return 1
  fi
}

# Assert a directory exists
# Usage: assert_dir_exists <path>
assert_dir_exists() {
  local path=$1
  if [[ ! -d "$path" ]]; then
    echo "Expected directory to exist: $path" >&2
    return 1
  fi
}

# Assert file contains string
# Usage: assert_file_contains <path> <string>
assert_file_contains() {
  local path=$1
  local string=$2
  
  if ! grep -q "$string" "$path" 2>/dev/null; then
    echo "Expected file '$path' to contain: $string" >&2
    return 1
  fi
}

# Assert command output contains string
# Usage: assert_output_contains <string>
# (use after running a command with 'run')
assert_output_contains() {
  local string=$1
  
  if [[ "$output" != *"$string"* ]]; then
    echo "Expected output to contain: $string" >&2
    echo "Actual output: $output" >&2
    return 1
  fi
}

# Assert git config value
# Usage: assert_git_config <file> <key> <expected>
assert_git_config() {
  local file=$1
  local key=$2
  local expected=$3
  local actual
  
  actual=$(git config -f "$file" "$key" 2>/dev/null || echo "")
  
  if [[ "$actual" != "$expected" ]]; then
    echo "Expected $key = '$expected', got '$actual'" >&2
    return 1
  fi
}

#------------------------------------------------------------------------------
# Subtree test helpers
#------------------------------------------------------------------------------

# Create an upstream repo with a working directory for making changes
# Returns: "bare_dir|work_dir" (pipe-separated)
# Usage: create_upstream_with_workdir <name>
create_upstream_with_workdir() {
  local name=$1
  local bare_dir work_dir
  
  bare_dir=$(create_bare_repo "$name")
  work_dir=$(create_repo "${name}_work")
  
  (
    cd "$work_dir"
    echo "initial content" > file.txt
    git add file.txt
    git commit -m "Initial commit"
    git remote add origin "$bare_dir"
    git push -u origin "$DEFAULT_BRANCH"
  ) >/dev/null
  
  echo "$bare_dir|$work_dir"
}

# Create a monorepo with a subtree already added
# Returns: "repo|upstream|work_dir" (pipe-separated)
# Usage: setup_subtree_repo [prefix] [upstream_name]
setup_subtree_repo() {
  local prefix=${1:-lib/foo}
  local upstream_name=${2:-upstream}
  local repo upstream work_dir upstream_info
  
  upstream_info=$(create_upstream_with_workdir "$upstream_name")
  upstream=$(echo "$upstream_info" | cut -d'|' -f1)
  work_dir=$(echo "$upstream_info" | cut -d'|' -f2)
  
  repo=$(create_monorepo)
  (
    cd "$repo"
    platypus subtree add "$prefix" "$upstream" main
  ) >/dev/null
  
  echo "$repo|$upstream|$work_dir"
}

# Parse setup_subtree_repo output
# Usage: parse_subtree_setup "$setup_output"
#        REPO=$(parse_subtree_setup "$output" repo)
parse_subtree_setup() {
  local output=$1
  local field=${2:-all}
  
  case "$field" in
    repo)     echo "$output" | cut -d'|' -f1 ;;
    upstream) echo "$output" | cut -d'|' -f2 ;;
    workdir)  echo "$output" | cut -d'|' -f3 ;;
    *)        echo "$output" ;;
  esac
}

# Add content to upstream and push
# Usage: upstream_add_file <work_dir> <filename> [content]
upstream_add_file() {
  local work_dir=$1
  local filename=$2
  local content=${3:-"content of $filename"}
  
  (
    cd "$work_dir"
    echo "$content" > "$filename"
    git add "$filename"
    git commit -m "Add $filename"
    git push origin "$DEFAULT_BRANCH"
  ) >/dev/null
}

# Add a subtree (simulates adding a library)
# Usage: add_subtree_commits <prefix> [num_commits] [name]
add_subtree_commits() {
  local prefix=$1
  local num_commits=${2:-3}
  local name=${3:-lib}
  
  # Create a separate repo for the "library"
  local lib_dir="$TEST_TMP/${name}-upstream"
  mkdir -p "$lib_dir"
  (
    cd "$lib_dir"
    git init -b main
    git config user.name "$GIT_AUTHOR_NAME"
    git config user.email "$GIT_AUTHOR_EMAIL"
    
    for i in $(seq 1 "$num_commits"); do
      echo "lib content $i" > "lib-file-$i.txt"
      git add "lib-file-$i.txt"
      git commit -m "Lib commit $i"
    done
  ) >/dev/null
  
  # Add as subtree (this creates a merge commit)
  git subtree add --prefix="$prefix" "$lib_dir" main -m "Add $prefix subtree"
}

#------------------------------------------------------------------------------
# Patch testing helpers
#------------------------------------------------------------------------------

# Create a repo with a base file for testing patches
# Usage: create_patch_test_repo [name]
create_patch_test_repo() {
  local name=${1:-patch-test}
  local dir
  dir=$(create_repo "$name")
  
  (
    cd "$dir"
    echo "line 1" > file.txt
    echo "line 2" >> file.txt
    echo "line 3" >> file.txt
    git add file.txt
    git commit -m "Initial file"
  ) >/dev/null
  
  echo "$dir"
}

# Generate a patch from changes
# Usage: create_patch <original_file> <modified_file>
create_patch() {
  local original=$1
  local modified=$2
  
  diff -u "$original" "$modified" || true
}

#------------------------------------------------------------------------------
# Module sourcing helpers (for tests that need to source platypus modules)
#------------------------------------------------------------------------------

# Setup with platypus-subtree sourced (for config functions)
# Usage: setup_with_subtree
# Note: This replaces the default setup() for tests that need config: functions
setup_with_subtree() {
  # Call parent setup
  rm -rf "$TEST_TMP"
  mkdir -p "$TEST_TMP"
  cd "$TEST_TMP"
  
  # Source platypus-subtree for config functions
  source "$PLATYPUS_ROOT/lib/platypus-subtree"
}

# Setup with platypus-svn sourced (for internal functions)
# Usage: setup_with_svn
# Note: This replaces the default setup() for tests that need internal SVN functions
setup_with_svn() {
  # Call parent setup
  rm -rf "$TEST_TMP"
  mkdir -p "$TEST_TMP"
  cd "$TEST_TMP"
  source "$PLATYPUS_ROOT/lib/platypus-svn"
}
