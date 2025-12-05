#!/usr/bin/env bats
#
# svn-commits.bats - Tests for SVN commit discovery and linear history
#
# These tests verify the commit walking logic that ensures we get a
# linear first-parent history, especially important when subtrees
# are involved (their history is "behind" merge commits).
#

load test_helper

# Source platypus-svn to access internal functions
setup() {
  rm -rf "$TEST_TMP"
  mkdir -p "$TEST_TMP"
  cd "$TEST_TMP"
  source "$PLATYPUS_ROOT/lib/platypus-svn"
}

#------------------------------------------------------------------------------
# Helper to create a mock git-svn setup
#------------------------------------------------------------------------------

# Creates a repo that looks like it has git-svn configured
# (without actually needing SVN)
create_mock_svn_repo() {
  local name=${1:-repo}
  local dir
  dir=$(create_repo "$name")
  
  (
    cd "$dir"
    
    # Initial commit
    echo "initial" > file.txt
    git add file.txt
    git commit -m "Initial commit"
    
    # Create a fake SVN remote ref (simulates git-svn tracking)
    # This points to the same commit as main for initial setup
    git update-ref refs/remotes/git-svn HEAD
    
    # Create svn branch pointing to same place
    git branch svn HEAD
    
    # Create origin remote
    git remote add origin "file://$dir"
    
    # Create marker branch
    git update-ref refs/remotes/origin/svn-marker HEAD
  ) >/dev/null
  
  echo "$dir"
}

# Add a simple commit to main
add_commit() {
  local file=$1
  local content=${2:-"content"}
  local message=${3:-"Add $file"}
  
  echo "$content" > "$file"
  git add "$file"
  git commit -m "$message"
}

# Add a subtree (simulates adding a library)
add_subtree_commits() {
  local prefix=$1
  local num_commits=${2:-3}
  
  # Create a separate repo for the "library"
  local lib_dir="$TEST_TMP/lib-upstream"
  mkdir -p "$lib_dir"
  (
    cd "$lib_dir"
    git init -b main
    git config user.name "Test"
    git config user.email "test@test.com"
    
    for i in $(seq 1 $num_commits); do
      echo "lib content $i" > "lib-file-$i.txt"
      git add "lib-file-$i.txt"
      git commit -m "Lib commit $i"
    done
  ) >/dev/null
  
  # Add as subtree (this creates a merge commit)
  git subtree add --prefix="$prefix" "$lib_dir" main -m "Add $prefix subtree"
}

#------------------------------------------------------------------------------
# First-parent commit discovery tests
#------------------------------------------------------------------------------

@test "commit list walks first-parent only" {
  local repo
  repo=$(create_mock_svn_repo)
  cd "$repo"
  
  # Add a subtree (creates merge commit with library history behind it)
  add_subtree_commits "lib/foo" 3
  
  # Add more commits on main
  add_commit "main-file.txt" "main content" "Main commit after subtree"
  
  # Get the commit list using internal function
  local TIP BASE
  TIP=$(git rev-parse HEAD)
  BASE=$(git rev-parse refs/remotes/origin/svn-marker)
  
  # Build commit list (first-parent only)
  local COMMITS
  COMMITS=$(git rev-list --first-parent --ancestry-path "$BASE..$TIP" | tac)
  
  # Count commits - should only be 2 (subtree merge + main commit)
  # NOT 5 (which would include the 3 library commits)
  local count
  count=$(echo "$COMMITS" | wc -l | tr -d ' ')
  
  [ "$count" -eq 2 ]
}

@test "subtree history is not included in commit list" {
  local repo
  repo=$(create_mock_svn_repo)
  cd "$repo"
  
  # Add subtree with distinctive commit messages
  add_subtree_commits "lib/foo" 3
  
  # Get commit list
  local TIP BASE COMMITS
  TIP=$(git rev-parse HEAD)
  BASE=$(git rev-parse refs/remotes/origin/svn-marker)
  
  COMMITS=$(git rev-list --first-parent --ancestry-path "$BASE..$TIP")
  
  # Check that none of the library commits are in the list
  for commit in $COMMITS; do
    local message
    message=$(git log -1 --format=%s "$commit")
    [[ "$message" != *"Lib commit"* ]]
  done
}

@test "multiple subtrees don't pollute commit list" {
  local repo
  repo=$(create_mock_svn_repo)
  cd "$repo"
  
  # Add first subtree
  add_subtree_commits "lib/foo" 2
  
  # Add main commit
  add_commit "between.txt" "between" "Between subtrees"
  
  # Add second subtree
  local lib2_dir="$TEST_TMP/lib2-upstream"
  mkdir -p "$lib2_dir"
  (
    cd "$lib2_dir"
    git init -b main
    git config user.name "Test"
    git config user.email "test@test.com"
    echo "lib2" > lib2.txt
    git add lib2.txt
    git commit -m "Lib2 commit"
  ) >/dev/null
  
  git subtree add --prefix="lib/bar" "$lib2_dir" main -m "Add lib/bar subtree"
  
  # Final main commit
  add_commit "final.txt" "final" "Final commit"
  
  # Get commit list
  local TIP BASE COMMITS
  TIP=$(git rev-parse HEAD)
  BASE=$(git rev-parse refs/remotes/origin/svn-marker)
  
  COMMITS=$(git rev-list --first-parent --ancestry-path "$BASE..$TIP")
  
  # Should be 4 commits: subtree1 merge, between, subtree2 merge, final
  local count
  count=$(echo "$COMMITS" | wc -l | tr -d ' ')
  
  [ "$count" -eq 4 ]
}

@test "empty commits are identified" {
  local repo
  repo=$(create_mock_svn_repo)
  cd "$repo"
  
  # Add a commit
  add_commit "file1.txt" "content1" "First commit"
  
  # Create an empty merge (subtree with no changes to export)
  # This simulates a subtree pull where nothing changed in main
  git commit --allow-empty -m "Empty merge commit"
  
  # The empty commit should still be in the list
  local TIP BASE COMMITS
  TIP=$(git rev-parse HEAD)
  BASE=$(git rev-parse refs/remotes/origin/svn-marker)
  
  COMMITS=$(git rev-list --first-parent --ancestry-path "$BASE..$TIP")
  local count
  count=$(echo "$COMMITS" | wc -l | tr -d ' ')
  
  [ "$count" -eq 2 ]
}

#------------------------------------------------------------------------------
# Patch generation tests
#------------------------------------------------------------------------------

@test "patch from merge commit only includes net changes" {
  local repo
  repo=$(create_mock_svn_repo)
  cd "$repo"
  
  # Add subtree
  add_subtree_commits "lib/foo" 2
  
  # Get the merge commit
  local merge_commit
  merge_commit=$(git rev-parse HEAD)
  
  # Generate patch (diff from first parent)
  local patch
  patch=$(git diff "${merge_commit}^1..${merge_commit}")
  
  # Patch should contain the library files
  [[ "$patch" == *"lib/foo/lib-file-1.txt"* ]]
  [[ "$patch" == *"lib/foo/lib-file-2.txt"* ]]
}

@test "sequential commits generate correct patches" {
  local repo
  repo=$(create_mock_svn_repo)
  cd "$repo"
  
  add_commit "file1.txt" "content1" "Commit 1"
  add_commit "file2.txt" "content2" "Commit 2"
  add_commit "file3.txt" "content3" "Commit 3"
  
  # Each commit should have a patch with only its changes
  local commits
  commits=$(git rev-list --first-parent HEAD~3..HEAD | tac)
  
  local i=1
  for commit in $commits; do
    local patch
    patch=$(git diff "${commit}^1..${commit}" 2>/dev/null || git show --format= "$commit")
    
    # Should contain only file$i.txt
    [[ "$patch" == *"file${i}.txt"* ]]
    
    # Should NOT contain other files
    if [ $i -lt 3 ]; then
      [[ "$patch" != *"file$((i+1)).txt"* ]]
    fi
    
    ((i++))
  done
}

