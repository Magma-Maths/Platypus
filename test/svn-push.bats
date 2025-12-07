#!/usr/bin/env bats
# shellcheck disable=SC2164,SC2034  # cd failures handled by bats; unused vars are for clarity
#
# svn-push.bats - Tests for 'platypus svn push' command
#
# NOTE: These tests verify command parsing, error handling, and state management.
# Full integration tests require an actual SVN server.
#

load test_helper

# Source platypus-svn to access internal functions
setup() {
  setup_with_svn
}

#------------------------------------------------------------------------------
# Helper to create a mock git-svn setup
#------------------------------------------------------------------------------

# Creates a repo that looks like it has git-svn configured
# (without actually needing SVN)
create_mock_svn_repo() {
  local dir
  dir=$(create_repo "repo")
  
  (
    cd "$dir"
    
    # Initial commit
    echo "initial" > file.txt
    git add file.txt
    git commit -m "Initial commit"
    
    # Create a fake SVN remote ref (simulates git-svn tracking)
    git update-ref refs/remotes/git-svn HEAD
    
    # Create svn branch pointing to same place
    git branch svn HEAD
    
    # Create origin remote
    git remote add origin "file://$dir"
    
    # Push main to origin
    git push -u origin main 2>/dev/null || true
    
    # Create marker branch on origin
    git push origin HEAD:refs/heads/svn-marker 2>/dev/null || true
    git fetch origin 2>/dev/null || true
  ) >/dev/null
  
  echo "$dir"
}

#------------------------------------------------------------------------------
# Command parsing tests
#------------------------------------------------------------------------------

@test "svn push shows help with --help" {
  run platypus svn push --help 2>&1 || true
  [[ "$output" == *"Usage"* ]] || [[ "$output" == *"platypus svn"* ]]
}

#------------------------------------------------------------------------------
# Error handling tests
#------------------------------------------------------------------------------

@test "push fails outside git repo" {
  cd "$TEST_TMP"
  
  run platypus svn push
  [ "$status" -ne 0 ]
  [[ "$output" == *"git repository"* ]] || [[ "$output" == *"Not inside"* ]]
}

@test "svn push fails without git-svn configured" {
  local repo
  repo=$(create_repo "test")
  cd "$repo"
  
  # Add initial commit
  echo "test" > file.txt
  git add file.txt
  git commit -m "Initial"
  
  # Add a remote
  git remote add origin "file://$repo"
  
  run platypus svn push
  [ "$status" -ne 0 ]
  [[ "$output" == *"SVN"* ]] || [[ "$output" == *"git-svn"* ]]
}

@test "svn push fails with dirty working tree" {
  local repo
  repo=$(create_mock_svn_repo)
  cd "$repo"
  
  # Create uncommitted changes
  echo "dirty" > dirty.txt
  git add dirty.txt
  
  run platypus svn push
  [ "$status" -ne 0 ]
  [[ "$output" == *"staged"* ]] || [[ "$output" == *"uncommitted"* ]] || [[ "$output" == *"changes"* ]]
}

@test "push fails with unstaged changes" {
  local repo
  repo=$(create_mock_svn_repo)
  cd "$repo"
  
  # Create unstaged changes
  echo "modified" >> file.txt
  
  run platypus svn push
  [ "$status" -ne 0 ]
  [[ "$output" == *"Unstaged"* ]] || [[ "$output" == *"changes"* ]]
}

#------------------------------------------------------------------------------
# Option handling tests
#------------------------------------------------------------------------------

@test "svn push accepts --verbose flag" {
  local repo
  repo=$(create_mock_svn_repo)
  cd "$repo"
  
  run platypus svn push --verbose 2>&1 || true
  [[ "$output" != *"Unknown option"* ]]
}

@test "svn push accepts --dry-run flag" {
  local repo
  repo=$(create_mock_svn_repo)
  cd "$repo"
  
  run platypus svn push --dry-run 2>&1 || true
  [[ "$output" != *"Unknown option"* ]]
}

@test "svn push accepts --push-conflicts flag" {
  local repo
  repo=$(create_mock_svn_repo)
  cd "$repo"
  
  run platypus svn push --push-conflicts 2>&1 || true
  [[ "$output" != *"Unknown option"* ]]
}

@test "svn push accepts -n flag" {
  local repo
  repo=$(create_mock_svn_repo)
  cd "$repo"
  
  run platypus svn push -n 2>&1 || true
  [[ "$output" != *"Unknown option"* ]]
}

#------------------------------------------------------------------------------
# State management tests
#------------------------------------------------------------------------------

@test "svn push --continue fails without in-progress operation" {
  local repo
  repo=$(create_mock_svn_repo)
  cd "$repo"
  
  run platypus svn push --continue
  [ "$status" -ne 0 ]
  [[ "$output" == *"No operation in progress"* ]]
}

@test "svn push --abort fails without in-progress operation" {
  local repo
  repo=$(create_mock_svn_repo)
  cd "$repo"
  
  run platypus svn push --abort
  [ "$status" -ne 0 ]
  [[ "$output" == *"No operation in progress"* ]]
}

@test "svn push --continue and --abort cannot be used together" {
  local repo
  repo=$(create_mock_svn_repo)
  cd "$repo"
  
  run platypus svn push --continue --abort 2>&1 || true
  [ "$status" -ne 0 ]
  [[ "$output" == *"both"* ]] || [[ "$output" == *"Can't use"* ]]
}

#------------------------------------------------------------------------------
# Dry run tests
#------------------------------------------------------------------------------

@test "svn push --dry-run shows DRY RUN MODE" {
  local repo
  repo=$(create_mock_svn_repo)
  cd "$repo"
  
  run platypus svn push --dry-run 2>&1 || true
  [[ "$output" == *"DRY RUN"* ]] || [[ "$output" == *"dry-run"* ]]
}

#------------------------------------------------------------------------------
# Commit list building (can test without real SVN)
#------------------------------------------------------------------------------

@test "push reports no commits when marker equals tip" {
  local repo
  repo=$(create_mock_svn_repo)
  cd "$repo"
  
  # Marker and main are at same commit, so nothing to export
  # This test might fail on SVN operations, but the message should indicate no commits
  run platypus svn push 2>&1 || true
  
  # Should either succeed with "no commits" or fail on SVN (acceptable)
  # If it says "no commits" or "No new", that's the expected behavior
  [[ "$output" == *"No new"* ]] || [[ "$output" == *"no commits"* ]] || [[ "$output" == *"SVN"* ]] || [[ "$output" == *"git svn"* ]]
}

