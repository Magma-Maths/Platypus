#!/usr/bin/env bats
# shellcheck disable=SC2164,SC2034  # cd failures handled by bats; unused vars are for clarity
#
# subtree-sync.bats - Tests for 'platypus subtree sync' command and divergent scenarios
#

load test_helper

#------------------------------------------------------------------------------
# Basic sync tests
#------------------------------------------------------------------------------

@test "sync pulls then pushes" {
  local setup repo upstream work_dir
  setup=$(setup_subtree_repo)
  repo=$(parse_subtree_setup "$setup" repo)
  upstream=$(parse_subtree_setup "$setup" upstream)
  work_dir=$(parse_subtree_setup "$setup" workdir)
  
  cd "$repo"
  
  # Add local change to subtree
  monorepo_add_subtree_file "lib/foo" "local.txt" "local content"
  
  # Add upstream change
  upstream_add_file "$work_dir" "upstream.txt" "upstream content"
  
  # Sync should pull then push
  run platypus subtree sync lib/foo
  [ "$status" -eq 0 ]
  
  # Local file should still exist
  assert_file_exists "lib/foo/local.txt"
  
  # Upstream file should now exist locally
  assert_file_exists "lib/foo/upstream.txt"
  
  # Local change should be in upstream (pull work_dir to check)
  (cd "$work_dir" && git pull origin main >/dev/null 2>&1)
  [ -f "$work_dir/local.txt" ]
}

@test "sync updates config" {
  local setup repo work_dir
  setup=$(setup_subtree_repo)
  repo=$(parse_subtree_setup "$setup" repo)
  work_dir=$(parse_subtree_setup "$setup" workdir)
  
  cd "$repo"
  
  # Add changes on both sides
  monorepo_add_subtree_file "lib/foo" "local.txt" "local"
  upstream_add_file "$work_dir" "upstream.txt" "upstream"
  
  local initial_upstream initial_split
  initial_upstream=$(git config -f .gitsubtrees subtree.lib/foo.upstream 2>/dev/null || echo "")
  initial_split=$(git config -f .gitsubtrees subtree.lib/foo.splitSha 2>/dev/null || echo "")
  
  run platypus subtree sync lib/foo
  [ "$status" -eq 0 ]
  
  # Config should be updated
  local new_upstream new_split
  new_upstream=$(git config -f .gitsubtrees subtree.lib/foo.upstream)
  new_split=$(git config -f .gitsubtrees subtree.lib/foo.splitSha)
  
  [ "$initial_upstream" != "$new_upstream" ]
  [ -n "$new_split" ]
}

#------------------------------------------------------------------------------
# Divergent scenario tests
#------------------------------------------------------------------------------

@test "divergent setup creates both-sides-changed state" {
  local setup repo upstream work_dir
  setup=$(setup_divergent_subtree)
  repo=$(parse_subtree_setup "$setup" repo)
  upstream=$(parse_subtree_setup "$setup" upstream)
  work_dir=$(parse_subtree_setup "$setup" workdir)
  
  # Monorepo should have local change
  assert_file_exists "$repo/lib/foo/mono-change.txt"
  
  # Upstream work_dir should have its change
  assert_file_exists "$work_dir/upstream-change.txt"
  
  # But monorepo shouldn't have upstream change yet
  [ ! -f "$repo/lib/foo/upstream-change.txt" ]
}

@test "sync resolves divergent state" {
  local setup repo upstream work_dir
  setup=$(setup_divergent_subtree)
  repo=$(parse_subtree_setup "$setup" repo)
  upstream=$(parse_subtree_setup "$setup" upstream)
  work_dir=$(parse_subtree_setup "$setup" workdir)
  
  cd "$repo"
  
  # Sync should resolve divergence
  run platypus subtree sync lib/foo
  [ "$status" -eq 0 ]
  
  # Both changes should be in monorepo
  assert_file_exists "lib/foo/mono-change.txt"
  assert_file_exists "lib/foo/upstream-change.txt"
  
  # Both changes should be in upstream
  (cd "$work_dir" && git pull origin main >/dev/null 2>&1)
  [ -f "$work_dir/mono-change.txt" ]
  [ -f "$work_dir/upstream-change.txt" ]
}

@test "sync preserves file contents after divergent merge" {
  local setup repo upstream work_dir
  setup=$(setup_divergent_subtree)
  repo=$(parse_subtree_setup "$setup" repo)
  upstream=$(parse_subtree_setup "$setup" upstream)
  work_dir=$(parse_subtree_setup "$setup" workdir)
  
  cd "$repo"
  
  run platypus subtree sync lib/foo
  [ "$status" -eq 0 ]
  
  # Update work_dir
  (cd "$work_dir" && git pull origin main >/dev/null 2>&1)
  
  # Check content is correct
  assert_file_contains "lib/foo/mono-change.txt" "from monorepo"
  assert_file_contains "lib/foo/upstream-change.txt" "from upstream"
  
  # Upstream should have same content
  grep -q "from monorepo" "$work_dir/mono-change.txt"
  grep -q "from upstream" "$work_dir/upstream-change.txt"
}

#------------------------------------------------------------------------------
# First-parent history verification
#------------------------------------------------------------------------------

@test "sync maintains linear first-parent history" {
  local setup repo work_dir
  setup=$(setup_subtree_repo)
  repo=$(parse_subtree_setup "$setup" repo)
  work_dir=$(parse_subtree_setup "$setup" workdir)
  
  cd "$repo"
  
  # Record base commit
  local base_commit
  base_commit=$(git rev-parse HEAD)
  
  # Add changes on both sides
  monorepo_add_subtree_file "lib/foo" "local.txt" "local"
  upstream_add_file "$work_dir" "upstream.txt" "upstream"
  
  run platypus subtree sync lib/foo
  [ "$status" -eq 0 ]
  
  # First-parent history should be linear (no subtree internal commits)
  assert_linear_first_parent_history "$base_commit"
}

@test "multiple syncs maintain linear history" {
  local setup repo work_dir
  setup=$(setup_subtree_repo)
  repo=$(parse_subtree_setup "$setup" repo)
  work_dir=$(parse_subtree_setup "$setup" workdir)
  
  cd "$repo"
  
  local base_commit
  base_commit=$(git rev-parse HEAD)
  
  # First round of changes and sync
  monorepo_add_subtree_file "lib/foo" "local1.txt" "local1"
  upstream_add_file "$work_dir" "upstream1.txt" "upstream1"
  platypus subtree sync lib/foo >/dev/null
  
  # Second round - need to pull work_dir first since we pushed to it
  (cd "$work_dir" && git pull origin main >/dev/null 2>&1)
  monorepo_add_subtree_file "lib/foo" "local2.txt" "local2"
  upstream_add_file "$work_dir" "upstream2.txt" "upstream2"
  platypus subtree sync lib/foo >/dev/null
  
  # History should still be linear
  assert_linear_first_parent_history "$base_commit"
  
  # All files should exist
  assert_file_exists "lib/foo/local1.txt"
  assert_file_exists "lib/foo/local2.txt"
  assert_file_exists "lib/foo/upstream1.txt"
  assert_file_exists "lib/foo/upstream2.txt"
}

#------------------------------------------------------------------------------
# Error cases
#------------------------------------------------------------------------------

@test "sync fails if subtree not configured" {
  local repo
  repo=$(create_monorepo)
  cd "$repo"
  
  run platypus subtree sync lib/nonexistent
  [ "$status" -ne 0 ]
  [[ "$output" == *"not configured"* ]]
}

@test "sync fails without prefix argument" {
  local repo
  repo=$(create_monorepo)
  cd "$repo"
  
  run platypus subtree sync
  [ "$status" -ne 0 ]
}

#------------------------------------------------------------------------------
# Dry run
#------------------------------------------------------------------------------

@test "sync --dry-run shows what would happen" {
  local setup repo work_dir
  setup=$(setup_divergent_subtree)
  repo=$(parse_subtree_setup "$setup" repo)
  work_dir=$(parse_subtree_setup "$setup" workdir)
  
  cd "$repo"
  
  run platypus subtree sync lib/foo --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"dry-run"* ]]
  
  # Upstream file should NOT exist (dry-run)
  [ ! -f "lib/foo/upstream-change.txt" ]
}

