#!/usr/bin/env bats
# shellcheck disable=SC2164,SC2034  # cd failures handled by bats; unused vars are for clarity
#
# add.bats - Tests for 'platypus subtree add' command
#

load test_helper

#------------------------------------------------------------------------------
# Basic add tests
#------------------------------------------------------------------------------

@test "add creates subtree directory and config" {
  local repo upstream
  repo=$(create_monorepo)
  upstream=$(create_upstream "foo")
  cd "$repo"
  
  run platypus subtree add lib/foo "$upstream" main
  [ "$status" -eq 0 ]
  
  # Directory should exist with content
  assert_dir_exists "lib/foo"
  assert_file_exists "lib/foo/README.md"
  assert_file_exists "lib/foo/file.txt"
  
  # Config should exist
  assert_file_exists ".gitsubtrees"
  assert_git_config ".gitsubtrees" "subtree.lib/foo.remote" "$upstream"
  assert_git_config ".gitsubtrees" "subtree.lib/foo.branch" "main"
}

@test "add records upstream and preMergeParent commits" {
  local repo upstream
  repo=$(create_monorepo)
  upstream=$(create_upstream "foo")
  cd "$repo"
  
  run platypus subtree add lib/foo "$upstream" main
  [ "$status" -eq 0 ]
  
  # Should have upstream commit recorded
  local upstream_sha
  upstream_sha=$(git config -f .gitsubtrees subtree.lib/foo.upstream)
  [ -n "$upstream_sha" ]
  
  # Should have preMergeParent commit recorded
  local preMergeParent_sha
  preMergeParent_sha=$(git config -f .gitsubtrees subtree.lib/foo.preMergeParent)
  [ -n "$preMergeParent_sha" ]
}

@test "add with different ref" {
  local repo upstream
  repo=$(create_monorepo)
  
  # Create upstream with a develop branch
  upstream=$(create_bare_repo "foo")
  local work_dir
  work_dir=$(create_repo "foo_work")
  (
    cd "$work_dir"
    echo "main content" > file.txt
    git add file.txt
    git commit -m "Initial commit"
    git remote add origin "$upstream"
    git push -u origin main
    
    # Create develop branch
    git checkout -b develop
    echo "develop content" > develop.txt
    git add develop.txt
    git commit -m "Develop commit"
    git push -u origin develop
  ) >/dev/null
  
  cd "$repo"
  
  run platypus subtree add lib/foo "$upstream" develop
  [ "$status" -eq 0 ]
  
  # Should have develop content
  assert_file_exists "lib/foo/develop.txt"
  assert_git_config ".gitsubtrees" "subtree.lib/foo.branch" "develop"
}

#------------------------------------------------------------------------------
# Error cases
#------------------------------------------------------------------------------

@test "add fails if directory already exists" {
  local repo upstream
  repo=$(create_monorepo)
  upstream=$(create_upstream "foo")
  cd "$repo"
  
  # Create the directory first
  mkdir -p lib/foo
  echo "existing content" > lib/foo/existing.txt
  git add lib/foo
  git commit -m "Add existing lib/foo"
  
  run platypus subtree add lib/foo "$upstream" main
  [ "$status" -ne 0 ]
  [[ "$output" == *"already exists"* ]]
}

@test "add fails if subtree already added (directory exists)" {
  local repo upstream1 upstream2
  repo=$(create_monorepo)
  upstream1=$(create_upstream "foo1")
  upstream2=$(create_upstream "foo2")
  cd "$repo"
  
  # Add first subtree
  run platypus subtree add lib/foo "$upstream1" main
  [ "$status" -eq 0 ]
  
  # Try to add another with same prefix - fails because directory exists
  run platypus subtree add lib/foo "$upstream2" main
  [ "$status" -ne 0 ]
  [[ "$output" == *"already exists"* ]]
}

@test "add fails without required arguments" {
  local repo
  repo=$(create_monorepo)
  cd "$repo"
  
  run platypus subtree add
  [ "$status" -ne 0 ]
  
  run platypus subtree add lib/foo
  [ "$status" -ne 0 ]
}

#------------------------------------------------------------------------------
# Dry run
#------------------------------------------------------------------------------

@test "add --dry-run shows what would happen" {
  local repo upstream
  repo=$(create_monorepo)
  upstream=$(create_upstream "foo")
  cd "$repo"
  
  run platypus subtree add lib/foo "$upstream" main --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"dry-run"* ]]
  
  # Directory should NOT exist
  [ ! -d "lib/foo" ]
  
  # Config should NOT exist
  [ ! -f ".gitsubtrees" ]
}

