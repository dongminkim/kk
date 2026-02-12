# Test formatting functions

echo "Testing format..."

source "${0:A:h}/../lib/utils.zsh"
source "${0:A:h}/../lib/colors.zsh"
source "${0:A:h}/../lib/format.zsh"

# Initialize colors
_kk_init_colors
_kk_init_size_colors
_kk_init_age_colors

# Test: file color for directory
result=$(_kk_get_file_color 1 0 0 0 0 0 0 0 0 0 0)
assert_not_empty "$result" "Should return directory color"

# Test: file color for symlink
result=$(_kk_get_file_color 0 1 0 0 0 0 0 0 0 0 0)
assert_equal "${KK_COLORS[ln]}" "$result" "Should return symlink color"

# Test: size color for small file
result=$(_kk_get_size_color 500)
assert_equal "46" "$result" "Should return color for small file (<=1KB)"

# Test: size color for large file
result=$(_kk_get_size_color 1000000)
assert_equal "196" "$result" "Should return color for large file"

# Test: age color setup
typeset -g K_EPOCH=1000000
result=$(_kk_get_age_color 999940)
assert_not_empty "$result" "Should return age color"

echo ""
