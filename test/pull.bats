#!/usr/bin/env bats
#
# pull.bats - Tests for 'platypus subtree pull' command
#

load test_helper

#------------------------------------------------------------------------------
# Helper to set up a repo with a subtree
#------------------------------------------------------------------------------

setup_with_subtree() {
  local repo upstream work_dir
  
  # Create upstream repo
  upstream=$(create_bare_repo "upstream")
  work_dir=$(create_repo "upstream_work")
  (
    cd "$work_dir"
    echo "initial content" > file.txt
    git add file.txt
    git commit -m "Initial commit"
    git remote add origin "$upstream"
    git push -u origin main
  ) >/dev/null
  
  # Create monorepo and add subtree
  repo=$(create_monorepo)
  (
    cd "$repo"
    platypus subtree add lib/foo "$upstream" main
  ) >/dev/null
  
  echo "$repo|$upstream|$work_dir"
}

#------------------------------------------------------------------------------
# Basic pull tests
#------------------------------------------------------------------------------

@test "pull merges upstream changes" {
  local setup repo upstream work_dir
  setup=$(setup_with_subtree)
  repo=$(echo "$setup" | cut -d'|' -f1)
  upstream=$(echo "$setup" | cut -d'|' -f2)
  work_dir=$(echo "$setup" | cut -d'|' -f3)
  
  # Add new content upstream
  (
    cd "$work_dir"
    echo "new content" > new_file.txt
    git add new_file.txt
    git commit -m "Add new file"
    git push origin main
  ) >/dev/null
  
  cd "$repo"
  
  # Pull should bring in new content
  run platypus subtree pull lib/foo
  [ "$status" -eq 0 ]
  
  # New file should exist
  assert_file_exists "lib/foo/new_file.txt"
}

@test "pull updates config with new upstream commit" {
  local setup repo upstream work_dir
  setup=$(setup_with_subtree)
  repo=$(echo "$setup" | cut -d'|' -f1)
  upstream=$(echo "$setup" | cut -d'|' -f2)
  work_dir=$(echo "$setup" | cut -d'|' -f3)
  
  # Get initial upstream SHA
  cd "$repo"
  local initial_upstream
  initial_upstream=$(git config -f .gitsubtrees subtree.lib/foo.upstream)
  
  # Add new content upstream
  (
    cd "$work_dir"
    echo "new content" > new_file.txt
    git add new_file.txt
    git commit -m "Add new file"
    git push origin main
  ) >/dev/null
  
  cd "$repo"
  
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
  local setup repo upstream work_dir
  setup=$(setup_with_subtree)
  repo=$(echo "$setup" | cut -d'|' -f1)
  upstream=$(echo "$setup" | cut -d'|' -f2)
  work_dir=$(echo "$setup" | cut -d'|' -f3)
  
  # Add new content upstream
  (
    cd "$work_dir"
    echo "new content" > new_file.txt
    git add new_file.txt
    git commit -m "Add new file"
    git push origin main
  ) >/dev/null
  
  cd "$repo"
  
  run platypus subtree pull lib/foo --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"dry-run"* ]]
  
  # New file should NOT exist (dry-run)
  [ ! -f "lib/foo/new_file.txt" ]
}

