# Test option parsing

echo "Testing options..."

# Load dependencies
source "${0:A:h}/../lib/utils.zsh"
source "${0:A:h}/../lib/options.zsh"

# Test: help option
typeset -gA KK_OPTS=()
_kk_parse_options --help
assert_not_empty "${KK_OPTS[help]}" "Should parse --help option"

# Test: human readable option
typeset -gA KK_OPTS=()
_kk_parse_options -h
assert_not_empty "${KK_OPTS[human]}" "Should parse -h option"

# Test: all option
typeset -gA KK_OPTS=()
_kk_parse_options -a
assert_not_empty "${KK_OPTS[all]}" "Should parse -a option"

# Test: option conflict detection
typeset -gA KK_OPTS=()
KK_OPTS[directory]="-d"
KK_OPTS[no_directory]="-n"
if ! _kk_validate_options 2>/dev/null; then
  TESTS_PASSED+=1
  echo "✓ Should detect conflicting directory options"
else
  TESTS_FAILED+=1
  echo "✗ Should detect conflicting directory options"
fi
TESTS_RUN+=1

echo ""
