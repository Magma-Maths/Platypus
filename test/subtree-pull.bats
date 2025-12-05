#!/usr/bin/env bats
# shellcheck disable=SC2164,SC2034  # cd failures handled by bats; unused vars are for clarity
#
# subtree-pull.bats - Tests for 'platypus subtree pull' command
#

load test_helper

#------------------------------------------------------------------------------
# Basic pull tests
#------------------------------------------------------------------------------

@test "pull merges upstream changes" {
  local setup repo work_dir
  setup=$(setup_subtree_repo)
  repo=$(parse_subtree_setup "$setup" repo)
  work_dir=$(parse_subtree_setup "$setup" workdir)
  
  # Add new content upstream
  upstream_add_file "$work_dir" "new_file.txt"
  
  cd "$repo"
  
  # Pull should bring in new content
  run platypus subtree pull lib/foo
  [ "$status" -eq 0 ]
  
  # New file should exist
  assert_file_exists "lib/foo/new_file.txt"
}

@test "pull updates config with new upstream commit" {
  local setup repo work_dir
  setup=$(setup_subtree_repo)
  repo=$(parse_subtree_setup "$setup" repo)
  work_dir=$(parse_subtree_setup "$setup" workdir)
  
  cd "$repo"
  local initial_upstream
  initial_upstream=$(git config -f .gitsubtrees subtree.lib/foo.upstream)
  
  # Add new content upstream
  upstream_add_file "$work_dir" "new_file.txt"
  
  run platypus subtree pull lib/foo
  [ "$status" -eq 0 ]
  
  # Upstream SHA should be updated
  local new_upstream
  new_upstream=$(git config -f .gitsubtrees subtree.lib/foo.upstream)
  [ "$initial_upstream" != "$new_upstream" ]
}

#------------------------------------------------------------------------------
# Error cases
#------------------------------------------------------------------------------

@test "pull fails if subtree not configured" {
  local repo
  repo=$(create_monorepo)
  cd "$repo"
  
  run platypus subtree pull lib/nonexistent
  [ "$status" -ne 0 ]
  [[ "$output" == *"not configured"* ]]
}

@test "pull fails without prefix argument" {
  local repo
  repo=$(create_monorepo)
  cd "$repo"
  
  run platypus subtree pull
  [ "$status" -ne 0 ]
}

#------------------------------------------------------------------------------
# Dry run
#------------------------------------------------------------------------------

@test "pull --dry-run shows what would happen" {
  local setup repo work_dir
  setup=$(setup_subtree_repo)
  repo=$(parse_subtree_setup "$setup" repo)
  work_dir=$(parse_subtree_setup "$setup" workdir)
  
  # Add new content upstream
  upstream_add_file "$work_dir" "new_file.txt"
  
  cd "$repo"
  
  run platypus subtree pull lib/foo --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"dry-run"* ]]
  
  # New file should NOT exist (dry-run)
  [ ! -f "lib/foo/new_file.txt" ]
}

