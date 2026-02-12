# kk plugin option parsing and validation

# Global associative array to store parsed options
typeset -gA KK_OPTS

# Parse command-line options using zparseopts
# Sets KK_OPTS associative array with parsed values
_kk_parse_options() {
  # Process options and get files/directories
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

  return $?
}

# Print help text to stderr
_kk_print_help() {
  print -u2 "Usage: kk [options] DIR"
  print -u2 "Options:"
  print -u2 "\t-a      --all           list entries starting with ."
  print -u2 "\t-A      --almost-all    list all except . and .."
  print -u2 "\t-c                      sort by ctime (inode change time)"
  print -u2 "\t-d      --directory     list only directories"
  print -u2 "\t-n      --no-directory  do not list directories"
  print -u2 "\t-h      --human         show filesizes in human-readable format"
  print -u2 "\t        --si            with -h, use powers of 1000 not 1024"
  print -u2 "\t-r      --reverse       reverse sort order"
  print -u2 "\t-S                      sort by size"
  print -u2 "\t-t                      sort by time (modification time)"
  print -u2 "\t-u                      sort by atime (use or access time)"
  print -u2 "\t-U                      Unsorted"
  print -u2 "\t        --sort WORD     sort by WORD: none (U), size (S),"
  print -u2 "\t                        time (t), ctime or status (c),"
  print -u2 "\t                        atime or access or use (u)"
  print -u2 "\t        --no-vcs        do not get VCS status (much faster)"
  print -u2 "\t        --help          show this help"
}

# Validate option combinations
# Returns 1 if there are conflicts, 0 otherwise
_kk_validate_options() {
  # Check for conflicts
  if [[ "${KK_OPTS[directory]}" != "" && "${KK_OPTS[no_directory]}" != "" ]]; then
    print -u2 "kk: --directory and --no-directory cannot be used together"
    return 1
  fi

  return 0
}

# vim: set ts=2 sw=2 ft=zsh et :
