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

# Fake git wrapper to stub out git-svn calls (avoids real SVN access)
make_git_svn_noop_wrapper() {
  local dir="$TEST_TMP/fake-git-svn-noop"
  local real_git
  real_git=$(command -v git)

  mkdir -p "$dir"
  cat > "$dir/git" <<EOF
#!/usr/bin/env bash
REAL_GIT="$real_git"
case "\$1" in
  svn)
    exit 0
    ;;
  apply)
    # Force git apply to succeed without changing the index (simulate empty export)
    exit 0
    ;;
esac
exec "\$REAL_GIT" "\$@"
EOF
  chmod +x "$dir/git"
  export PATH="$dir:$PATH"
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

@test "marker advances when export plan only has empty commits" {
  local repo origin before_marker after_marker tip

  repo=$(create_repo "empty-export")
  origin=$(create_bare_repo "origin-empty")

  (
    cd "$repo"
    echo "base" > file.txt
    git add file.txt
    git commit -m "Initial commit"
    git remote add origin "$origin"
    git push -u origin main >/dev/null 2>&1

    # Simulate git-svn tracking and marker at the base commit
    git update-ref refs/remotes/git-svn HEAD
    git branch svn HEAD
    git push origin HEAD:refs/heads/svn-marker >/dev/null 2>&1
    git fetch origin >/dev/null 2>&1

    # Add an empty commit that should be skipped during export
    git commit --allow-empty -m "Empty export commit"
    git push origin main >/dev/null 2>&1
  )

  make_git_svn_noop_wrapper
  cd "$repo"
  git fetch origin >/dev/null 2>&1

  before_marker=$(git rev-parse origin/svn-marker)
  tip=$(git rev-parse origin/main)

  run platypus svn export
  [ "$status" -eq 0 ]
  [[ "$output" == *"No commits exported"* ]]

  git fetch origin >/dev/null 2>&1
  after_marker=$(git rev-parse origin/svn-marker)

  [ "$after_marker" = "$tip" ]
  [ "$before_marker" != "$after_marker" ]
}

