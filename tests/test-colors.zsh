# Test color initialization

echo "Testing colors..."

source "${0:A:h}/../lib/utils.zsh"
source "${0:A:h}/../lib/colors.zsh"

# Test: color initialization
_kk_init_colors
assert_not_empty "${KK_COLORS[di]}" "Directory color should be set"
assert_not_empty "${KK_COLORS[ln]}" "Symlink color should be set"
assert_not_empty "${KK_COLORS[ex]}" "Executable color should be set"

# Test: size color initialization
_kk_init_size_colors
assert_not_empty "$KK_SIZELIMITS_TO_COLOR" "Size colors should be initialized"
assert_equal "196" "$KK_LARGE_FILE_COLOR" "Large file color should be 196"

# Test: age color initialization
_kk_init_age_colors
assert_not_empty "$KK_FILEAGES_TO_COLOR" "Age colors should be initialized"
assert_equal "236" "$KK_ANCIENT_TIME_COLOR" "Ancient time color should be 236"

echo ""
