#!/usr/bin/env bats
# shellcheck disable=SC2164,SC2034  # cd handled by bats; unused vars for clarity
#
# svn-marker-edge.bats - Marker edge-case tests for platypus svn export
#

load test_helper

setup() {
  # Use lightweight mock setup (no Docker)
  rm -rf "$TEST_TMP"
  mkdir -p "$TEST_TMP"
  cd "$TEST_TMP"
}

# Creates a repo with git-svn-style refs and origin/marker configured
create_mock_svn_repo() {
  local dir
  dir=$(create_repo "repo")

  (
    cd "$dir"
    echo "initial" > file.txt
    git add file.txt
    git commit -m "Initial commit"

    # Fake git-svn tracking ref and svn branch
    git update-ref refs/remotes/git-svn HEAD
    git branch svn HEAD

    # Create origin remote pointing to itself
    git remote add origin "file://$dir"
    git push -u origin main >/dev/null 2>&1 || true

    # Marker at HEAD
    git push origin HEAD:refs/heads/svn-marker >/dev/null 2>&1 || true
    git fetch origin >/dev/null 2>&1 || true
  ) >/dev/null

  echo "$dir"
}

@test "svn export fails when marker is off the first-parent path" {
  local repo marker_commit
  repo=$(create_mock_svn_repo)
  cd "$repo"

  # Create a side branch and merge it; marker will be set to the side branch tip
  git checkout -b feature
  echo "side" > side.txt
  git add side.txt
  git commit -m "Side commit"
  marker_commit=$(git rev-parse HEAD)

  git checkout main
  git merge --no-ff feature -m "Merge feature"

  # Force marker to the side commit (not on first-parent path)
  git push origin "$marker_commit:refs/heads/svn-marker" --force >/dev/null 2>&1
  git fetch origin >/dev/null 2>&1

  run platypus svn export --dry-run
  [ "$status" -ne 0 ]
  [[ "$output" == *"first-parent"* ]] || [[ "$output" == *"Stale marker"* ]]
}

