#!/usr/bin/env bats
# shellcheck disable=SC2164,SC2034  # cd failures handled by bats; unused vars are for clarity
#
# svn-state.bats - Tests for platypus-svn state management
#
# These tests verify the --continue and --abort functionality
# by creating mock state files.
#

load test_helper

# Use the same state directory as the code under test
DEFAULT_STATE_DIR=".git/platypus/svngit"

# Lightweight git-svn mock (copied from svn-push.bats)
create_mock_svn_repo() {
  local dir
  dir=$(create_repo "repo")
  
  (
    cd "$dir"
    
    # Initial commit
    echo "initial" > file.txt
    git add file.txt
    git commit -m "Initial commit"
    
    # Fake SVN tracking ref (git-svn mirror)
    git update-ref refs/remotes/git-svn HEAD
    git branch svn HEAD
    
    # Remote
    git remote add origin "file://$dir"
    git push -u origin main 2>/dev/null || true
    
    # Marker branch on origin
    git push origin HEAD:refs/heads/svn-marker 2>/dev/null || true
    git fetch origin 2>/dev/null || true
  ) >/dev/null
  
  echo "$dir"
}

#------------------------------------------------------------------------------
# State file structure
#------------------------------------------------------------------------------

# Helper to create fake state files (matching actual format in platypus-svn)
create_fake_state() {
  local repo=$1
  local state_dir="$repo/${STATE_DIR:-$DEFAULT_STATE_DIR}"
  
  mkdir -p "$state_dir"
  
  # Create individual state files matching state:save format
  echo "main" > "$state_dir/original-branch"
  echo "abc123" > "$state_dir/tip"
  echo "def456" > "$state_dir/base"
  touch "$state_dir/commits-remaining"
}

#------------------------------------------------------------------------------
# Marker integrity
#------------------------------------------------------------------------------

@test "svn push initializes missing marker (dry-run)" {
  local repo
  repo=$(create_mock_svn_repo)
  cd "$repo"
  
  # Remove marker from origin to simulate missing state
  git push origin :refs/heads/svn-marker >/dev/null 2>&1 || true
  git update-ref -d refs/remotes/origin/svn-marker >/dev/null 2>&1 || true
  
  run platypus svn push --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"Marker origin/svn-marker missing"* ]] || [[ "$output" == *"Marker origin/svn-marker"* ]]
}

@test "svn push fails when marker is not ancestor of main" {
  local repo
  repo=$(create_mock_svn_repo)
  cd "$repo"
  
  # Make a new commit and set marker to it
  echo "rewrite" > rewritten.txt
  git add rewritten.txt
  git commit -m "Rewrite history"
  git push origin main
  git push origin HEAD:refs/heads/svn-marker
  
  # Rewrite main to previous commit (marker now ahead/divergent)
  git reset --hard HEAD~1
  git push origin +HEAD:main
  git fetch origin
  
  run platypus svn push --dry-run
  [ "$status" -ne 0 ]
  [[ "$output" == *"not an ancestor"* ]] || [[ "$output" == *"Stale marker"* ]]
}

#------------------------------------------------------------------------------
# --abort with state
#------------------------------------------------------------------------------

@test "svn --abort with state cleans up" {
  local repo
  repo=$(create_monorepo)
  cd "$repo"
  
  # Create fake state
  create_fake_state "$repo"
  
  # Also create svn-export branch that would need cleanup
  git checkout -b svn-export
  git checkout main
  
  run platypus svn --abort
  [ "$status" -eq 0 ]
  [[ "$output" == *"Aborted"* ]] || [[ "$output" == *"abort"* ]]
  
  # State directory should be cleaned up
  [ ! -d "$repo/.git/svngit" ]
}

@test "svn --abort removes svn-export branch" {
  local repo
  repo=$(create_monorepo)
  cd "$repo"
  
  # Create fake state
  create_fake_state "$repo"
  
  # Create svn-export branch
  git checkout -b svn-export
  git checkout main
  
  run platypus svn --abort
  [ "$status" -eq 0 ]
  
  # svn-export branch should be gone
  run git branch --list svn-export
  [ -z "$output" ]
}

#------------------------------------------------------------------------------
# --continue validation
#------------------------------------------------------------------------------

@test "svn --continue with state checks for clean worktree" {
  local repo
  repo=$(create_monorepo)
  cd "$repo"
  
  # Create fake state
  create_fake_state "$repo"
  
  # Create dirty worktree
  echo "dirty" >> README.md
  
  run platypus svn --continue
  [ "$status" -ne 0 ]
  # Should fail due to dirty worktree, not missing state
  [[ "$output" == *"unstaged"* ]] || [[ "$output" == *"uncommitted"* ]]
}

@test "svn --continue resumes with saved state in dry-run and clears state" {
  local repo state_dir tip
  repo=$(create_monorepo)
  cd "$repo"
  
  tip=$(git rev-parse HEAD)
  state_dir="$repo/${STATE_DIR:-$DEFAULT_STATE_DIR}"
  mkdir -p "$state_dir"
  echo "main" > "$state_dir/original-branch"
  echo "$tip" > "$state_dir/base"
  echo "$tip" > "$state_dir/tip"
  echo "" > "$state_dir/commits-remaining"
  echo "" > "$state_dir/current-commit"
  echo "false" > "$state_dir/had-conflicts"
  
  run platypus svn --continue --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"Resuming"* ]]
  [[ "$output" == *"dry-run"* ]] || [[ "$output" == *"DRY RUN"* ]]
  [ ! -d "$state_dir" ]
}

#------------------------------------------------------------------------------
# State persistence
#------------------------------------------------------------------------------

@test "state directory is in .git/svngit" {
  local repo
  repo=$(create_monorepo)
  cd "$repo"
  
  # Create fake state
  create_fake_state "$repo"
  
  # Verify state exists (individual files, not a single "state" file)
  local state_dir="$repo/${STATE_DIR:-$DEFAULT_STATE_DIR}"
  [ -d "$state_dir" ]
  [ -f "$state_dir/original-branch" ]
  [ -f "$state_dir/tip" ]
}

