#!/usr/bin/env bats
# shellcheck disable=SC2164,SC2034  # cd failures handled by bats; unused vars are for clarity
#
# scripts.bats - Tests for COMMANDS.md helper scripts
#

load test_helper

clone_repo() {
  local dir="$TEST_TMP/platypus-clone-$RANDOM"
  git clone "$PLATYPUS_ROOT" "$dir" >/dev/null 2>&1
  # Overlay working tree changes (uncommitted) so tests exercise current state
  rsync -a --exclude '.git' "$PLATYPUS_ROOT"/ "$dir"/
  echo "$dir"
}

@test "update-commands-md is idempotent" {
  local repo
  repo=$(clone_repo)
  cd "$repo"
  
  ./scripts/update-commands-md
  git add COMMANDS.md
  git commit -m "refresh commands" >/dev/null
  
  run ./scripts/update-commands-md
  [ "$status" -eq 0 ]
  
  run git diff --quiet -- COMMANDS.md
  [ "$status" -eq 0 ]
}

@test "update-commands-md refreshes changed help output" {
  local repo
  repo=$(clone_repo)
  cd "$repo"
  
  # Tweak svn usage text to force a change
  perl -0pi -e 's/Sync Git main branch to SVN without rewriting Git history\./Sync Git main branch to SVN without rewriting Git history.\nTest usage tweak./' lib/platypus-svn
  
  run ./scripts/update-commands-md
  [ "$status" -eq 0 ]
  
  run grep -q "Test usage tweak" COMMANDS.md
  [ "$status" -eq 0 ]
}

@test "check-commands-md detects drift" {
  local repo
  repo=$(clone_repo)
  cd "$repo"
  
  ./scripts/update-commands-md
  git add COMMANDS.md
  git commit -m "commands baseline" >/dev/null
  
  perl -0pi -e 's/Usage: platypus/Usage: platypus DRIFT/' COMMANDS.md
  git add COMMANDS.md
  git commit -m "introduce drift" >/dev/null
  
  run ./scripts/check-commands-md
  [ "$status" -ne 0 ]
  [[ "$output" == *"out of date"* ]] || [[ "$output" == *"COMMANDS.md"* ]]
  
  # Drift should be removed by the script rewrite
  run grep -q "DRIFT" COMMANDS.md
  [ "$status" -ne 0 ]
}

@test "pre-commit hook blocks outdated COMMANDS.md" {
  local repo
  repo=$(clone_repo)
  cd "$repo"
  
  ./scripts/update-commands-md
  git add COMMANDS.md
  git commit -m "commands baseline" >/dev/null
  
  echo "HOOK_DRIFT" >> COMMANDS.md
  git add COMMANDS.md
  
  cat > .git/hooks/pre-commit <<'EOF'
#!/usr/bin/env bash
./scripts/check-commands-md
EOF
  chmod +x .git/hooks/pre-commit
  
  run git commit -m "attempt commit with drift"
  [ "$status" -ne 0 ]
  
  ./scripts/update-commands-md
  git add COMMANDS.md
  
  run git commit --allow-empty -m "commit after fixing drift"
  [ "$status" -eq 0 ]
}

