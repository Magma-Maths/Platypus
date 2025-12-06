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

#------------------------------------------------------------------------------
# Config value correctness tests
# These verify that config values point to valid, reachable commits
#------------------------------------------------------------------------------

@test "add: preMergeParent points to commit BEFORE the merge" {
  local result repo upstream work_dir
  result=$(setup_subtree_repo)
  repo=$(echo "$result" | cut -d'|' -f1)
  upstream=$(echo "$result" | cut -d'|' -f2)
  work_dir=$(echo "$result" | cut -d'|' -f3)
  
  cd "$repo"
  
  # Get the preMergeParent from config
  local preMergeParent
  preMergeParent=$(config:get "lib/foo" preMergeParent)
  
  # Get the current HEAD (the merge commit after amend)
  local current_head
  current_head=$(git rev-parse HEAD)
  
  # preMergeParent should NOT equal HEAD (it's before the merge)
  [ "$preMergeParent" != "$current_head" ]
  
  # preMergeParent should be an ancestor of HEAD
  run git merge-base --is-ancestor "$preMergeParent" "$current_head"
  [ "$status" -eq 0 ]
  
  # The first parent of HEAD should be preMergeParent
  # (after the amend, HEAD^ still points to the pre-merge state)
  local first_parent
  first_parent=$(git rev-parse HEAD^1)
  [ "$preMergeParent" = "$first_parent" ]
}

@test "add: preMergeParent is reachable after amend" {
  local result repo upstream work_dir
  result=$(setup_subtree_repo)
  repo=$(echo "$result" | cut -d'|' -f1)
  upstream=$(echo "$result" | cut -d'|' -f2)
  work_dir=$(echo "$result" | cut -d'|' -f3)
  
  cd "$repo"
  
  local preMergeParent
  preMergeParent=$(config:get "lib/foo" preMergeParent)
  
  # Verify the commit is reachable
  run git cat-file -t "$preMergeParent"
  [ "$status" -eq 0 ]
  [ "$output" = "commit" ]
  
  # Verify it's in the history (not orphaned)
  run git log --oneline "$preMergeParent" -1
  [ "$status" -eq 0 ]
}

@test "add: upstream points to the fetched upstream commit" {
  local result repo upstream work_dir
  result=$(setup_subtree_repo)
  repo=$(echo "$result" | cut -d'|' -f1)
  upstream=$(echo "$result" | cut -d'|' -f2)
  work_dir=$(echo "$result" | cut -d'|' -f3)
  
  cd "$repo"
  
  local recorded_upstream
  recorded_upstream=$(config:get "lib/foo" upstream)
  
  # Verify it's a valid commit SHA
  run git cat-file -t "$recorded_upstream"
  [ "$status" -eq 0 ]
  [ "$output" = "commit" ]
  
  # Verify it matches the upstream's HEAD
  cd "$upstream"
  local upstream_head
  upstream_head=$(git rev-parse HEAD)
  
  [ "$recorded_upstream" = "$upstream_head" ]
}

@test "pull: preMergeParent points to commit BEFORE the merge" {
  local result repo upstream work_dir
  result=$(setup_subtree_repo)
  repo=$(echo "$result" | cut -d'|' -f1)
  upstream=$(echo "$result" | cut -d'|' -f2)
  work_dir=$(echo "$result" | cut -d'|' -f3)
  
  # Add a commit to upstream
  cd "$work_dir"
  echo "new content" > new-file.txt
  git add new-file.txt
  git commit -m "Add new file"
  git push
  
  # Record pre-pull HEAD in monorepo
  cd "$repo"
  local pre_pull_head
  pre_pull_head=$(git rev-parse HEAD)
  
  # Pull
  run platypus subtree pull lib/foo
  [ "$status" -eq 0 ]
  
  # Get the preMergeParent from config
  local preMergeParent
  preMergeParent=$(config:get "lib/foo" preMergeParent)
  
  # preMergeParent should equal what HEAD was before pull
  [ "$preMergeParent" = "$pre_pull_head" ]
  
  # Current HEAD should be different (it's the merge commit)
  local current_head
  current_head=$(git rev-parse HEAD)
  [ "$preMergeParent" != "$current_head" ]
}

@test "pull: upstream is updated to the new upstream commit" {
  local result repo upstream work_dir
  result=$(setup_subtree_repo)
  repo=$(echo "$result" | cut -d'|' -f1)
  upstream=$(echo "$result" | cut -d'|' -f2)
  work_dir=$(echo "$result" | cut -d'|' -f3)
  
  cd "$repo"
  local old_upstream
  old_upstream=$(config:get "lib/foo" upstream)
  
  # Add a commit to upstream
  cd "$work_dir"
  echo "new content" > new-file.txt
  git add new-file.txt
  git commit -m "Add new file"
  git push
  
  local new_upstream_head
  new_upstream_head=$(git rev-parse HEAD)
  
  # Pull
  cd "$repo"
  run platypus subtree pull lib/foo
  [ "$status" -eq 0 ]
  
  # upstream should now be the new commit
  local recorded_upstream
  recorded_upstream=$(config:get "lib/foo" upstream)
  
  [ "$recorded_upstream" = "$new_upstream_head" ]
  [ "$recorded_upstream" != "$old_upstream" ]
}

@test "push: preMergeParent points to commit BEFORE the rejoin" {
  local result repo upstream work_dir
  result=$(setup_subtree_repo)
  repo=$(echo "$result" | cut -d'|' -f1)
  upstream=$(echo "$result" | cut -d'|' -f2)
  work_dir=$(echo "$result" | cut -d'|' -f3)
  
  cd "$repo"
  
  # Add a change to the subtree
  echo "mono change" > lib/foo/mono-file.txt
  git add lib/foo/mono-file.txt
  git commit -m "Add file from monorepo"
  
  # Record pre-push HEAD
  local pre_push_head
  pre_push_head=$(git rev-parse HEAD)
  
  # Push
  run platypus subtree push lib/foo
  [ "$status" -eq 0 ]
  
  # Get the preMergeParent from config
  local preMergeParent
  preMergeParent=$(config:get "lib/foo" preMergeParent)
  
  # preMergeParent should equal what HEAD was before push
  [ "$preMergeParent" = "$pre_push_head" ]
  
  # Current HEAD should be different (it's the rejoin commit)
  local current_head
  current_head=$(git rev-parse HEAD)
  [ "$preMergeParent" != "$current_head" ]
}

@test "push: splitSha points to valid extracted subtree commit" {
  local result repo upstream work_dir
  result=$(setup_subtree_repo)
  repo=$(echo "$result" | cut -d'|' -f1)
  upstream=$(echo "$result" | cut -d'|' -f2)
  work_dir=$(echo "$result" | cut -d'|' -f3)
  
  cd "$repo"
  
  # Add a change to the subtree
  echo "mono change" > lib/foo/mono-file.txt
  git add lib/foo/mono-file.txt
  git commit -m "Add file from monorepo"
  
  # Push
  run platypus subtree push lib/foo
  [ "$status" -eq 0 ]
  
  # Get splitSha
  local splitSha
  splitSha=$(config:get "lib/foo" splitSha)
  
  # Verify it's a valid commit
  run git cat-file -t "$splitSha"
  [ "$status" -eq 0 ]
  [ "$output" = "commit" ]
  
  # Verify it's in the upstream now
  cd "$work_dir"
  git fetch
  run git cat-file -t "$splitSha"
  [ "$status" -eq 0 ]
}

@test "init: preMergeParent is set to current HEAD" {
  local repo
  repo=$(create_monorepo)
  cd "$repo"
  
  # Create a directory to init as subtree
  mkdir -p lib/foo
  echo "content" > lib/foo/file.txt
  git add lib/foo
  git commit -m "Add lib/foo"
  
  local current_head
  current_head=$(git rev-parse HEAD)
  
  # Create a bare upstream
  local upstream
  upstream=$(create_bare_repo "upstream")
  
  # Init
  run platypus subtree init lib/foo -r "$upstream"
  [ "$status" -eq 0 ]
  
  # preMergeParent should equal current HEAD (no merge in init)
  local preMergeParent
  preMergeParent=$(config:get "lib/foo" preMergeParent)
  [ "$preMergeParent" = "$current_head" ]
}

