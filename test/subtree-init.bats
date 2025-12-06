#!/usr/bin/env bats
# shellcheck disable=SC2164,SC2034  # cd failures handled by bats; unused vars are for clarity
#
# init.bats - Tests for 'platypus subtree init' command
#

load test_helper

#------------------------------------------------------------------------------
# Basic init tests
#------------------------------------------------------------------------------

@test "init creates config for existing directory" {
  local repo
  repo=$(create_monorepo)
  cd "$repo"
  
  # Create a directory that looks like a subtree
  mkdir -p lib/foo
  echo "# Foo Library" > lib/foo/README.md
  git add lib/foo
  git commit -m "Add lib/foo"
  
  # Init should create config
  run platypus subtree init lib/foo -r git@github.com:owner/foo.git
  [ "$status" -eq 0 ]
  
  # Check config was created
  assert_file_exists ".gitsubtrees"
  assert_git_config ".gitsubtrees" "subtree.lib/foo.remote" "git@github.com:owner/foo.git"
  assert_git_config ".gitsubtrees" "subtree.lib/foo.branch" "main"
}

@test "init accepts -b branch option" {
  local repo
  repo=$(create_monorepo)
  cd "$repo"
  
  mkdir -p lib/foo
  echo "content" > lib/foo/file.txt
  git add lib/foo
  git commit -m "Add lib/foo"
  
  run platypus subtree init lib/foo -r git@github.com:owner/foo.git -b develop
  [ "$status" -eq 0 ]
  
  assert_git_config ".gitsubtrees" "subtree.lib/foo.branch" "develop"
}

@test "init records preMergeParent commit" {
  local repo
  repo=$(create_monorepo)
  cd "$repo"
  
  mkdir -p lib/foo
  echo "content" > lib/foo/file.txt
  git add lib/foo
  git commit -m "Add lib/foo"
  
  local expected_preMergeParent
  expected_preMergeParent=$(git rev-parse HEAD)
  
  run platypus subtree init lib/foo -r git@github.com:owner/foo.git
  [ "$status" -eq 0 ]
  
  local actual_preMergeParent
  actual_preMergeParent=$(git config -f .gitsubtrees subtree.lib/foo.preMergeParent)
  [ "$actual_preMergeParent" = "$expected_preMergeParent" ]
}

#------------------------------------------------------------------------------
# Error cases
#------------------------------------------------------------------------------

@test "init fails without remote option" {
  local repo
  repo=$(create_monorepo)
  cd "$repo"
  
  mkdir -p lib/foo
  echo "content" > lib/foo/file.txt
  git add lib/foo
  git commit -m "Add lib/foo"
  
  run platypus subtree init lib/foo
  [ "$status" -ne 0 ]
  [[ "$output" == *"Remote is required"* ]] || [[ "$output" == *"-r"* ]]
}

@test "init fails if directory doesn't exist" {
  local repo
  repo=$(create_monorepo)
  cd "$repo"
  
  run platypus subtree init lib/nonexistent -r git@github.com:owner/foo.git
  [ "$status" -ne 0 ]
  [[ "$output" == *"does not exist"* ]]
}

@test "init fails if directory is empty" {
  local repo
  repo=$(create_monorepo)
  cd "$repo"
  
  mkdir -p lib/empty
  
  run platypus subtree init lib/empty -r git@github.com:owner/foo.git
  [ "$status" -ne 0 ]
  [[ "$output" == *"empty"* ]]
}

@test "init fails if subtree already configured" {
  local repo
  repo=$(create_monorepo)
  cd "$repo"
  
  mkdir -p lib/foo
  echo "content" > lib/foo/file.txt
  git add lib/foo
  git commit -m "Add lib/foo"
  
  # First init should succeed
  run platypus subtree init lib/foo -r git@github.com:owner/foo.git
  [ "$status" -eq 0 ]
  git add .gitsubtrees
  git commit -m "Add config"
  
  # Second init should fail
  run platypus subtree init lib/foo -r git@github.com:owner/other.git
  [ "$status" -ne 0 ]
  [[ "$output" == *"already configured"* ]]
}

#------------------------------------------------------------------------------
# Dry run
#------------------------------------------------------------------------------

@test "init --dry-run shows what would happen" {
  local repo
  repo=$(create_monorepo)
  cd "$repo"
  
  mkdir -p lib/foo
  echo "content" > lib/foo/file.txt
  git add lib/foo
  git commit -m "Add lib/foo"
  
  run platypus subtree init lib/foo -r git@github.com:owner/foo.git --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"dry-run"* ]]
  
  # Config file should NOT be created in dry-run
  [ ! -f ".gitsubtrees" ]
}

#------------------------------------------------------------------------------
# Prefix normalization
#------------------------------------------------------------------------------

@test "init normalizes prefix with trailing slash" {
  local repo
  repo=$(create_monorepo)
  cd "$repo"
  
  mkdir -p lib/foo
  echo "content" > lib/foo/file.txt
  git add lib/foo
  git commit -m "Add lib/foo"
  
  run platypus subtree init lib/foo/ -r git@github.com:owner/foo.git
  [ "$status" -eq 0 ]
  
  # Should be stored without trailing slash
  run git config -f .gitsubtrees subtree.lib/foo.remote
  [ "$status" -eq 0 ]
}

@test "init normalizes prefix with leading slash" {
  local repo
  repo=$(create_monorepo)
  cd "$repo"
  
  mkdir -p lib/foo
  echo "content" > lib/foo/file.txt
  git add lib/foo
  git commit -m "Add lib/foo"
  
  run platypus subtree init /lib/foo -r git@github.com:owner/foo.git
  [ "$status" -eq 0 ]
  
  # Should be stored without leading slash
  run git config -f .gitsubtrees subtree.lib/foo.remote
  [ "$status" -eq 0 ]
}

