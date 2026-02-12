# Test sort configuration

echo "Testing sort..."

source "${0:A:h}/../lib/utils.zsh"
source "${0:A:h}/../lib/options.zsh"
source "${0:A:h}/../lib/sort.zsh"

# Test: default sort (by name)
typeset -gA KK_OPTS=()
result=$(_kk_build_sort_glob)
assert_equal "on" "$result" "Default sort should be by name"

# Test: sort by time
typeset -gA KK_OPTS=()
KK_OPTS[sort]="-t"
result=$(_kk_build_sort_glob)
assert_equal "om" "$result" "Should sort by modification time"

# Test: sort by size (reverse default)
typeset -gA KK_OPTS=()
KK_OPTS[sort]="-S"
result=$(_kk_build_sort_glob)
assert_equal "OL" "$result" "Should sort by size (reverse)"

# Test: sort by ctime
typeset -gA KK_OPTS=()
KK_OPTS[sort]="-c"
result=$(_kk_build_sort_glob)
assert_equal "oc" "$result" "Should sort by ctime"

# Test: reverse sort
typeset -gA KK_OPTS=()
KK_OPTS[sort_reverse]="-r"
result=$(_kk_build_sort_glob)
assert_equal "On" "$result" "Should reverse sort order"

echo ""
