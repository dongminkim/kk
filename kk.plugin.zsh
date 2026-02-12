# kk - Enhanced directory listing with Git integration
# Modular architecture for better maintainability

zmodload zsh/datetime
zmodload -F zsh/stat b:zstat

alias kk-git="command git -c core.quotepath=false"

# ----------------------------------------------------------------------------
# Load library modules
# ----------------------------------------------------------------------------
0="${${ZERO:-${0:#$ZSH_ARGZERO}}:-${(%):-%N}}"
0="${${(M)0:#/*}:-$PWD/$0}"
typeset -g KK_LIB_DIR="${0:A:h}/lib"

source "$KK_LIB_DIR/utils.zsh"
source "$KK_LIB_DIR/options.zsh"
source "$KK_LIB_DIR/sort.zsh"
source "$KK_LIB_DIR/colors.zsh"
source "$KK_LIB_DIR/files.zsh"
source "$KK_LIB_DIR/stat.zsh"
source "$KK_LIB_DIR/git.zsh"
source "$KK_LIB_DIR/format.zsh"

# ----------------------------------------------------------------------------
# Main kk function - orchestrates all modules
# ----------------------------------------------------------------------------
kk() {
  # Initialize local options
  _kk_init_locals

  # Parse and validate options
  _kk_parse_options "$@" || return 1

  # Print help if requested
  if [[ "${KK_OPTS[help]}" != "" ]]; then
    _kk_print_help
    return 0
  fi

  # Validate option combinations
  _kk_validate_options || return 1

  # Initialize color systems
  _kk_init_colors
  _kk_init_size_colors
  _kk_init_age_colors

  # Setup numfmt if needed
  _kk_setup_numfmt

  # Build sort glob qualifier
  local SORT_GLOB=$(_kk_build_sort_glob)

  # Check if we're in a Git repository
  typeset -gi INSIDE_WORK_TREE=0
  if _kk_check_git_repo; then
    INSIDE_WORK_TREE=1
  fi

  # Build list of base directories to process
  _kk_build_base_dirs "$@"

  # Get current epoch time for age calculations
  typeset -g K_EPOCH="${EPOCHSECONDS:?}"

  # ----------------------------------------------------------------------------
  # Process each directory
  # ----------------------------------------------------------------------------
  for base_dir in $base_dirs; do
    # Print header for multiple directories
    if [[ "$#base_dirs" -gt 1 ]]; then
      # Only add a newline if its not the first iteration
      if [[ "$base_dir" != "${base_dirs[1]}" ]]; then
        print
      fi

      if ! [[ "$base_dir" == "." && ${#base_show_list} -gt 0 ]]; then
        print -r "${base_dir}:"
      fi
    fi

    # Build file list for this directory
    local show_list
    if [[ "$base_dir" == "." && ${#base_show_list} -gt 0 ]]; then
      show_list=("${base_show_list[@]}")
    else
      show_list=($(_kk_build_file_list "$base_dir" "$SORT_GLOB"))
    fi

    # Process file stats
    _kk_process_stats "${show_list[@]}"

    # Print total blocks
    if ! [[ "$base_dir" == "." && ${#base_show_list} -gt 0 ]]; then
      echo "total $TOTAL_BLOCKS"
    fi

    # Get Git status if in a repository
    if [[ "$INSIDE_WORK_TREE" == 1 ]]; then
      _kk_get_git_status "$base_dir"
    fi

    # Format and print each file
    for statvar in "${STATS_PARAMS_LIST[@]}"; do
      _kk_format_line "$statvar"
    done
  done
}

# vim: set ts=2 sw=2 ft=zsh et :
