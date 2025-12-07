#!/usr/bin/env bats
# shellcheck disable=SC2164,SC2034  # cd handled by bats; unused vars for clarity
#
# subtree-history-edge.bats - History shape edge cases for subtrees
#

load test_helper

@test "subtree push handles large upstream divergence before first push" {
  local setup repo work_dir upstream
  setup=$(setup_subtree_repo)
  repo=$(parse_subtree_setup "$setup" repo)
  upstream=$(parse_subtree_setup "$setup" upstream)
  work_dir=$(parse_subtree_setup "$setup" workdir)

  # Upstream evolves independently
  upstream_add_file "$work_dir" "upstream-a.txt" "A"
  upstream_add_file "$work_dir" "upstream-b.txt" "B"
  upstream_add_file "$work_dir" "upstream-c.txt" "C"

  cd "$repo"
  echo "mono change" > lib/foo/mono-change.txt
  git add lib/foo/mono-change.txt
  git commit -m "Mono change after upstream divergence"

  run platypus subtree sync lib/foo
  [ "$status" -eq 0 ]

  # Upstream should contain both its own commits and the mono change
  (cd "$work_dir" && git pull origin main >/dev/null 2>&1)
  [ -f "$work_dir/upstream-a.txt" ]
  [ -f "$work_dir/upstream-b.txt" ]
  [ -f "$work_dir/upstream-c.txt" ]
  [ -f "$work_dir/mono-change.txt" ]
}

@test "repeated subtree sync with no changes is a no-op" {
  local setup repo upstream work_dir head_before head_after upstream_before upstream_after split_before split_after
  setup=$(setup_subtree_repo)
  repo=$(parse_subtree_setup "$setup" repo)
  upstream=$(parse_subtree_setup "$setup" upstream)
  work_dir=$(parse_subtree_setup "$setup" workdir)

  cd "$repo"
  run platypus subtree sync lib/foo
  [ "$status" -eq 0 ]

  upstream_before=$(git config -f .gitsubtrees subtree.lib/foo.upstream)
  split_before=$(git config -f .gitsubtrees subtree.lib/foo.splitSha 2>/dev/null || echo "")
  head_before=$(git rev-parse HEAD)
  local upstream_tip_before
  upstream_tip_before=$(
    cd "$work_dir"
    git pull origin main >/dev/null 2>&1
    git rev-parse HEAD
  )

  run platypus subtree sync lib/foo
  [ "$status" -eq 0 ]

  upstream_after=$(git config -f .gitsubtrees subtree.lib/foo.upstream)
  split_after=$(git config -f .gitsubtrees subtree.lib/foo.splitSha 2>/dev/null || echo "")
  head_after=$(git rev-parse HEAD)

  # Allow no-op except for possible config amend (preMergeParent may advance)
  [ "$upstream_before" = "$upstream_after" ]
  [ "$split_before" = "$split_after" ]

  # Upstream tip should stay unchanged
  local upstream_tip_after
  upstream_tip_after=$(
    cd "$work_dir"
    git pull origin main >/dev/null 2>&1
    git rev-parse HEAD
  )
  [ "$upstream_tip_before" = "$upstream_tip_after" ]
}

