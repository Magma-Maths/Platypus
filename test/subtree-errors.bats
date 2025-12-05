#!/usr/bin/env bats
#
# errors.bats - Tests for error handling across platypus commands
#

load test_helper

#------------------------------------------------------------------------------
# Not in a git repository
#------------------------------------------------------------------------------

@test "subtree commands fail outside git repo" {
  cd "$TEST_TMP"
  
  run platypus subtree list
  [ "$status" -ne 0 ]
  [[ "$output" == *"git repository"* ]] || [[ "$output" == *"not a git"* ]]
}

@test "subtree init fails outside git repo" {
  cd "$TEST_TMP"
  
  run platypus subtree init lib/foo -r git@example.com:foo.git
  [ "$status" -ne 0 ]
}

#------------------------------------------------------------------------------
# Dirty worktree
#------------------------------------------------------------------------------

@test "subtree add fails with unstaged changes" {
  local repo upstream
  repo=$(create_monorepo)
  upstream=$(create_upstream "foo")
  cd "$repo"
  
  # Create unstaged change to a tracked file
  echo "modified" >> README.md
  
  run platypus subtree add lib/foo "$upstream" main
  [ "$status" -ne 0 ]
  [[ "$output" == *"unstaged"* ]] || [[ "$output" == *"uncommitted"* ]]
}

@test "subtree add fails with staged changes" {
  local repo upstream
  repo=$(create_monorepo)
  upstream=$(create_upstream "foo")
  cd "$repo"
  
  # Create staged change
  echo "staged" > staged.txt
  git add staged.txt
  
  run platypus subtree add lib/foo "$upstream" main
  [ "$status" -ne 0 ]
  [[ "$output" == *"uncommitted"* ]] || [[ "$output" == *"staged"* ]] || [[ "$output" == *"clean"* ]]
}

@test "subtree pull fails with dirty worktree" {
  local repo upstream
  repo=$(create_monorepo)
  upstream=$(create_upstream "foo")
  cd "$repo"
  
  # Add subtree first
  platypus subtree add lib/foo "$upstream" main >/dev/null
  
  # Create dirty state (modify a tracked file)
  echo "modified" >> README.md
  
  run platypus subtree pull lib/foo
  [ "$status" -ne 0 ]
  [[ "$output" == *"unstaged"* ]] || [[ "$output" == *"uncommitted"* ]]
}

@test "subtree push fails with dirty worktree" {
  local repo upstream
  repo=$(create_monorepo)
  upstream=$(create_upstream "foo")
  cd "$repo"
  
  # Add subtree first
  platypus subtree add lib/foo "$upstream" main >/dev/null
  
  # Make a change to push
  echo "change" > lib/foo/change.txt
  git add lib/foo/change.txt
  git commit -m "Change"
  
  # Create dirty state (modify a tracked file)
  echo "modified" >> README.md
  
  run platypus subtree push lib/foo
  [ "$status" -ne 0 ]
  [[ "$output" == *"unstaged"* ]] || [[ "$output" == *"uncommitted"* ]]
}

#------------------------------------------------------------------------------
# Missing prefix argument
#------------------------------------------------------------------------------

@test "subtree init fails without prefix" {
  local repo
  repo=$(create_monorepo)
  cd "$repo"
  
  run platypus subtree init
  [ "$status" -ne 0 ]
}

@test "subtree add fails without prefix" {
  local repo
  repo=$(create_monorepo)
  cd "$repo"
  
  run platypus subtree add
  [ "$status" -ne 0 ]
}

#------------------------------------------------------------------------------
# Invalid config handling
#------------------------------------------------------------------------------

@test "subtree pull fails for unconfigured prefix" {
  local repo
  repo=$(create_monorepo)
  cd "$repo"
  
  run platypus subtree pull nonexistent
  [ "$status" -ne 0 ]
  [[ "$output" == *"not configured"* ]]
}

@test "subtree push fails for unconfigured prefix" {
  local repo
  repo=$(create_monorepo)
  cd "$repo"
  
  run platypus subtree push nonexistent
  [ "$status" -ne 0 ]
  [[ "$output" == *"not configured"* ]]
}

@test "subtree status fails for unconfigured prefix" {
  local repo
  repo=$(create_monorepo)
  cd "$repo"
  
  run platypus subtree status nonexistent
  [ "$status" -ne 0 ]
  [[ "$output" == *"not configured"* ]]
}

