#!/usr/bin/env bats
# shellcheck disable=SC2164,SC2034  # cd handled by bats; unused vars for clarity
#
# subtree-config-edge.bats - Config edge cases for platypus subtree
#

load test_helper

@test "subtree push recomputes splitSha when missing" {
  local setup repo work_dir splitSha
  setup=$(setup_subtree_repo)
  repo=$(parse_subtree_setup "$setup" repo)
  work_dir=$(parse_subtree_setup "$setup" workdir)

  cd "$repo"
  echo "local change" > lib/foo/local-missing-split.txt
  git add lib/foo/local-missing-split.txt
  git commit -m "Local change needing push"

  # Remove splitSha to simulate stale/missing config
  git config -f .gitsubtrees --unset subtree.lib/foo.splitSha 2>/dev/null || true

  run platypus subtree push lib/foo
  [ "$status" -eq 0 ]

  splitSha=$(git config -f .gitsubtrees subtree.lib/foo.splitSha 2>/dev/null || echo "")
  [ -n "$splitSha" ]

  # Verify upstream received the change
  (cd "$work_dir" && git pull origin main >/dev/null 2>&1)
  [ -f "$work_dir/local-missing-split.txt" ]
}

@test "subtree sync refreshes stale preMergeParent" {
  local setup repo work_dir old_parent new_parent
  setup=$(setup_subtree_repo)
  repo=$(parse_subtree_setup "$setup" repo)
  work_dir=$(parse_subtree_setup "$setup" workdir)

  cd "$repo"
  old_parent=$(git config -f .gitsubtrees subtree.lib/foo.preMergeParent)

  # Create changes on both sides to force a real sync
  upstream_add_file "$work_dir" "upstream-stale.txt" "from upstream"
  echo "mono change" > lib/foo/mono-stale.txt
  git add lib/foo/mono-stale.txt
  git commit -m "Mono change before sync"

  # Corrupt preMergeParent to an old commit
  git config -f .gitsubtrees subtree.lib/foo.preMergeParent "$(git rev-parse HEAD~1)"
  git add .gitsubtrees
  git commit -m "Corrupt preMergeParent for test"

  run platypus subtree sync lib/foo
  [ "$status" -eq 0 ]

  new_parent=$(git config -f .gitsubtrees subtree.lib/foo.preMergeParent)
  [ "$new_parent" != "$old_parent" ]

  # Config should now point to a recent commit (HEAD before rejoin), so it must exist
  git rev-parse "$new_parent" >/dev/null
}

@test "subtree add rejects overlapping prefixes" {
  local repo upstream
  repo=$(create_monorepo)
  upstream=$(create_upstream "overlap-upstream")
  cd "$repo"

  platypus subtree add lib/foo "$upstream" main >/dev/null

  # Child overlap
  run platypus subtree add lib/foo/bar "$upstream" main
  [ "$status" -ne 0 ]

  # Parent overlap
  run platypus subtree add lib "$upstream" main
  [ "$status" -ne 0 ]
}

