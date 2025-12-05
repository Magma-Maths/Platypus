#!/usr/bin/env bats
# shellcheck disable=SC2164,SC2034  # cd failures handled by bats; unused vars are for clarity
#
# svn-pull.bats - Tests for 'platypus svn pull' command
#
# NOTE: These tests verify command parsing and error handling.
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
    
    # Create marker branch
    git update-ref refs/remotes/origin/svn-marker HEAD
  ) >/dev/null
  
  echo "$dir"
}

#------------------------------------------------------------------------------
# Command parsing tests
#------------------------------------------------------------------------------

@test "svn pull shows help with --help" {
  run platypus svn pull --help 2>&1 || true
  # Should show usage information
  [[ "$output" == *"Usage"* ]] || [[ "$output" == *"platypus svn"* ]]
}

@test "svn shows usage without subcommand" {
  local repo
  repo=$(create_repo "test")
  cd "$repo"
  
  run platypus svn
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage"* ]]
}

@test "svn rejects unknown subcommand" {
  local repo
  repo=$(create_repo "test")
  cd "$repo"
  
  run platypus svn unknown
  [ "$status" -ne 0 ]
  [[ "$output" == *"Unknown"* ]]
}

#------------------------------------------------------------------------------
# Error handling tests
#------------------------------------------------------------------------------

@test "svn pull fails outside git repo" {
  cd "$TEST_TMP"
  
  run platypus svn pull
  [ "$status" -ne 0 ]
  [[ "$output" == *"git repository"* ]] || [[ "$output" == *"Not inside"* ]]
}

@test "svn pull fails without git-svn configured" {
  local repo
  repo=$(create_repo "test")
  cd "$repo"
  
  # Add initial commit
  echo "test" > file.txt
  git add file.txt
  git commit -m "Initial"
  
  # Add a remote
  git remote add origin "file://$repo"
  
  run platypus svn pull
  [ "$status" -ne 0 ]
  # Should fail because git-svn ref doesn't exist
  [[ "$output" == *"SVN"* ]] || [[ "$output" == *"git-svn"* ]]
}

@test "svn pull fails with dirty working tree" {
  local repo
  repo=$(create_mock_svn_repo)
  cd "$repo"
  
  # Create uncommitted changes
  echo "dirty" > dirty.txt
  git add dirty.txt
  
  run platypus svn pull
  [ "$status" -ne 0 ]
  [[ "$output" == *"staged"* ]] || [[ "$output" == *"uncommitted"* ]] || [[ "$output" == *"changes"* ]]
}

@test "svn pull fails with unstaged changes" {
  local repo
  repo=$(create_mock_svn_repo)
  cd "$repo"
  
  # Create unstaged changes to tracked file
  echo "modified" >> file.txt
  
  run platypus svn pull
  [ "$status" -ne 0 ]
  [[ "$output" == *"Unstaged"* ]] || [[ "$output" == *"changes"* ]]
}

#------------------------------------------------------------------------------
# Option handling tests
#------------------------------------------------------------------------------

@test "svn pull accepts --verbose flag" {
  local repo
  repo=$(create_mock_svn_repo)
  cd "$repo"
  
  # This will still fail (no real SVN) but should parse the option
  run platypus svn pull --verbose 2>&1 || true
  # Verbose flag should be accepted without "unknown option" error
  [[ "$output" != *"Unknown option"* ]]
}

@test "svn pull accepts --dry-run flag" {
  local repo
  repo=$(create_mock_svn_repo)
  cd "$repo"
  
  run platypus svn pull --dry-run 2>&1 || true
  [[ "$output" != *"Unknown option"* ]]
}

@test "svn pull accepts -n flag" {
  local repo
  repo=$(create_mock_svn_repo)
  cd "$repo"
  
  run platypus svn pull -n 2>&1 || true
  [[ "$output" != *"Unknown option"* ]]
}

#------------------------------------------------------------------------------
# State management tests
#------------------------------------------------------------------------------

@test "svn pull does not leave state on normal completion" {
  local repo
  repo=$(create_mock_svn_repo)
  cd "$repo"
  
  # Attempt pull (will fail on SVN operations but shouldn't leave state)
  platypus svn pull 2>&1 || true
  
  # State directory should not exist after failed pull
  # (pull doesn't create state - only push does)
  [ ! -d ".git/svngit" ]
}

