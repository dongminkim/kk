# kk plugin Git integration

# Global associative array for VCS status
typeset -gA KK_VCS_STATUS

# Check if current directory is inside a Git repository
# Returns: 0 if inside repo, 1 otherwise
_kk_check_git_repo() {
  if [[ $(kk-git rev-parse --is-inside-work-tree 2>/dev/null) == true ]]; then
    return 0
  fi
  return 1
}

# Get Git status for files in the given directory
# Arguments: base_dir
# Sets global KK_VCS_STATUS associative array
_kk_get_git_status() {
  local base_dir=$1
  KK_VCS_STATUS=()

  if [[ "${KK_OPTS[no_vcs]}" != "" ]]; then
    return 0
  fi

  local old_dir="$PWD"
  if ! builtin cd -q "$base_dir" 2>/dev/null; then
    return 1
  fi

  local GIT_TOPLEVEL
  GIT_TOPLEVEL=$(kk-git -c core.quotepath=false rev-parse --show-toplevel 2>/dev/null)

  if [[ $? -ne 0 ]]; then
    builtin cd -q "$old_dir" >/dev/null
    return 1
  fi

  # Get tracked files
  kk-git ls-files -c --deduplicate | cut -d/ -f1 | sort -u | while IFS= read fn; do
    KK_VCS_STATUS["$fn"]="=="
  done

  # Get changed files
  local changed=0
  kk-git status --porcelain . 2>/dev/null | while IFS= read ln; do
    fn="${ln:3}"
    if [[ "$fn" == '"'*'"' ]]; then
      # Remove quotes(") from the file names containing special characters(', ", \, emoji, hangul)
      fn=${fn:1:-1}
    fi
    fn="$GIT_TOPLEVEL/${fn}"
    fn="${${${fn#$PWD/}:-.}%/}"
    st="${ln:0:2}"
    KK_VCS_STATUS["${fn}"]="$st"
    if [[ "$st" != "!!" && "$st" != "??" ]]; then
      if [[ "$fn" =~ .*/.* ]]; then
        # There is a change inside the directory "$fn"
        fn="${fn%%/*}"
        st="//"
      else
        if [[ "${st:0:1}" == "R" ]]; then
          fn="${fn#*-> }"
        fi
      fi
      KK_VCS_STATUS["${fn}"]="$st"
      changed=1
    fi
  done

  # Get ignored files
  setopt local_options null_glob
  local ignore_files=(.* *)
  if [[ ${#ignore_files} -gt 0 ]]; then
    kk-git check-ignore "${ignore_files[@]}" 2>/dev/null | while IFS= read fn; do
      KK_VCS_STATUS["${fn}"]="!!"
    done
  fi

  # Handle . and .. markers
  if [[ "${KK_OPTS[all]}" != "" && "${KK_OPTS[almost_all]}" == "" && "${KK_OPTS[no_directory]}" == "" ]]; then
    if [[ -z "${KK_VCS_STATUS["."]}" ]]; then
      if [[ $changed -eq 1 ]]; then
        KK_VCS_STATUS["."]="//"
        if [[ "$PWD" =~ ${GIT_TOPLEVEL}/.* ]]; then
          KK_VCS_STATUS[".."]="//"
        fi
      fi
    fi
  fi

  builtin cd -q "$old_dir" >/dev/null
  return 0
}

# vim: set ts=2 sw=2 ft=zsh et :
