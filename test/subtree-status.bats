#!/usr/bin/env bats
# shellcheck disable=SC2164,SC2034  # cd failures handled by bats; unused vars are for clarity
#
# status.bats - Tests for 'platypus subtree status' and 'platypus subtree list'
#

load test_helper

# Source platypus-subtree to get access to config:* functions
setup() {
  setup_with_subtree
}

#------------------------------------------------------------------------------
# list command tests
#------------------------------------------------------------------------------

@test "list shows no subtrees when none configured" {
  local repo
  repo=$(create_monorepo)
  cd "$repo"
  
  run platypus subtree list
  [ "$status" -eq 0 ]
  [[ "$output" == *"No subtrees"* ]]
}

@test "list shows all configured subtrees" {
  local repo
  repo=$(create_monorepo)
  cd "$repo"
  
  # Set up some config without actual subtrees
  config:set "lib/foo" remote "git@github.com:owner/foo.git"
  config:set "lib/foo" branch "main"
  config:set "lib/bar" remote "git@github.com:owner/bar.git"
  config:set "lib/bar" branch "develop"
  
  run platypus subtree list
  [ "$status" -eq 0 ]
  [[ "$output" == *"lib/foo"* ]]
  [[ "$output" == *"lib/bar"* ]]
}

@test "status: list --quiet outputs only prefixes" {
  local repo
  repo=$(create_monorepo)
  cd "$repo"
  
  config:set "lib/foo" remote "git@github.com:owner/foo.git"
  config:set "lib/bar" remote "git@github.com:owner/bar.git"
  
  run platypus subtree list --quiet
  [ "$status" -eq 0 ]
  
  # Should output just the prefixes, one per line
  local line_count
  line_count=$(echo "$output" | wc -l | tr -d ' ')
  [ "$line_count" -eq 2 ]
}

#------------------------------------------------------------------------------
# status command tests
#------------------------------------------------------------------------------

@test "status shows all subtrees when no prefix given" {
  local repo
  repo=$(create_monorepo)
  cd "$repo"
  
  local upstream1 upstream2
  upstream1=$(create_upstream "foo-status-all")
  upstream2=$(create_upstream "bar-status-all")
  config:set "lib/foo" remote "$upstream1"
  config:set "lib/foo" branch "main"
  config:set "lib/bar" remote "$upstream2"
  config:set "lib/bar" branch "develop"
  
  mkdir -p lib/foo lib/bar
  echo "content" > lib/foo/file.txt
  echo "content" > lib/bar/file.txt
  
  run platypus subtree status
  [ "$status" -eq 0 ]
  [[ "$output" == *"lib/foo"* ]]
  [[ "$output" == *"lib/bar"* ]]
}

@test "status detects missing directory" {
  local repo
  repo=$(create_monorepo)
  cd "$repo"
  
  # Config exists but directory doesn't
  local upstream
  upstream=$(create_upstream "foo-status-missing")
  config:set "lib/foo" remote "$upstream"
  config:set "lib/foo" branch "main"
  
  run platypus subtree status lib/foo
  [ "$status" -eq 0 ]
  [[ "$output" == *"MISSING"* ]]
}

@test "status fails for unconfigured prefix" {
  local repo
  repo=$(create_monorepo)
  cd "$repo"
  
  run platypus subtree status lib/nonexistent
  [ "$status" -ne 0 ]
  [[ "$output" == *"not configured"* ]]
}

@test "status reports diverged when both sides have commits" {
  local setup repo work_dir
  setup=$(setup_divergent_subtree)
  repo=$(parse_subtree_setup "$setup" repo)
  work_dir=$(parse_subtree_setup "$setup" workdir)
  
  # Ensure upstream change is pushed (already done in helper), fetch latest
  (
    cd "$work_dir"
    git push origin main >/dev/null 2>&1
  )
  
  cd "$repo"
  run platypus subtree status lib/foo
  [ "$status" -eq 0 ]
  [[ "$output" == *"DIVERGED"* ]]
}

