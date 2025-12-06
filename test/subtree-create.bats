#!/usr/bin/env bats
# shellcheck disable=SC2164,SC2034  # cd failures handled by bats; unused vars are for clarity
#
# subtree-create.bats - Tests for 'platypus subtree create' command
#

load test_helper

#------------------------------------------------------------------------------
# Helper: create a bare upstream repo
#------------------------------------------------------------------------------

create_bare_upstream() {
  local upstream="$TEST_TMP/upstream-$RANDOM"
  git init --bare "$upstream" >/dev/null 2>&1
  echo "$upstream"
}

#------------------------------------------------------------------------------
# Basic create tests
#------------------------------------------------------------------------------

@test "create exports directory to upstream" {
  local repo upstream
  repo=$(create_monorepo)
  upstream=$(create_bare_upstream)
  cd "$repo"
  
  # Create a directory with content
  mkdir -p lib/foo
  echo "# Foo Library" > lib/foo/README.md
  echo "content" > lib/foo/file.txt
  git add lib/foo
  git commit -m "Add lib/foo"
  
  # Create should export to upstream
  run platypus subtree create lib/foo "$upstream" -b main
  [ "$status" -eq 0 ]
  
  # Check config was created
  assert_file_exists ".gitsubtrees"
  assert_git_config ".gitsubtrees" "subtree.lib/foo.remote" "$upstream"
  assert_git_config ".gitsubtrees" "subtree.lib/foo.branch" "main"
}

@test "create pushes content to upstream" {
  local repo upstream work_dir
  repo=$(create_monorepo)
  upstream=$(create_bare_upstream)
  cd "$repo"
  
  # Create a directory with content
  mkdir -p lib/foo
  echo "# Foo Library" > lib/foo/README.md
  echo "content" > lib/foo/file.txt
  git add lib/foo
  git commit -m "Add lib/foo"
  
  # Create
  run platypus subtree create lib/foo "$upstream" -b main
  [ "$status" -eq 0 ]
  
  # Clone upstream and verify content
  work_dir="$TEST_TMP/work-$RANDOM"
  git clone "$upstream" "$work_dir" >/dev/null 2>&1
  
  assert_file_exists "$work_dir/README.md"
  assert_file_exists "$work_dir/file.txt"
  assert_file_content "$work_dir/README.md" "# Foo Library"
}

@test "create sets splitSha for incremental push" {
  local repo upstream
  repo=$(create_monorepo)
  upstream=$(create_bare_upstream)
  cd "$repo"
  
  mkdir -p lib/foo
  echo "content" > lib/foo/file.txt
  git add lib/foo
  git commit -m "Add lib/foo"
  
  run platypus subtree create lib/foo "$upstream"
  [ "$status" -eq 0 ]
  
  # splitSha should be set
  local split_sha
  split_sha=$(git config -f .gitsubtrees subtree.lib/foo.splitSha)
  [ -n "$split_sha" ]
}

@test "create sets preMergeParent before rejoin" {
  local repo upstream
  repo=$(create_monorepo)
  upstream=$(create_bare_upstream)
  cd "$repo"
  
  mkdir -p lib/foo
  echo "content" > lib/foo/file.txt
  git add lib/foo
  git commit -m "Add lib/foo"
  
  local expected_preMergeParent
  expected_preMergeParent=$(git rev-parse HEAD)
  
  run platypus subtree create lib/foo "$upstream"
  [ "$status" -eq 0 ]
  
  local actual_preMergeParent
  actual_preMergeParent=$(git config -f .gitsubtrees subtree.lib/foo.preMergeParent)
  [ "$actual_preMergeParent" = "$expected_preMergeParent" ]
}

@test "create allows subsequent push" {
  local repo upstream work_dir
  repo=$(create_monorepo)
  upstream=$(create_bare_upstream)
  cd "$repo"
  
  # Create directory and export
  mkdir -p lib/foo
  echo "original" > lib/foo/file.txt
  git add lib/foo
  git commit -m "Add lib/foo"
  
  run platypus subtree create lib/foo "$upstream"
  [ "$status" -eq 0 ]
  
  # Make a local change
  echo "updated" > lib/foo/file.txt
  git add lib/foo
  git commit -m "Update foo"
  
  # Push should work (uses splitSha for incremental)
  run platypus subtree push lib/foo
  [ "$status" -eq 0 ]
  
  # Verify upstream has update
  work_dir="$TEST_TMP/work-$RANDOM"
  git clone "$upstream" "$work_dir" >/dev/null 2>&1
  assert_file_content "$work_dir/file.txt" "updated"
}

@test "create allows subsequent pull" {
  local repo upstream work_dir
  repo=$(create_monorepo)
  upstream=$(create_bare_upstream)
  cd "$repo"
  
  # Create directory and export
  mkdir -p lib/foo
  echo "original" > lib/foo/file.txt
  git add lib/foo
  git commit -m "Add lib/foo"
  
  run platypus subtree create lib/foo "$upstream"
  [ "$status" -eq 0 ]
  
  # Make an upstream change
  work_dir="$TEST_TMP/work-$RANDOM"
  git clone "$upstream" "$work_dir" >/dev/null 2>&1
  cd "$work_dir"
  echo "upstream change" > new_file.txt
  git add new_file.txt
  git commit -m "Add file from upstream"
  git push origin main
  
  # Pull should work
  cd "$repo"
  run platypus subtree pull lib/foo
  [ "$status" -eq 0 ]
  
  # Verify we got the upstream change
  assert_file_exists "lib/foo/new_file.txt"
}

#------------------------------------------------------------------------------
# Error cases
#------------------------------------------------------------------------------

@test "create fails if directory doesn't exist" {
  local repo upstream
  repo=$(create_monorepo)
  upstream=$(create_bare_upstream)
  cd "$repo"
  
  run platypus subtree create lib/nonexistent "$upstream"
  [ "$status" -ne 0 ]
  [[ "$output" == *"does not exist"* ]]
}

@test "create fails if directory is empty" {
  local repo upstream
  repo=$(create_monorepo)
  upstream=$(create_bare_upstream)
  cd "$repo"
  
  mkdir -p lib/empty
  
  run platypus subtree create lib/empty "$upstream"
  [ "$status" -ne 0 ]
  [[ "$output" == *"empty"* ]]
}

@test "create fails if already configured" {
  local repo upstream
  repo=$(create_monorepo)
  upstream=$(create_bare_upstream)
  cd "$repo"
  
  mkdir -p lib/foo
  echo "content" > lib/foo/file.txt
  git add lib/foo
  git commit -m "Add lib/foo"
  
  # First create should succeed
  run platypus subtree create lib/foo "$upstream"
  [ "$status" -eq 0 ]
  
  # Second create should fail
  local upstream2
  upstream2=$(create_bare_upstream)
  run platypus subtree create lib/foo "$upstream2"
  [ "$status" -ne 0 ]
  [[ "$output" == *"already configured"* ]]
}

@test "create fails if upstream not accessible" {
  local repo
  repo=$(create_monorepo)
  cd "$repo"
  
  mkdir -p lib/foo
  echo "content" > lib/foo/file.txt
  git add lib/foo
  git commit -m "Add lib/foo"
  
  run platypus subtree create lib/foo "/nonexistent/path/repo.git"
  [ "$status" -ne 0 ]
  [[ "$output" == *"Cannot access upstream"* ]]
}

@test "create fails without prefix argument" {
  local repo
  repo=$(create_monorepo)
  cd "$repo"
  
  run platypus subtree create
  [ "$status" -ne 0 ]
  [[ "$output" == *"Usage"* ]]
}

@test "create fails without upstream argument" {
  local repo
  repo=$(create_monorepo)
  cd "$repo"
  
  mkdir -p lib/foo
  echo "content" > lib/foo/file.txt
  git add lib/foo
  git commit -m "Add lib/foo"
  
  run platypus subtree create lib/foo
  [ "$status" -ne 0 ]
  [[ "$output" == *"Usage"* ]]
}

#------------------------------------------------------------------------------
# Dry run
#------------------------------------------------------------------------------

@test "create --dry-run shows what would happen" {
  local repo upstream
  repo=$(create_monorepo)
  upstream=$(create_bare_upstream)
  cd "$repo"
  
  mkdir -p lib/foo
  echo "content" > lib/foo/file.txt
  git add lib/foo
  git commit -m "Add lib/foo"
  
  run platypus subtree create lib/foo "$upstream" --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"dry-run"* ]]
  
  # Config file should NOT be created in dry-run
  [ ! -f ".gitsubtrees" ]
}

#------------------------------------------------------------------------------
# Prefix normalization
#------------------------------------------------------------------------------

@test "create normalizes prefix with trailing slash" {
  local repo upstream
  repo=$(create_monorepo)
  upstream=$(create_bare_upstream)
  cd "$repo"
  
  mkdir -p lib/foo
  echo "content" > lib/foo/file.txt
  git add lib/foo
  git commit -m "Add lib/foo"
  
  run platypus subtree create lib/foo/ "$upstream"
  [ "$status" -eq 0 ]
  
  # Should be stored without trailing slash
  run git config -f .gitsubtrees subtree.lib/foo.remote
  [ "$status" -eq 0 ]
}

