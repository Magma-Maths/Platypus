#!/usr/bin/env bats
# shellcheck disable=SC2164,SC2034  # cd failures handled by bats; unused vars are for clarity
#
# svn-environment.bats - Tests for platypus-svn environment checks
#
# These tests verify the environment validation that happens before
# any SVN operations. They don't require an actual SVN server.
#

load test_helper

#------------------------------------------------------------------------------
# Helper: Create a mock git-svn repo (same as in svn-push.bats)
#------------------------------------------------------------------------------
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
# Not in a git repository
#------------------------------------------------------------------------------

@test "svn push fails outside git repo" {
  cd "$TEST_TMP"
  
  run platypus svn push
  [ "$status" -ne 0 ]
  [[ "$output" == *"git repository"* ]] || [[ "$output" == *"Not inside"* ]]
}

#------------------------------------------------------------------------------
# Dirty worktree
#------------------------------------------------------------------------------

@test "svn push fails with unstaged changes" {
  local repo
  repo=$(create_mock_svn_repo)
  cd "$repo"
  
  # Create unstaged change to tracked file
  echo "modified" >> file.txt
  
  run platypus svn push
  [ "$status" -ne 0 ]
  [[ "$output" == *"Unstaged"* ]] || [[ "$output" == *"unstaged"* ]]
}

@test "svn push fails with staged changes" {
  local repo
  repo=$(create_mock_svn_repo)
  cd "$repo"
  
  # Create staged change
  echo "new file" > new.txt
  git add new.txt
  
  run platypus svn push
  [ "$status" -ne 0 ]
  [[ "$output" == *"staged"* ]] || [[ "$output" == *"uncommitted"* ]] || [[ "$output" == *"clean"* ]]
}

#------------------------------------------------------------------------------
# Not on correct branch
#------------------------------------------------------------------------------

@test "svn push fails when on svn-export branch" {
  local repo
  repo=$(create_mock_svn_repo)
  cd "$repo"
  
  # Create and switch to svn-export branch
  git checkout -b svn-export
  
  run platypus svn push
  [ "$status" -ne 0 ]
  [[ "$output" == *"svn-export"* ]]
}

@test "svn push fails when HEAD is detached" {
  local repo
  repo=$(create_mock_svn_repo)
  cd "$repo"
  
  # Create detached HEAD
  git checkout --detach HEAD
  
  run platypus svn push
  [ "$status" -ne 0 ]
  [[ "$output" == *"detached"* ]] || [[ "$output" == *"branch"* ]]
}

#------------------------------------------------------------------------------
# Not at repo root
#------------------------------------------------------------------------------

@test "svn push fails when not at repo root" {
  local repo
  repo=$(create_mock_svn_repo)
  cd "$repo"
  
  # Create subdirectory and cd into it
  mkdir -p subdir
  cd subdir
  
  run platypus svn push
  [ "$status" -ne 0 ]
  [[ "$output" == *"top level"* ]] || [[ "$output" == *"root"* ]]
}

#------------------------------------------------------------------------------
# Help and version
#------------------------------------------------------------------------------

@test "svn --help shows usage" {
  run platypus svn --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage"* ]] || [[ "$output" == *"usage"* ]]
}

@test "svn -h shows usage" {
  run platypus svn -h
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage"* ]] || [[ "$output" == *"usage"* ]]
}

@test "svn --version shows version" {
  run platypus svn --version
  [ "$status" -eq 0 ]
  [[ "$output" =~ [0-9]+\.[0-9]+ ]]
}

#------------------------------------------------------------------------------
# Modes (basic check - these would need SVN for full testing)
#------------------------------------------------------------------------------

@test "svn push --dry-run is accepted" {
  local repo
  repo=$(create_mock_svn_repo)
  cd "$repo"
  
  # dry-run should be accepted and run without error
  run platypus svn push --dry-run
  # Should not fail with "unknown option" error
  [[ "$output" != *"unknown option"* ]]
  [[ "$output" != *"Unknown option"* ]]
}

@test "svn push --verbose is accepted" {
  local repo
  repo=$(create_mock_svn_repo)
  cd "$repo"
  
  run platypus svn push --verbose
  [[ "$output" != *"unknown option"* ]]
  [[ "$output" != *"Unknown option"* ]]
}

@test "svn push --quiet is accepted" {
  local repo
  repo=$(create_mock_svn_repo)
  cd "$repo"
  
  run platypus svn push --quiet
  [[ "$output" != *"unknown option"* ]]
  [[ "$output" != *"Unknown option"* ]]
}

#------------------------------------------------------------------------------
# Continue/Abort without state
#------------------------------------------------------------------------------

@test "svn --continue fails without saved state" {
  local repo
  repo=$(create_mock_svn_repo)
  cd "$repo"
  
  run platypus svn --continue
  [ "$status" -ne 0 ]
  [[ "$output" == *"No operation in progress"* ]]
}

@test "svn --abort fails without saved state" {
  local repo
  repo=$(create_mock_svn_repo)
  cd "$repo"
  
  run platypus svn --abort
  [ "$status" -ne 0 ]
  [[ "$output" == *"No operation in progress"* ]]
}

