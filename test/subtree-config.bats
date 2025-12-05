#!/usr/bin/env bats
# shellcheck disable=SC2164,SC2034  # cd failures handled by bats; unused vars are for clarity
#
# config.bats - Tests for config:* functions in platypus-subtree
#

load test_helper

# Source platypus-subtree to get access to config:* functions
setup() {
  setup_with_subtree
}

#------------------------------------------------------------------------------
# config:set and config:get tests
#------------------------------------------------------------------------------

@test "config:set creates .gitsubtrees file if it doesn't exist" {
  local repo
  repo=$(create_monorepo)
  cd "$repo"
  
  config:set "lib/foo" remote "git@github.com:owner/foo.git"
  
  assert_file_exists ".gitsubtrees"
}

@test "config:set writes correct value" {
  local repo
  repo=$(create_monorepo)
  cd "$repo"
  
  config:set "lib/foo" remote "git@github.com:owner/foo.git"
  config:set "lib/foo" branch "main"
  
  assert_git_config ".gitsubtrees" "subtree.lib/foo.remote" "git@github.com:owner/foo.git"
  assert_git_config ".gitsubtrees" "subtree.lib/foo.branch" "main"
}

@test "config:get returns correct value" {
  local repo
  repo=$(create_monorepo)
  cd "$repo"
  
  config:set "lib/foo" remote "git@github.com:owner/foo.git"
  
  run config:get "lib/foo" remote
  [ "$status" -eq 0 ]
  [ "$output" = "git@github.com:owner/foo.git" ]
}

@test "config:get returns error for missing key" {
  local repo
  repo=$(create_monorepo)
  cd "$repo"
  
  run config:get "lib/foo" remote
  [ "$status" -ne 0 ]
}

@test "config:get returns error when .gitsubtrees doesn't exist" {
  local repo
  repo=$(create_monorepo)
  cd "$repo"
  
  run config:get "lib/foo" remote
  [ "$status" -ne 0 ]
}

#------------------------------------------------------------------------------
# config:exists tests
#------------------------------------------------------------------------------

@test "config:exists returns true for configured subtree" {
  local repo
  repo=$(create_monorepo)
  cd "$repo"
  
  config:set "lib/foo" remote "git@github.com:owner/foo.git"
  
  run config:exists "lib/foo"
  [ "$status" -eq 0 ]
}

@test "config:exists returns false for unconfigured subtree" {
  local repo
  repo=$(create_monorepo)
  cd "$repo"
  
  config:set "lib/foo" remote "git@github.com:owner/foo.git"
  
  run config:exists "lib/bar"
  [ "$status" -ne 0 ]
}

@test "config:exists returns false when .gitsubtrees doesn't exist" {
  local repo
  repo=$(create_monorepo)
  cd "$repo"
  
  run config:exists "lib/foo"
  [ "$status" -ne 0 ]
}

#------------------------------------------------------------------------------
# config:list tests
#------------------------------------------------------------------------------

@test "config:list returns empty when no subtrees configured" {
  local repo
  repo=$(create_monorepo)
  cd "$repo"
  
  run config:list
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "config:list returns all configured subtrees" {
  local repo
  repo=$(create_monorepo)
  cd "$repo"
  
  config:set "lib/foo" remote "git@github.com:owner/foo.git"
  config:set "lib/bar" remote "git@github.com:owner/bar.git"
  config:set "vendor/baz" remote "git@github.com:owner/baz.git"
  
  run config:list
  [ "$status" -eq 0 ]
  [[ "$output" == *"lib/bar"* ]]
  [[ "$output" == *"lib/foo"* ]]
  [[ "$output" == *"vendor/baz"* ]]
}

#------------------------------------------------------------------------------
# config:unset tests
#------------------------------------------------------------------------------

@test "config:unset removes a key" {
  local repo
  repo=$(create_monorepo)
  cd "$repo"
  
  config:set "lib/foo" remote "git@github.com:owner/foo.git"
  config:set "lib/foo" branch "main"
  
  config:unset "lib/foo" branch
  
  run config:get "lib/foo" remote
  [ "$status" -eq 0 ]
  
  run config:get "lib/foo" branch
  [ "$status" -ne 0 ]
}

#------------------------------------------------------------------------------
# config:remove-section tests
#------------------------------------------------------------------------------

@test "config:remove-section removes entire subtree config" {
  local repo
  repo=$(create_monorepo)
  cd "$repo"
  
  config:set "lib/foo" remote "git@github.com:owner/foo.git"
  config:set "lib/foo" branch "main"
  config:set "lib/bar" remote "git@github.com:owner/bar.git"
  
  config:remove-section "lib/foo"
  
  run config:exists "lib/foo"
  [ "$status" -ne 0 ]
  
  run config:exists "lib/bar"
  [ "$status" -eq 0 ]
}

#------------------------------------------------------------------------------
# Edge cases
#------------------------------------------------------------------------------

@test "config handles subtree prefix with multiple slashes" {
  local repo
  repo=$(create_monorepo)
  cd "$repo"
  
  config:set "lib/external/foo" remote "git@github.com:owner/foo.git"
  
  run config:get "lib/external/foo" remote
  [ "$status" -eq 0 ]
  [ "$output" = "git@github.com:owner/foo.git" ]
  
  run config:exists "lib/external/foo"
  [ "$status" -eq 0 ]
}

