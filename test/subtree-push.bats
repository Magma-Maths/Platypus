#!/usr/bin/env bats
#
# subtree-push.bats - Tests for 'platypus subtree push' command
#

load test_helper

#------------------------------------------------------------------------------
# Basic push tests
#------------------------------------------------------------------------------

@test "push sends local changes to upstream" {
  local setup repo upstream work_dir
  setup=$(setup_subtree_repo)
  repo=$(parse_subtree_setup "$setup" repo)
  upstream=$(parse_subtree_setup "$setup" upstream)
  work_dir=$(parse_subtree_setup "$setup" workdir)
  
  cd "$repo"
  
  # Make local changes to subtree
  echo "local change" > lib/foo/local.txt
  git add lib/foo/local.txt
  git commit -m "Add local file to subtree"
  
  # Push should send changes upstream
  run platypus subtree push lib/foo
  [ "$status" -eq 0 ]
  
  # Verify change is in upstream
  (
    cd "$work_dir"
    git pull origin main
    [ -f "local.txt" ]
  )
}

@test "push records splitSha for incremental optimization" {
  local setup repo
  setup=$(setup_subtree_repo)
  repo=$(parse_subtree_setup "$setup" repo)
  
  cd "$repo"
  
  # Make local changes
  echo "local change" > lib/foo/local.txt
  git add lib/foo/local.txt
  git commit -m "Add local file"
  
  # Push
  run platypus subtree push lib/foo
  [ "$status" -eq 0 ]
  
  # Should have splitSha recorded
  local splitSha
  splitSha=$(git config -f .gitsubtrees subtree.lib/foo.splitSha 2>/dev/null || echo "")
  [ -n "$splitSha" ]
}

@test "second push succeeds and updates splitSha" {
  local setup repo
  setup=$(setup_subtree_repo)
  repo=$(parse_subtree_setup "$setup" repo)
  
  cd "$repo"
  
  # First push
  echo "first change" > lib/foo/first.txt
  git add lib/foo/first.txt
  git commit -m "First change"
  platypus subtree push lib/foo >/dev/null
  
  local first_splitSha
  first_splitSha=$(git config -f .gitsubtrees subtree.lib/foo.splitSha)
  
  # Second push
  echo "second change" > lib/foo/second.txt
  git add lib/foo/second.txt
  git commit -m "Second change"
  
  run platypus subtree push lib/foo
  [ "$status" -eq 0 ]
  
  # splitSha should be updated
  local second_splitSha
  second_splitSha=$(git config -f .gitsubtrees subtree.lib/foo.splitSha)
  [ "$first_splitSha" != "$second_splitSha" ]
}

#------------------------------------------------------------------------------
# Error cases
#------------------------------------------------------------------------------

@test "push fails if subtree not configured" {
  local repo
  repo=$(create_monorepo)
  cd "$repo"
  
  run platypus subtree push lib/nonexistent
  [ "$status" -ne 0 ]
  [[ "$output" == *"not configured"* ]]
}

@test "push fails without prefix argument" {
  local repo
  repo=$(create_monorepo)
  cd "$repo"
  
  run platypus subtree push
  [ "$status" -ne 0 ]
}

#------------------------------------------------------------------------------
# Dry run
#------------------------------------------------------------------------------

@test "push --dry-run shows what would happen" {
  local setup repo
  setup=$(setup_subtree_repo)
  repo=$(parse_subtree_setup "$setup" repo)
  
  cd "$repo"
  
  # Make local changes
  echo "local change" > lib/foo/local.txt
  git add lib/foo/local.txt
  git commit -m "Add local file"
  
  run platypus subtree push lib/foo --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"dry-run"* ]]
  
  # Should NOT have splitSha (dry run doesn't update config)
  local splitSha
  splitSha=$(git config -f .gitsubtrees subtree.lib/foo.splitSha 2>/dev/null || echo "")
  [ -z "$splitSha" ]
}
