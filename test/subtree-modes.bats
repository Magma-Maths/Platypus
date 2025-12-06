#!/usr/bin/env bats
# shellcheck disable=SC2164,SC2034  # cd failures handled by bats; unused vars are for clarity
#
# subtree-modes.bats - Tests for --verbose, --quiet, --dry-run modes
#

load test_helper

# Source platypus-subtree for config functions
setup() {
  setup_with_subtree
}

#------------------------------------------------------------------------------
# Quiet mode
#------------------------------------------------------------------------------

@test "list --quiet outputs only prefixes" {
  local repo
  repo=$(create_monorepo)
  cd "$repo"
  
  config:set "lib/foo" remote "git@example.com:foo.git"
  config:set "lib/bar" remote "git@example.com:bar.git"
  
  run platypus subtree list --quiet
  [ "$status" -eq 0 ]
  
  # Output should be just prefixes, no extra text
  [[ "$output" != *"Configured"* ]]
  [[ "$output" == *"lib/foo"* ]]
  [[ "$output" == *"lib/bar"* ]]
}

@test "list -q outputs only prefixes" {
  local repo
  repo=$(create_monorepo)
  cd "$repo"
  
  config:set "lib/foo" remote "git@example.com:foo.git"
  
  run platypus subtree list -q
  [ "$status" -eq 0 ]
  [[ "$output" != *"Configured"* ]]
}

@test "init --quiet suppresses messages" {
  local repo
  repo=$(create_monorepo)
  cd "$repo"
  
  mkdir -p lib/foo
  echo "content" > lib/foo/file.txt
  git add lib/foo
  git commit -m "Add lib/foo"
  
  # Use --dry-run with --quiet to test output behavior without needing a real remote
  run platypus subtree init lib/foo -r git@example.com:foo.git --quiet --dry-run
  [ "$status" -eq 0 ]
  
  # Should have minimal output (dry-run might show something, but not "Initializing")
  [[ "$output" != *"Initializing"* ]]
}

#------------------------------------------------------------------------------
# Verbose mode
#------------------------------------------------------------------------------

@test "init --verbose shows extra detail" {
  local repo
  repo=$(create_monorepo)
  cd "$repo"
  
  mkdir -p lib/foo
  echo "content" > lib/foo/file.txt
  git add lib/foo
  git commit -m "Add lib/foo"
  
  # Use --dry-run with --verbose to test output behavior without needing a real remote
  run platypus subtree init lib/foo -r git@example.com:foo.git --verbose --dry-run
  [ "$status" -eq 0 ]
  
  # Should show details in dry-run mode
  [[ "$output" == *"dry-run"* ]]
}

@test "init -v shows extra detail" {
  local repo
  repo=$(create_monorepo)
  cd "$repo"
  
  mkdir -p lib/foo
  echo "content" > lib/foo/file.txt
  git add lib/foo
  git commit -m "Add lib/foo"
  
  # Use --dry-run with -v to test output behavior
  run platypus subtree init lib/foo -r git@example.com:foo.git -v --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"dry-run"* ]]
}

#------------------------------------------------------------------------------
# Dry-run mode
#------------------------------------------------------------------------------

@test "add --dry-run doesn't create files" {
  local repo upstream
  repo=$(create_monorepo)
  upstream=$(create_upstream "foo")
  cd "$repo"
  
  run platypus subtree add lib/foo "$upstream" main --dry-run
  [ "$status" -eq 0 ]
  
  # Directory should NOT exist
  [ ! -d "lib/foo" ]
  # Config should NOT exist
  [ ! -f ".gitsubtrees" ]
  # Output should mention dry-run
  [[ "$output" == *"dry-run"* ]]
}

@test "add -n is alias for --dry-run" {
  local repo upstream
  repo=$(create_monorepo)
  upstream=$(create_upstream "foo")
  cd "$repo"
  
  run platypus subtree add lib/foo "$upstream" main -n
  [ "$status" -eq 0 ]
  [ ! -d "lib/foo" ]
  [[ "$output" == *"dry-run"* ]]
}

@test "pull --dry-run doesn't change files" {
  local setup repo work_dir
  setup=$(setup_subtree_repo)
  repo=$(parse_subtree_setup "$setup" repo)
  work_dir=$(parse_subtree_setup "$setup" workdir)
  
  cd "$repo"
  local before_upstream
  before_upstream=$(git config -f .gitsubtrees subtree.lib/foo.upstream)
  
  # Add new content upstream
  upstream_add_file "$work_dir" "new.txt"
  
  run platypus subtree pull lib/foo --dry-run
  [ "$status" -eq 0 ]
  
  # New file should NOT exist
  [ ! -f "lib/foo/new.txt" ]
  
  # Config should be unchanged
  local after_upstream
  after_upstream=$(git config -f .gitsubtrees subtree.lib/foo.upstream)
  [ "$before_upstream" = "$after_upstream" ]
}

@test "push --dry-run doesn't push to remote" {
  local setup repo upstream
  setup=$(setup_subtree_repo)
  repo=$(parse_subtree_setup "$setup" repo)
  upstream=$(parse_subtree_setup "$setup" upstream)
  
  cd "$repo"
  
  # Make local change
  echo "local change" > lib/foo/local.txt
  git add lib/foo/local.txt
  git commit -m "Local change"
  
  # Get upstream HEAD before
  local before_head
  before_head=$(git -C "$upstream" rev-parse HEAD)
  
  run platypus subtree push lib/foo --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"dry-run"* ]]
  
  # Upstream HEAD should be unchanged
  local after_head
  after_head=$(git -C "$upstream" rev-parse HEAD)
  [ "$before_head" = "$after_head" ]
}
