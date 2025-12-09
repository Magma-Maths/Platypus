#!/usr/bin/env bats
# shellcheck disable=SC2164,SC2034  # cd failures handled by bats; unused vars are for clarity
#
# svn-update.bats - Tests for 'platypus svn update' command
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

@test "svn update shows help with --help" {
  run platypus svn update --help 2>&1 || true
  # Should show usage information
  [[ "$output" == *"Usage"* ]] || [[ "$output" == *"platypus svn"* ]]
}

# Legacy name should be rejected now that the command is renamed
@test "legacy svn pull subcommand is rejected" {
  cd "$TEST_TMP"

  run platypus svn pull
  [ "$status" -ne 0 ]
  [[ "$output" == *"Unknown"* ]]
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

@test "svn update fails outside git repo" {
  cd "$TEST_TMP"
  
  run platypus svn update
  [ "$status" -ne 0 ]
  [[ "$output" == *"git repository"* ]] || [[ "$output" == *"Not inside"* ]]
}

@test "svn update fails without git-svn configured" {
  local repo
  repo=$(create_repo "test")
  cd "$repo"
  
  # Add initial commit
  echo "test" > file.txt
  git add file.txt
  git commit -m "Initial"
  
  # Add a remote
  git remote add origin "file://$repo"
  
  run platypus svn update
  [ "$status" -ne 0 ]
  # Should fail because git-svn ref doesn't exist
  [[ "$output" == *"SVN"* ]] || [[ "$output" == *"git-svn"* ]]
}

@test "svn update fails with dirty working tree" {
  local repo
  repo=$(create_mock_svn_repo)
  cd "$repo"
  
  # Create uncommitted changes
  echo "dirty" > dirty.txt
  git add dirty.txt
  
  run platypus svn update
  [ "$status" -ne 0 ]
  [[ "$output" == *"staged"* ]] || [[ "$output" == *"uncommitted"* ]] || [[ "$output" == *"changes"* ]]
}

@test "svn update fails with unstaged changes" {
  local repo
  repo=$(create_mock_svn_repo)
  cd "$repo"
  
  # Create unstaged changes to tracked file
  echo "modified" >> file.txt
  
  run platypus svn update
  [ "$status" -ne 0 ]
  [[ "$output" == *"Unstaged"* ]] || [[ "$output" == *"changes"* ]]
}

#------------------------------------------------------------------------------
# Option handling tests
#------------------------------------------------------------------------------

@test "svn update accepts --verbose flag" {
  local repo
  repo=$(create_mock_svn_repo)
  cd "$repo"
  
  # This will still fail (no real SVN) but should parse the option
  run platypus svn update --verbose 2>&1 || true
  # Verbose flag should be accepted without "unknown option" error
  [[ "$output" != *"Unknown option"* ]]
}

@test "svn update accepts --dry-run flag" {
  local repo
  repo=$(create_mock_svn_repo)
  cd "$repo"
  
  run platypus svn update --dry-run 2>&1 || true
  [[ "$output" != *"Unknown option"* ]]
}

@test "svn update accepts -n flag" {
  local repo
  repo=$(create_mock_svn_repo)
  cd "$repo"
  
  run platypus svn update -n 2>&1 || true
  [[ "$output" != *"Unknown option"* ]]
}

#------------------------------------------------------------------------------
# State management tests
#------------------------------------------------------------------------------

@test "svn update does not leave state on normal completion" {
  local repo
  repo=$(create_mock_svn_repo)
  cd "$repo"
  
  # Attempt update (will fail on SVN operations but shouldn't leave state)
  platypus svn update 2>&1 || true
  
  # State directory should not exist after failed update
  # (update doesn't create state - only export does)
  [ ! -d ".git/svngit" ]
}

