#!/usr/bin/env bats
# shellcheck disable=SC2164,SC2034  # cd failures handled by bats; unused vars are for clarity
#
# common-options.bats - Tests for global option parsing across modules
#

load test_helper

# Helper to seed two subtree configs (no actual subtrees needed)
seed_subtree_config() {
  git config -f .gitsubtrees subtree.lib/foo.remote git@example.com:foo.git
  git config -f .gitsubtrees subtree.lib/foo.branch main
  git config -f .gitsubtrees subtree.lib/bar.remote git@example.com:bar.git
  git config -f .gitsubtrees subtree.lib/bar.branch develop
}

# Helper copied from svn-export.bats (lightweight git-svn mock)
create_mock_svn_repo() {
  local dir
  dir=$(create_repo "repo")
  
  (
    cd "$dir"
    
    # Initial commit
    echo "initial" > file.txt
    git add file.txt
    git commit -m "Initial commit"
    
    # Fake SVN tracking ref
    git update-ref refs/remotes/git-svn HEAD
    git branch svn HEAD
    
    # Remote
    git remote add origin "file://$dir"
    git push -u origin main 2>/dev/null || true
    
    # Marker branch on origin
    git push origin HEAD:refs/heads/svn-marker 2>/dev/null || true
    git fetch origin 2>/dev/null || true
  ) >/dev/null
  
  echo "$dir"
}

#------------------------------------------------------------------------------
# Position of global options
#------------------------------------------------------------------------------

@test "options before subcommand apply: subtree -q list" {
  local repo
  repo=$(create_monorepo)
  cd "$repo"
  seed_subtree_config
  
  run platypus subtree -q list
  [ "$status" -eq 0 ]
  [[ "$output" == *"lib/foo"* ]]
  [[ "$output" == *"lib/bar"* ]]
  [[ "$output" != *"Configured"* ]]
}

@test "options after subcommand apply: subtree list -q" {
  local repo
  repo=$(create_monorepo)
  cd "$repo"
  seed_subtree_config
  
  run platypus subtree list -q
  [ "$status" -eq 0 ]
  [[ "$output" == *"lib/foo"* ]]
  [[ "$output" == *"lib/bar"* ]]
  [[ "$output" != *"Configured"* ]]
}

@test "options before and after: quiet still wins" {
  local repo
  repo=$(create_monorepo)
  cd "$repo"
  seed_subtree_config
  
  run platypus subtree -v list -q
  [ "$status" -eq 0 ]
  [[ "$output" == *"lib/foo"* ]]
  [[ "$output" == *"lib/bar"* ]]
  [[ "$output" != *"Configured"* ]]
}

#------------------------------------------------------------------------------
# --help / --version with global flags around
#------------------------------------------------------------------------------

@test "subtree --help accepts surrounding global flags" {
  run platypus subtree -v --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage: platypus subtree"* ]]
}

@test "svn --help accepts surrounding global flags" {
  run platypus svn --help -n
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage: platypus svn"* ]]
}

#------------------------------------------------------------------------------
# Debug / tracing flags
#------------------------------------------------------------------------------

@test "--debug enables verbose RUN output (svn export)" {
  local repo
  repo=$(create_mock_svn_repo)
  cd "$repo"
  
  run platypus svn --debug export --dry-run 2>&1 || true
  [[ "$output" == *">>> git fetch"* ]]
  [[ "$output" == *"dry-run"* ]] || [[ "$output" == *"DRY RUN"* ]]
}

@test "-x turns on bash tracing" {
  run platypus subtree -x --help 2>&1
  [ "$status" -eq 0 ]
  [[ "$output" == *"+ subtree:usage"* ]] || [[ "$output" == *"+ usage"* ]] || [[ "$output" == *"+ platypus"* ]]
}

#------------------------------------------------------------------------------
# Mutually exclusive options
#------------------------------------------------------------------------------

@test "svn --continue --push-conflicts produces error" {
  run platypus svn --continue --push-conflicts
  [ "$status" -eq 1 ]
  [[ "$output" == *"Can't use both --continue and --push-conflicts"* ]]
}

@test "svn --continue --abort produces error" {
  run platypus svn --continue --abort
  [ "$status" -eq 1 ]
  [[ "$output" == *"Can't use both --continue and --abort"* ]]
}

