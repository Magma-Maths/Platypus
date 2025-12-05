#!/usr/bin/env bash
#
# run-tests.sh - Run tests and shellcheck locally (like CI)
#
# Usage:
#   ./run-tests.sh              # Run everything (shellcheck + tests)
#   ./run-tests.sh --shellcheck # Run only shellcheck
#   ./run-tests.sh --tests      # Run only bats tests
#   ./run-tests.sh --help       # Show help

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Flags
RUN_SHELLCHECK=true
RUN_TESTS=true

# Parse arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    --shellcheck)
      RUN_TESTS=false
      shift
      ;;
    --tests)
      RUN_SHELLCHECK=false
      shift
      ;;
    --help|-h)
      cat <<EOF
Usage: $0 [options]

Run tests and shellcheck locally (matching CI behavior).

Options:
  --shellcheck    Run only shellcheck
  --tests         Run only bats tests
  --help, -h      Show this help message

By default, runs both shellcheck and tests.
EOF
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      echo "Use --help for usage" >&2
      exit 1
      ;;
  esac
done

# Get script directory and repository root
# Script is in test/, so repo root is one level up
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

# Track if any checks failed
FAILED=0

# Function to print section header
section() {
  echo ""
  echo -e "${GREEN}=== $1 ===${NC}"
  echo ""
}

# Function to print error
error() {
  echo -e "${RED}✗ $1${NC}" >&2
}

# Function to print success
success() {
  echo -e "${GREEN}✓ $1${NC}"
}

# Function to print warning
warning() {
  echo -e "${YELLOW}⚠ $1${NC}"
}

# Check dependencies
check_deps() {
  local missing=0

  if ! command -v shellcheck &> /dev/null; then
    error "shellcheck is not installed"
    echo "  Install with: sudo apt-get install shellcheck  (Linux)"
    echo "                brew install shellcheck           (macOS)"
    missing=1
  fi

  if ! command -v bats &> /dev/null; then
    error "bats is not installed"
    echo "  Install with: sudo apt-get install bats          (Linux)"
    echo "                brew install bats-core             (macOS)"
    missing=1
  fi

  if [[ $missing -eq 1 ]]; then
    exit 1
  fi
}

# Run shellcheck
run_shellcheck() {
  section "Running shellcheck"

  local failed=0

  # Check lib scripts
  echo "Checking lib scripts..."
  if shellcheck lib/platypus lib/platypus-subtree lib/platypus-svn; then
    success "lib scripts passed shellcheck"
  else
    error "lib scripts failed shellcheck"
    failed=1
  fi

  echo ""
  echo "Checking test scripts..."
  if shellcheck -x test/*.bats test/test_helper.bash; then
    success "test scripts passed shellcheck"
  else
    error "test scripts failed shellcheck"
    failed=1
  fi

  if [[ $failed -eq 1 ]]; then
    return 1
  fi
  return 0
}

# Check git config (warn but don't modify)
check_git_config() {
  local missing=0

  if ! git config --global user.name &> /dev/null; then
    warning "git user.name is not set globally"
    echo "  Tests may fail. Set with: git config --global user.name 'Your Name'"
    missing=1
  fi

  if ! git config --global user.email &> /dev/null; then
    warning "git user.email is not set globally"
    echo "  Tests may fail. Set with: git config --global user.email 'your@email.com'"
    missing=1
  fi

  if [[ $missing -eq 1 ]]; then
    echo ""
  fi
}

# Run bats tests
run_tests() {
  section "Running bats tests"

  # .rc is required
  if [[ ! -f .rc ]]; then
    error ".rc file is required but not found"
    echo "  The .rc file sets up PLATYPUS_ROOT and PATH for tests"
    return 1
  fi

  # shellcheck disable=SC1091  # .rc file is required for tests
  source .rc

  # Check git config (warn but don't modify)
  check_git_config

  if bats test/; then
    success "All tests passed"
    return 0
  else
    error "Some tests failed"
    return 1
  fi
}

# Main
main() {
  echo "Platypus Test Runner"
  echo "===================="

  # Check dependencies
  check_deps

  # Run checks
  if $RUN_SHELLCHECK; then
    if ! run_shellcheck; then
      FAILED=1
    fi
  fi

  if $RUN_TESTS; then
    if ! run_tests; then
      FAILED=1
    fi
  fi

  # Summary
  echo ""
  echo "===================="
  if [[ $FAILED -eq 0 ]]; then
    success "All checks passed!"
    exit 0
  else
    error "Some checks failed"
    exit 1
  fi
}

main "$@"

