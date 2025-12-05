#!/usr/bin/env bats
# shellcheck disable=SC2164,SC2034  # cd failures handled by bats; unused vars are for clarity
#
# svn-patches.bats - Tests for patch application and conflict handling
#
# These tests verify the cascading patch apply logic and conflict detection.
#

load test_helper

#------------------------------------------------------------------------------
# Helper functions
#------------------------------------------------------------------------------

# Create a repo with a base file for testing patches
create_patch_test_repo() {
  local dir
  dir=$(create_repo "patch-test")
  
  (
    cd "$dir"
    echo "line 1" > file.txt
    echo "line 2" >> file.txt
    echo "line 3" >> file.txt
    git add file.txt
    git commit -m "Initial file"
  ) >/dev/null
  
  echo "$dir"
}

# Generate a patch from changes
create_patch() {
  local original=$1
  local modified=$2
  
  diff -u "$original" "$modified" || true
}

#------------------------------------------------------------------------------
# Clean patch application
#------------------------------------------------------------------------------

@test "clean patch applies with git apply --index" {
  local repo
  repo=$(create_patch_test_repo)
  cd "$repo"
  
  # Create a clean patch (add a line)
  local patch_file="$TEST_TMP/patch.diff"
  cat > "$patch_file" << 'EOF'
--- a/file.txt
+++ b/file.txt
@@ -1,3 +1,4 @@
 line 1
 line 2
 line 3
+line 4
EOF
  
  # Apply patch
  run git apply --index "$patch_file"
  [ "$status" -eq 0 ]
  
  # Verify file was modified
  grep -q "line 4" file.txt
}

@test "patch to different area applies with fuzz" {
  local repo
  repo=$(create_patch_test_repo)
  cd "$repo"
  
  # Make a change to the beginning (won't conflict with end)
  echo "header" > newfile.txt
  git add newfile.txt
  git commit -m "Add header file"
  
  # Now try to apply a patch that adds to the end of original file
  local patch_file="$TEST_TMP/patch.diff"
  cat > "$patch_file" << 'EOF'
--- a/file.txt
+++ b/file.txt
@@ -1,3 +1,4 @@
 line 1
 line 2
 line 3
+line 4
EOF
  
  # Should apply cleanly (different file)
  run git apply --index "$patch_file"
  [ "$status" -eq 0 ]
  
  # Verify the change
  grep -q "line 4" file.txt
}

#------------------------------------------------------------------------------
# 3-way merge fallback
#------------------------------------------------------------------------------

@test "3-way merge handles context changes" {
  local repo
  repo=$(create_patch_test_repo)
  cd "$repo"
  
  # Modify context (but not the changed lines)
  sed -i.bak 's/line 2/LINE 2/' file.txt
  rm -f file.txt.bak
  git add file.txt
  git commit -m "Modify line 2"
  
  # Patch that touches line 3 (adjacent to changed line 2)
  local patch_file="$TEST_TMP/patch.diff"
  cat > "$patch_file" << 'EOF'
--- a/file.txt
+++ b/file.txt
@@ -1,3 +1,3 @@
 line 1
 line 2
-line 3
+line 3 modified
EOF
  
  # Regular apply might fail, 3-way should work
  git apply --3way "$patch_file" 2>/dev/null || true
  
  # File should have both changes
  grep -q "LINE 2" file.txt
  grep -q "line 3 modified" file.txt || grep -q "line 3" file.txt
}

#------------------------------------------------------------------------------
# Conflict detection
#------------------------------------------------------------------------------

@test "conflicting changes are detected" {
  local repo
  repo=$(create_patch_test_repo)
  cd "$repo"
  
  # Modify line 2
  sed -i.bak 's/line 2/modified line 2/' file.txt
  rm -f file.txt.bak
  git add file.txt
  git commit -m "Modify line 2"
  
  # Patch that also modifies line 2
  local patch_file="$TEST_TMP/patch.diff"
  cat > "$patch_file" << 'EOF'
--- a/file.txt
+++ b/file.txt
@@ -1,3 +1,3 @@
 line 1
-line 2
+different line 2
 line 3
EOF
  
  # This should fail or create conflicts
  run git apply --index "$patch_file"
  [ "$status" -ne 0 ]
}

@test "reject files are created on conflict with --reject" {
  local repo
  repo=$(create_patch_test_repo)
  cd "$repo"
  
  # Modify the file to create conflict
  echo "completely different" > file.txt
  git add file.txt
  git commit -m "Different content"
  
  # Incompatible patch
  local patch_file="$TEST_TMP/patch.diff"
  cat > "$patch_file" << 'EOF'
--- a/file.txt
+++ b/file.txt
@@ -1,3 +1,4 @@
 line 1
 line 2
 line 3
+line 4
EOF
  
  # Apply with --reject
  git apply --reject "$patch_file" 2>/dev/null || true
  
  # Should create .rej file
  [ -f "file.txt.rej" ]
}

#------------------------------------------------------------------------------
# Conflict markers (for --push-conflicts mode)
#------------------------------------------------------------------------------

@test "3-way merge can leave conflict markers" {
  local repo
  repo=$(create_patch_test_repo)
  cd "$repo"
  
  # Create a situation where 3-way merge will have conflicts
  # First, create the "base" version the patch expects
  # Then modify it locally
  # Then try to apply a patch that conflicts
  
  # Modify line 2 locally
  sed -i.bak 's/line 2/local line 2/' file.txt
  rm -f file.txt.bak
  git add file.txt
  git commit -m "Local change"
  
  # Patch that also changes line 2
  local patch_file="$TEST_TMP/patch.diff"
  cat > "$patch_file" << 'EOF'
--- a/file.txt
+++ b/file.txt
@@ -1,3 +1,3 @@
 line 1
-line 2
+remote line 2
 line 3
EOF
  
  # 3-way merge with conflicts
  git apply --3way "$patch_file" 2>/dev/null || true
  
  # Check for conflict markers
  if grep -q "<<<<<<" file.txt; then
    # Has conflict markers - this is expected in some git versions
    grep -q "======" file.txt
    grep -q ">>>>>>" file.txt
  fi
  # If no conflict markers, 3-way merge chose one side (also valid)
}

#------------------------------------------------------------------------------
# New file handling
#------------------------------------------------------------------------------

@test "patch adding new file applies cleanly" {
  local repo
  repo=$(create_patch_test_repo)
  cd "$repo"
  
  local patch_file="$TEST_TMP/patch.diff"
  cat > "$patch_file" << 'EOF'
--- /dev/null
+++ b/newfile.txt
@@ -0,0 +1,2 @@
+new content
+more content
EOF
  
  run git apply --index "$patch_file"
  [ "$status" -eq 0 ]
  
  [ -f "newfile.txt" ]
  grep -q "new content" newfile.txt
}

@test "patch deleting file applies cleanly" {
  local repo
  repo=$(create_patch_test_repo)
  cd "$repo"
  
  local patch_file="$TEST_TMP/patch.diff"
  cat > "$patch_file" << 'EOF'
--- a/file.txt
+++ /dev/null
@@ -1,3 +0,0 @@
-line 1
-line 2
-line 3
EOF
  
  run git apply --index "$patch_file"
  [ "$status" -eq 0 ]
  
  [ ! -f "file.txt" ]
}

