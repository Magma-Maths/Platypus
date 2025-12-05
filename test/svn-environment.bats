#!/usr/bin/env bats
#
# svn-environment.bats - Tests for platypus-svn environment checks
#
# These tests verify the environment validation that happens before
# any SVN operations. They don't require an actual SVN server.
#

load test_helper

#------------------------------------------------------------------------------
# Not in a git repository
#------------------------------------------------------------------------------

@test "svn fails outside git repo" {
  cd "$TEST_TMP"
  
  run platypus svn
  [ "$status" -ne 0 ]
  [[ "$output" == *"git repository"* ]] || [[ "$output" == *"Not inside"* ]]
}

#------------------------------------------------------------------------------
# Dirty worktree
#------------------------------------------------------------------------------

@test "svn fails with unstaged changes" {
  local repo
  repo=$(create_monorepo)
  cd "$repo"
  
  # Create unstaged change to tracked file
  echo "modified" >> README.md
  
  run platypus svn
  [ "$status" -ne 0 ]
  [[ "$output" == *"Unstaged"* ]] || [[ "$output" == *"unstaged"* ]]
}

@test "svn fails with staged changes" {
  local repo
  repo=$(create_monorepo)
  cd "$repo"
  
  # Create staged change
  echo "new file" > new.txt
  git add new.txt
  
  run platypus svn
  [ "$status" -ne 0 ]
  [[ "$output" == *"staged"* ]] || [[ "$output" == *"uncommitted"* ]] || [[ "$output" == *"clean"* ]]
}

#------------------------------------------------------------------------------
# Not on correct branch
#------------------------------------------------------------------------------

@test "svn fails when on svn-export branch" {
  local repo
  repo=$(create_monorepo)
  cd "$repo"
  
  # Create and switch to svn-export branch
  git checkout -b svn-export
  
  run platypus svn
  [ "$status" -ne 0 ]
  [[ "$output" == *"svn-export"* ]]
}

@test "svn fails when HEAD is detached" {
  local repo
  repo=$(create_monorepo)
  cd "$repo"
  
  # Create detached HEAD
  git checkout --detach HEAD
  
  run platypus svn
  [ "$status" -ne 0 ]
  [[ "$output" == *"detached"* ]] || [[ "$output" == *"branch"* ]]
}

#------------------------------------------------------------------------------
# Not at repo root
#------------------------------------------------------------------------------

@test "svn fails when not at repo root" {
  local repo
  repo=$(create_monorepo)
  cd "$repo"
  
  # Create subdirectory and cd into it
  mkdir -p subdir
  cd subdir
  
  run platypus svn
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

@test "svn --dry-run is accepted" {
  local repo
  repo=$(create_monorepo)
  cd "$repo"
  
  # dry-run should be accepted but will fail later due to missing SVN setup
  # We just verify the flag is recognized
  run platypus svn --dry-run
  # Should not fail with "unknown option" error
  [[ "$output" != *"unknown option"* ]]
  [[ "$output" != *"Unknown option"* ]]
}

@test "svn --verbose is accepted" {
  local repo
  repo=$(create_monorepo)
  cd "$repo"
  
  run platypus svn --verbose
  [[ "$output" != *"unknown option"* ]]
  [[ "$output" != *"Unknown option"* ]]
}

@test "svn --quiet is accepted" {
  local repo
  repo=$(create_monorepo)
  cd "$repo"
  
  run platypus svn --quiet
  [[ "$output" != *"unknown option"* ]]
  [[ "$output" != *"Unknown option"* ]]
}

#------------------------------------------------------------------------------
# Continue/Abort without state
#------------------------------------------------------------------------------

@test "svn --continue fails without saved state" {
  local repo
  repo=$(create_monorepo)
  cd "$repo"
  
  run platypus svn --continue
  [ "$status" -ne 0 ]
  [[ "$output" == *"No operation in progress"* ]]
}

@test "svn --abort fails without saved state" {
  local repo
  repo=$(create_monorepo)
  cd "$repo"
  
  run platypus svn --abort
  [ "$status" -ne 0 ]
  [[ "$output" == *"No operation in progress"* ]]
}

