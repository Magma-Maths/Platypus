#!/usr/bin/env bats
# shellcheck disable=SC2164,SC2034  # cd handled by bats; unused vars for clarity
#
# subtree-failures.bats - Failure/resume scenarios for subtrees
#

load test_helper

make_git_wrapper_split_fail() {
  local dir="$TEST_TMP/fake-git-split-fail"
  local real_git
  real_git=$(command -v git)
  mkdir -p "$dir"
  cat > "$dir/git" <<'EOF'
#!/usr/bin/env bash
if [[ "$1" == "subtree" && "$2" == "split" ]]; then
  echo "forced git subtree split failure" >&2
  exit 1
fi
exec REAL_GIT_PLACEHOLDER "$@"
EOF
  chmod +x "$dir/git"
  # Replace placeholder with the absolute path to the real git to avoid recursion
  perl -pi -e "s|REAL_GIT_PLACEHOLDER|${real_git//\//\\/}|g" "$dir/git"
  export PATH="$dir:$PATH"
}

@test "subtree pull conflict leaves config untouched until resolved" {
  local setup repo work_dir upstream_before parent_before upstream_after parent_after
  setup=$(setup_subtree_repo)
  repo=$(parse_subtree_setup "$setup" repo)
  work_dir=$(parse_subtree_setup "$setup" workdir)

  cd "$repo"
  upstream_before=$(git config -f .gitsubtrees subtree.lib/foo.upstream)
  parent_before=$(git config -f .gitsubtrees subtree.lib/foo.preMergeParent)

  # Divergent changes to the same file to force conflict
  echo "local change" > lib/foo/file.txt
  git add lib/foo/file.txt
  git commit -m "Local conflicting change"

  (
    cd "$work_dir"
    echo "upstream change" > file.txt
    git add file.txt
    git commit -m "Upstream conflicting change"
    git push origin main
  ) >/dev/null 2>&1

  run platypus subtree pull lib/foo
  [ "$status" -ne 0 ]
  [[ "$output" == *"CONFLICT"* ]] || [[ "$output" == *"conflict"* ]]

  upstream_after=$(git config -f .gitsubtrees subtree.lib/foo.upstream)
  parent_after=$(git config -f .gitsubtrees subtree.lib/foo.preMergeParent)

  [ "$upstream_before" = "$upstream_after" ]
  [ "$parent_before" = "$parent_after" ]
}

@test "subtree push does not update config when split fails" {
  local setup repo split_before split_after
  setup=$(setup_subtree_repo)
  repo=$(parse_subtree_setup "$setup" repo)

  cd "$repo"
  echo "change" > lib/foo/split-fail.txt
  git add lib/foo/split-fail.txt
  git commit -m "Change to push"

  split_before=$(git config -f .gitsubtrees subtree.lib/foo.splitSha 2>/dev/null || echo "")

  make_git_wrapper_split_fail

  run timeout 30 platypus subtree push lib/foo
  [ "$status" -ne 0 ]
  [[ "$output" == *"split"* ]] || [[ "$output" == *"subtree"* ]]

  split_after=$(git config -f .gitsubtrees subtree.lib/foo.splitSha 2>/dev/null || echo "")
  [ "$split_before" = "$split_after" ]
}

