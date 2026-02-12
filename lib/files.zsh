# kk plugin file collection logic

# Global arrays for directory/file lists
typeset -ga base_dirs base_show_list

# Build base directory list from command-line arguments
# Sets global base_dirs and base_show_list arrays
_kk_build_base_dirs() {
  base_dirs=()
  base_show_list=()

  if [[ $# -gt 0 ]]; then
    if [[ "${KK_OPTS[directory]}" == "" ]]; then
      for (( i=1; i <= $#; i++ )); do
        local p="${@[$i]}"
        if [[ -d "$p" ]]; then
          base_dirs+=("$p")
        else
          if [ "${base_dirs[1]}" != "." ]; then
            base_dirs=(. "${base_dirs[@]}")
          fi
          base_show_list+=("$p")
        fi
      done
    else
      base_dirs=(.)
      base_show_list=("$@")
    fi
  else
    base_dirs=(.)
  fi
}

# Build file list for a given directory using glob patterns
# Arguments: base_dir, sort_glob
# Returns: space-separated list of files (via echo)
_kk_build_file_list() {
  local base_dir=$1
  local sort_glob=$2
  typeset -a show_list

  # Check if it even exists
  if [[ ! -e $base_dir ]]; then
    print -u2 "kk: cannot access $base_dir: No such file or directory"
    return 1
  fi

  # If its just a file, return it as-is
  if [[ -f $base_dir ]]; then
    echo "$base_dir"
    return 0
  fi

  # Directory, add its contents
  show_list=()

  # Add . and .. if requested
  if [[ "${KK_OPTS[all]}" != "" && "${KK_OPTS[almost_all]}" == "" && "${KK_OPTS[no_directory]}" == "" ]]; then
    show_list+=($base_dir/.)
    show_list+=($base_dir/..)
  fi

  # Build glob pattern with appropriate filters
  if [[ "${KK_OPTS[all]}" != "" || "${KK_OPTS[almost_all]}" != "" ]]; then
    if [[ "${KK_OPTS[directory]}" != "" ]]; then
      show_list+=($base_dir/*(D/$sort_glob))
    elif [[ "${KK_OPTS[no_directory]}" != "" ]]; then
      # Use (^/) instead of (.) so sockets and symlinks get displayed
      show_list+=($base_dir/*(D^/$sort_glob))
    else
      show_list+=($base_dir/*(D$sort_glob))
    fi
  else
    if [[ "${KK_OPTS[directory]}" != "" ]]; then
      show_list+=($base_dir)
    elif [[ "${KK_OPTS[no_directory]}" != "" ]]; then
      # Use (^/) instead of (.) so sockets and symlinks get displayed
      show_list+=($base_dir/*(^/$sort_glob))
    else
      show_list+=($base_dir/*($sort_glob))
    fi
  fi

  echo "${show_list[@]}"
  return 0
}

# vim: set ts=2 sw=2 ft=zsh et :
