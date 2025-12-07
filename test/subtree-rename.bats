#!/usr/bin/env bats
# shellcheck disable=SC2164,SC2034  # cd handled by bats; unused vars for clarity
#
# subtree-rename.bats - Rename handling for subtrees
#

load test_helper

@test "subtree push handles rename-only changes inside subtree" {
  local setup repo work_dir
  setup=$(setup_subtree_repo)
  repo=$(parse_subtree_setup "$setup" repo)
  work_dir=$(parse_subtree_setup "$setup" workdir)

  cd "$repo"
  mv lib/foo/file.txt lib/foo/renamed.txt
  git add -A
  git commit -m "Rename file in subtree"

  run platypus subtree push lib/foo
  [ "$status" -eq 0 ]

  (cd "$work_dir" && git pull origin main >/dev/null 2>&1)
  [ -f "$work_dir/renamed.txt" ]
  [ ! -f "$work_dir/file.txt" ]
}

@test "subtree status flags renamed subtree root as missing" {
  local setup repo
  setup=$(setup_subtree_repo)
  repo=$(parse_subtree_setup "$setup" repo)

  cd "$repo"
  mv lib/foo lib/bar
  git add -A
  git commit -m "Rename subtree root directory"

  run platypus subtree status lib/foo
  [ "$status" -eq 0 ]
  [[ "$output" == *"MISSING"* ]] || [[ "$output" == *"missing"* ]]
}

