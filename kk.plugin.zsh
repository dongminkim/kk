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

  # Parse command-line options
  # Note: zparseopts -D modifies $@ to remove parsed options, leaving only non-option args
  typeset -a o_all o_almost_all o_human o_si o_directory o_group_directories \
          o_no_directory o_no_vcs o_sort o_sort_reverse o_help

  zparseopts -E -D \
             a=o_all -all=o_all \
             A=o_almost_all -almost-all=o_almost_all \
             c=o_sort \
             d=o_directory -directory=o_directory \
             -group-directories-first=o_group_directories \
             h=o_human -human=o_human \
             -si=o_si \
             n=o_no_directory -no-directory=o_no_directory \
             -no-vcs=o_no_vcs \
             r=o_sort_reverse -reverse=o_sort_reverse \
             -sort:=o_sort \
             S=o_sort \
             t=o_sort \
             u=o_sort \
             U=o_sort \
             -help=o_help

  if [[ $? != 0 || "$o_help" != "" ]]; then
    _kk_print_help
    return 1
  fi

  # Store parsed options in global associative array
  KK_OPTS[all]="$o_all"
  KK_OPTS[almost_all]="$o_almost_all"
  KK_OPTS[human]="$o_human"
  KK_OPTS[si]="$o_si"
  KK_OPTS[directory]="$o_directory"
  KK_OPTS[group_directories]="$o_group_directories"
  KK_OPTS[no_directory]="$o_no_directory"
  KK_OPTS[no_vcs]="$o_no_vcs"
  KK_OPTS[sort]="$o_sort"
  KK_OPTS[sort_reverse]="$o_sort_reverse"
  KK_OPTS[help]="$o_help"

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
  # Now $@ contains only the remaining arguments after option parsing
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
