#!/usr/bin/env zsh

# Test runner for kk plugin
# Usage: ./run-tests.zsh

setopt local_options err_return

typeset -i TESTS_RUN=0
typeset -i TESTS_PASSED=0
typeset -i TESTS_FAILED=0

# Test helper functions
assert_equal() {
  local expected=$1
  local actual=$2
  local message=${3:-"Assertion failed"}

  TESTS_RUN+=1
  if [[ "$expected" == "$actual" ]]; then
    TESTS_PASSED+=1
    echo "✓ $message"
  else
    TESTS_FAILED+=1
    echo "✗ $message"
    echo "  Expected: $expected"
    echo "  Actual:   $actual"
  fi
}

assert_not_empty() {
  local value=$1
  local message=${2:-"Value should not be empty"}

  TESTS_RUN+=1
  if [[ -n "$value" ]]; then
    TESTS_PASSED+=1
    echo "✓ $message"
  else
    TESTS_FAILED+=1
    echo "✗ $message"
  fi
}

# Run all tests
echo "========================================"
echo "Running kk plugin tests..."
echo "========================================"
echo ""

source "${0:A:h}/test-options.zsh"
source "${0:A:h}/test-sort.zsh"
source "${0:A:h}/test-colors.zsh"
source "${0:A:h}/test-format.zsh"

echo ""
echo "========================================"
echo "Test Summary"
echo "========================================"
echo "Tests run: $TESTS_RUN"
echo "Passed: $TESTS_PASSED"
echo "Failed: $TESTS_FAILED"

if [[ $TESTS_FAILED -eq 0 ]]; then
  echo ""
  echo "✓ All tests passed!"
  exit 0
else
  echo ""
  echo "✗ Some tests failed"
  exit 1
fi
