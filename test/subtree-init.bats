#!/usr/bin/env bats
# shellcheck disable=SC2164,SC2034  # cd failures handled by bats; unused vars are for clarity
#
# init.bats - Tests for 'platypus subtree init' command
#
# The init command links an existing directory to an existing upstream repo.
# It fetches from the upstream and merges to establish a merge base.

load test_helper

#------------------------------------------------------------------------------
# Helper: create an upstream repo with content
#------------------------------------------------------------------------------

create_upstream_repo() {
  local upstream="$TEST_TMP/upstream-$RANDOM"
  git init "$upstream" >/dev/null 2>&1
  cd "$upstream"
  echo "# Upstream Lib" > README.md
  echo "upstream content" > file.txt
  git add .
  git commit -m "Initial upstream commit" >/dev/null 2>&1
  echo "$upstream"
}

#------------------------------------------------------------------------------
# Basic init tests
#------------------------------------------------------------------------------

@test "init creates config and establishes merge base" {
  local repo upstream
  repo=$(create_monorepo)
  upstream=$(create_upstream_repo)
  cd "$repo"
  
  # Create a directory that looks like a subtree (with some content)
  mkdir -p lib/foo
  echo "local content" > lib/foo/local.txt
  git add lib/foo
  git commit -m "Add lib/foo locally"
  
  # Init should create config and merge with upstream
  run platypus subtree init lib/foo -r "$upstream"
  [ "$status" -eq 0 ]
  
  # Check config was created
  assert_file_exists ".gitsubtrees"
  assert_git_config ".gitsubtrees" "subtree.lib/foo.remote" "$upstream"
  assert_git_config ".gitsubtrees" "subtree.lib/foo.branch" "main"
  
  # Check merge brought in upstream content
  assert_file_exists "lib/foo/README.md"
  assert_file_content "lib/foo/README.md" "# Upstream Lib"
}

@test "init accepts -b branch option" {
  local repo upstream
  repo=$(create_monorepo)
  
  # Create upstream with develop branch
  upstream="$TEST_TMP/upstream-$RANDOM"
  git init "$upstream" >/dev/null 2>&1
  cd "$upstream"
  echo "content" > file.txt
  git add file.txt
  git commit -m "Initial" >/dev/null 2>&1
  git checkout -b develop >/dev/null 2>&1
  
  cd "$repo"
  mkdir -p lib/foo
  echo "local" > lib/foo/local.txt
  git add lib/foo
  git commit -m "Add lib/foo"
  
  run platypus subtree init lib/foo -r "$upstream" -b develop
  [ "$status" -eq 0 ]
  
  assert_git_config ".gitsubtrees" "subtree.lib/foo.branch" "develop"
}

@test "init records preMergeParent commit before merge" {
  local repo upstream
  repo=$(create_monorepo)
  upstream=$(create_upstream_repo)
  cd "$repo"
  
  mkdir -p lib/foo
  # Use a different file name to avoid conflict with upstream's file.txt
  echo "local content" > lib/foo/local.txt
  git add lib/foo
  git commit -m "Add lib/foo"
  
  local expected_preMergeParent
  expected_preMergeParent=$(git rev-parse HEAD)
  
  run platypus subtree init lib/foo -r "$upstream"
  [ "$status" -eq 0 ]
  
  local actual_preMergeParent
  actual_preMergeParent=$(git config -f .gitsubtrees subtree.lib/foo.preMergeParent)
  [ "$actual_preMergeParent" = "$expected_preMergeParent" ]
}

@test "init records upstream commit" {
  local repo upstream
  repo=$(create_monorepo)
  upstream=$(create_upstream_repo)
  local upstream_sha
  upstream_sha=$(cd "$upstream" && git rev-parse HEAD)
  
  cd "$repo"
  mkdir -p lib/foo
  # Use a different file name to avoid conflict with upstream's file.txt
  echo "local content" > lib/foo/local.txt
  git add lib/foo
  git commit -m "Add lib/foo"
  
  run platypus subtree init lib/foo -r "$upstream"
  [ "$status" -eq 0 ]
  
  local actual_upstream
  actual_upstream=$(git config -f .gitsubtrees subtree.lib/foo.upstream)
  [ "$actual_upstream" = "$upstream_sha" ]
}

@test "init allows subsequent pull" {
  local repo upstream
  repo=$(create_monorepo)
  upstream=$(create_upstream_repo)
  cd "$repo"
  
  mkdir -p lib/foo
  echo "local" > lib/foo/local.txt
  git add lib/foo
  git commit -m "Add lib/foo"
  
  run platypus subtree init lib/foo -r "$upstream"
  [ "$status" -eq 0 ]
  
  # Add content to upstream
  cd "$upstream"
  echo "new upstream file" > new.txt
  git add new.txt
  git commit -m "Add new file" >/dev/null 2>&1
  
  # Pull should work
  cd "$repo"
  run platypus subtree pull lib/foo
  [ "$status" -eq 0 ]
  
  # Should have new file
  assert_file_exists "lib/foo/new.txt"
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
  local repo upstream
  repo=$(create_monorepo)
  upstream=$(create_upstream_repo)
  cd "$repo"
  
  run platypus subtree init lib/nonexistent -r "$upstream"
  [ "$status" -ne 0 ]
  [[ "$output" == *"does not exist"* ]]
}

@test "init fails if directory is empty" {
  local repo upstream
  repo=$(create_monorepo)
  upstream=$(create_upstream_repo)
  cd "$repo"
  
  mkdir -p lib/empty
  
  run platypus subtree init lib/empty -r "$upstream"
  [ "$status" -ne 0 ]
  [[ "$output" == *"empty"* ]]
}

@test "init fails if subtree already configured" {
  local repo upstream
  repo=$(create_monorepo)
  upstream=$(create_upstream_repo)
  cd "$repo"
  
  mkdir -p lib/foo
  # Use a different file name to avoid conflict with upstream's file.txt
  echo "local content" > lib/foo/local.txt
  git add lib/foo
  git commit -m "Add lib/foo"
  
  # First init should succeed
  run platypus subtree init lib/foo -r "$upstream"
  [ "$status" -eq 0 ]
  
  # Second init should fail
  run platypus subtree init lib/foo -r "$upstream"
  [ "$status" -ne 0 ]
  [[ "$output" == *"already configured"* ]]
}

@test "init fails if remote not accessible" {
  local repo
  repo=$(create_monorepo)
  cd "$repo"
  
  mkdir -p lib/foo
  echo "content" > lib/foo/file.txt
  git add lib/foo
  git commit -m "Add lib/foo"
  
  run platypus subtree init lib/foo -r "/nonexistent/repo.git"
  [ "$status" -ne 0 ]
}

#------------------------------------------------------------------------------
# Dirty worktree
#------------------------------------------------------------------------------

@test "init fails with dirty working tree" {
  local repo upstream
  repo=$(create_monorepo)
  upstream=$(create_upstream_repo)
  cd "$repo"
  
  mkdir -p lib/foo
  echo "local content" > lib/foo/local.txt
  git add lib/foo
  git commit -m "Add lib/foo"
  
  # Create staged but uncommitted changes
  echo "dirty" > lib/foo/dirty.txt
  git add lib/foo/dirty.txt
  
  run platypus subtree init lib/foo -r "$upstream"
  [ "$status" -ne 0 ]
  [[ "$output" == *"unstaged"* ]] || [[ "$output" == *"uncommitted"* ]] || [[ "$output" == *"staged"* ]]
}

#------------------------------------------------------------------------------
# Dry run
#------------------------------------------------------------------------------

@test "init --dry-run shows what would happen" {
  local repo upstream
  repo=$(create_monorepo)
  upstream=$(create_upstream_repo)
  cd "$repo"
  
  mkdir -p lib/foo
  echo "content" > lib/foo/file.txt
  git add lib/foo
  git commit -m "Add lib/foo"
  
  run platypus subtree init lib/foo -r "$upstream" --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"dry-run"* ]]
  
  # Config file should NOT be created in dry-run
  [ ! -f ".gitsubtrees" ]
}

#------------------------------------------------------------------------------
# Prefix normalization
#------------------------------------------------------------------------------

@test "init normalizes prefix with trailing slash" {
  local repo upstream
  repo=$(create_monorepo)
  upstream=$(create_upstream_repo)
  cd "$repo"
  
  mkdir -p lib/foo
  echo "local content" > lib/foo/local.txt
  git add lib/foo
  git commit -m "Add lib/foo"
  
  run platypus subtree init lib/foo/ -r "$upstream"
  [ "$status" -eq 0 ]
  
  # Should be stored without trailing slash
  run git config -f .gitsubtrees subtree.lib/foo.remote
  [ "$status" -eq 0 ]
}

@test "init normalizes prefix with leading slash" {
  local repo upstream
  repo=$(create_monorepo)
  upstream=$(create_upstream_repo)
  cd "$repo"
  
  mkdir -p lib/foo
  echo "local content" > lib/foo/local.txt
  git add lib/foo
  git commit -m "Add lib/foo"
  
  run platypus subtree init /lib/foo -r "$upstream"
  [ "$status" -eq 0 ]
  
  # Should be stored without leading slash
  run git config -f .gitsubtrees subtree.lib/foo.remote
  [ "$status" -eq 0 ]
}
