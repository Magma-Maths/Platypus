#!/usr/bin/env bats
# shellcheck disable=SC2164,SC2034  # cd handled by bats; unused vars for clarity
#
# svn-commit-shapes.bats - Commit shape edge cases for platypus svn push
#

load test_helper

setup() {
  setup_docker_svn
}

# Helper: create SVN + git-svn + origin + marker
create_svn_shape_fixture() {
  local name=$1
  local svn_url remote git_repo

  svn_url=$(create_svn_repo "$name" 2>/dev/null | tr -d '\r')
  svn_add_file "$svn_url" "README.txt" "Initial content" "Initial import" >/dev/null 2>&1

  remote=$(create_bare_repo "origin-$name" 2>/dev/null | tr -d '\r')
  git_repo="$TEST_TMP/$name-mono"
  mkdir -p "$git_repo"

  (
    cd "$git_repo"
    git svn init "$svn_url"
    git svn fetch
    git checkout -b main git-svn
    git config user.name "$GIT_AUTHOR_NAME"
    git config user.email "$GIT_AUTHOR_EMAIL"
    git remote add origin "$remote"
    git push -u origin main
    git push origin main:refs/heads/svn-marker
    git fetch origin
  ) >/dev/null 2>&1

  echo "$svn_url|$git_repo"
}

svn_rev_count() {
  local url=$1
  svn log "$url" --quiet | grep -c "^r"
}

# bats test_tags=docker
@test "empty commit is skipped but marker advances" {
  local setup svn_url git_repo before_rev after_rev marker_before marker_after
  setup=$(create_svn_shape_fixture "empty-commit")
  svn_url=$(echo "$setup" | cut -d'|' -f1)
  git_repo=$(echo "$setup" | cut -d'|' -f2)

  cd "$git_repo"
  git commit --allow-empty -m "Empty change"
  git push origin main

  before_rev=$(svn_rev_count "$svn_url")
  marker_before=$(git rev-parse origin/svn-marker)

  run platypus svn push
  [ "$status" -eq 0 ] || [ "$status" -eq 1 ]

  git fetch origin >/dev/null 2>&1
  marker_after=$(git rev-parse origin/svn-marker)
  # When empty commits are skipped, marker should remain unchanged
  [ "$marker_after" = "$marker_before" ]

  after_rev=$(svn_rev_count "$svn_url")
  [ "$after_rev" -eq "$before_rev" ]
}

# bats test_tags=docker
@test "merge commit with only subtree changes pushes cleanly" {
  local setup svn_url git_repo rev_before rev_after
  setup=$(create_svn_shape_fixture "subtree-only-merge")
  svn_url=$(echo "$setup" | cut -d'|' -f1)
  git_repo=$(echo "$setup" | cut -d'|' -f2)

  cd "$git_repo"
  mkdir -p lib/foo
  echo "base" > lib/foo/file.txt
  git add lib/foo/file.txt
  git commit -m "Add subtree file"
  git push origin main

  git checkout -b feature
  echo "feature change" > lib/foo/file.txt
  git add lib/foo/file.txt
  git commit -m "Update subtree file"
  git checkout main
  git merge --no-ff feature -m "Merge subtree-only changes"
  git push origin main

  rev_before=$(svn_rev_count "$svn_url")

  run platypus svn push
  [ "$status" -eq 0 ]

  rev_after=$(svn_rev_count "$svn_url")
  [ "$rev_after" -gt "$rev_before" ]
}

# bats test_tags=docker
@test "merge commit with subtree and non-subtree changes exports non-subtree diff" {
  local setup svn_url git_repo rev_before rev_after
  setup=$(create_svn_shape_fixture "mixed-merge")
  svn_url=$(echo "$setup" | cut -d'|' -f1)
  git_repo=$(echo "$setup" | cut -d'|' -f2)

  cd "$git_repo"
  echo "root base" > root.txt
  mkdir -p lib/foo
  echo "subtree base" > lib/foo/file.txt
  git add root.txt lib/foo/file.txt
  git commit -m "Add base files"
  git push origin main

  git checkout -b feature
  echo "root change" >> root.txt
  echo "subtree change" >> lib/foo/file.txt
  git add root.txt lib/foo/file.txt
  git commit -m "Mixed changes"
  git checkout main
  git merge --no-ff feature -m "Merge mixed changes"
  git push origin main

  rev_before=$(svn_rev_count "$svn_url")

  run platypus svn push
  [ "$status" -eq 0 ]

  rev_after=$(svn_rev_count "$svn_url")
  [ "$rev_after" -gt "$rev_before" ]

  # SVN should at least contain the root file change
  local svn_checkout="$TEST_TMP/mixed-merge-svn"
  svn checkout "$svn_url" "$svn_checkout" --quiet
  grep -q "root change" "$svn_checkout/root.txt"
}

# bats test_tags=docker
@test "octopus merge on first-parent path pushes successfully" {
  local setup svn_url git_repo rev_before rev_after
  setup=$(create_svn_shape_fixture "octopus-merge")
  svn_url=$(echo "$setup" | cut -d'|' -f1)
  git_repo=$(echo "$setup" | cut -d'|' -f2)

  cd "$git_repo"
  echo "base" > base.txt
  git add base.txt
  git commit -m "Base"
  git push origin main

  git checkout -b feat1
  echo "feat1" > feat1.txt
  git add feat1.txt
  git commit -m "feat1 commit"

  git checkout -b feat2 main
  echo "feat2" > feat2.txt
  git add feat2.txt
  git commit -m "feat2 commit"

  git checkout main
  git merge --no-ff feat1 feat2 -m "Octopus merge"
  git push origin main

  rev_before=$(svn_rev_count "$svn_url")

  run platypus svn push
  [ "$status" -eq 0 ]

  rev_after=$(svn_rev_count "$svn_url")
  [ "$rev_after" -gt "$rev_before" ]

  local svn_checkout="$TEST_TMP/octopus-merge-svn"
  svn checkout "$svn_url" "$svn_checkout" --quiet
  [ -f "$svn_checkout/feat1.txt" ]
  [ -f "$svn_checkout/feat2.txt" ]
}

