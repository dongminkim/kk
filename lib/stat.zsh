# kk plugin stat processing

# Global variables for stat results
typeset -ga STATS_PARAMS_LIST MAX_LEN
typeset -gA sz
typeset -gi TOTAL_BLOCKS
typeset -g numfmt_cmd

# Check for numfmt command availability and setup
_kk_setup_numfmt() {
  numfmt_cmd=""

  if [[ "${KK_OPTS[human]}" == "" ]]; then
    return 0
  fi

  if [[ $+commands[numfmt] == 1 ]]; then
    numfmt_cmd=numfmt
  elif [[ $+commands[gnumfmt] == 1 ]]; then
    numfmt_cmd=gnumfmt
  else
    print -u2 "'numfmt' or 'gnumfmt' command not found, human readable output will not work."
    print -u2 "\tFalling back to normal file size output"
    # Set o_human to off
    KK_OPTS[human]=""
    return 1
  fi

  # Define local function for numfmt
  numfmt_local() {
    if [[ "${KK_OPTS[si]}" != "" ]]; then
      $numfmt_cmd --to=si "$@"
    else
      $numfmt_cmd --to=iec "$@"
    fi
  }

  return 0
}

# Process file stats using zstat
# Arguments: list of files
# Sets global variables: STATS_PARAMS_LIST, MAX_LEN, sz, TOTAL_BLOCKS
_kk_process_stats() {
  local -a show_list=("$@")

  typeset -i i=1 j=1
  typeset fn statvar h
  typeset -A sv
  typeset -a fs

  MAX_LEN=(0 0 0 0 0 0)
  TOTAL_BLOCKS=0
  STATS_PARAMS_LIST=()
  sz=()

  # Collect stats
  for fn in $show_list; do
    statvar="stats_$i"
    typeset -gA $statvar
    zstat -H $statvar -Lsn -F "%s^%d^%b^%H:%M^%Y" -- "$fn"  # use lstat, render mode/uid/gid to strings
    if [[ $? -ne 0 ]]; then continue; fi
    STATS_PARAMS_LIST+=($statvar)
    if [[ "${KK_OPTS[human]}" != "" ]]; then
      sv=("${(@Pkv)statvar}")
      fs+=("${sv[size]}")
    fi
    i+=1
  done

  # Format human-readable sizes
  if [[ "${KK_OPTS[human]}" != "" ]]; then
    fs=($( printf "%s\n" "${fs[@]}" | numfmt_local ))
    i=1
  fi

  # Calculate padding (MAX_LEN) and store sizes
  for statvar in "${STATS_PARAMS_LIST[@]}"; do
    sv=("${(@Pkv)statvar}")
    if [[ ${#sv[mode]}  -gt $MAX_LEN[1] ]]; then MAX_LEN[1]=${#sv[mode]}  ; fi
    if [[ ${#sv[nlink]} -gt $MAX_LEN[2] ]]; then MAX_LEN[2]=${#sv[nlink]} ; fi
    if [[ ${#sv[uid]}   -gt $MAX_LEN[3] ]]; then MAX_LEN[3]=${#sv[uid]}   ; fi
    if [[ ${#sv[gid]}   -gt $MAX_LEN[4] ]]; then MAX_LEN[4]=${#sv[gid]}   ; fi

    if [[ "${KK_OPTS[human]}" != "" ]]; then
      h="${fs[$(( i++ ))]}"
    else
      h="${sv[size]}"
    fi
    sz[${sv[name]}]="$h"
    if (( ${#h} > $MAX_LEN[5] )); then MAX_LEN[5]=${#h}; fi

    TOTAL_BLOCKS+=$sv[blocks]
  done
}

# vim: set ts=2 sw=2 ft=zsh et :
