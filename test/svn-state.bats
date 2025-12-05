#!/usr/bin/env bats
# shellcheck disable=SC2164,SC2034  # cd failures handled by bats; unused vars are for clarity
#
# svn-state.bats - Tests for platypus-svn state management
#
# These tests verify the --continue and --abort functionality
# by creating mock state files.
#

load test_helper

#------------------------------------------------------------------------------
# State file structure
#------------------------------------------------------------------------------

# Helper to create fake state files (matching actual format in platypus-svn)
create_fake_state() {
  local repo=$1
  local state_dir="$repo/.git/svngit"
  
  mkdir -p "$state_dir"
  
  # Create individual state files matching state:save format
  echo "main" > "$state_dir/original-branch"
  echo "abc123" > "$state_dir/tip"
  echo "def456" > "$state_dir/base"
  touch "$state_dir/commits-remaining"
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
  [[ "$output" == *"Unstaged"* ]] || [[ "$output" == *"uncommitted"* ]]
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
  [ -d "$repo/.git/svngit" ]
  [ -f "$repo/.git/svngit/original-branch" ]
  [ -f "$repo/.git/svngit/tip" ]
}

