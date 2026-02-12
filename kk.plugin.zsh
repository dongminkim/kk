zmodload zsh/datetime
zmodload -F zsh/stat b:zstat

alias kk-git="command git -c core.quotepath=false"

# =============================================================================
# Utility functions
# =============================================================================

_kk_debug() {
  (( KK_DEBUG > 0 )) && echo "🚥 $@" 1>&2
}

# BSD LSCOLORS letter to ANSI color code conversion (macOS compatibility)
_kk_bsd_to_ansi() {
  local foreground=$1 background=$2 fg_ansi bg_ansi
  case $foreground in
    a) fg_ansi=30;; b) fg_ansi=31;; c) fg_ansi=32;; d) fg_ansi=33;;
    e) fg_ansi=34;; f) fg_ansi=35;; g) fg_ansi=36;; h) fg_ansi=37;;
    x) fg_ansi=0;;
  esac
  case $background in
    a) bg_ansi=40;; b) bg_ansi=41;; c) bg_ansi=42;; d) bg_ansi=43;;
    e) bg_ansi=44;; f) bg_ansi=45;; g) bg_ansi=46;; h) bg_ansi=47;;
    x) bg_ansi=0;;
  esac
  printf "%s;%s" $bg_ansi $fg_ansi
}

# Backward-compatible aliases
debug() { _kk_debug "$@" }
_k_bsd_to_ansi() { _kk_bsd_to_ansi "$@" }

# =============================================================================
# Print usage/help text
# =============================================================================
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

# =============================================================================
# Initialize file-type color codes
# Uses macOS LSCOLORS when available, otherwise falls back to defaults
# Sets: K_COLOR_{DI,LN,SO,PI,EX,BD,CD,SU,SG,TW,OW,BR}
# =============================================================================
_kk_init_colors() {
  K_COLOR_DI="0;34"  # di: directory
  K_COLOR_LN="0;35"  # ln: symlink
  K_COLOR_SO="0;32"  # so: socket
  K_COLOR_PI="0;33"  # pi: pipe
  K_COLOR_EX="0;31"  # ex: executable
  K_COLOR_BD="34;46" # bd: block special
  K_COLOR_CD="34;43" # cd: character special
  K_COLOR_SU="30;41" # su: setuid executable
  K_COLOR_SG="30;46" # sg: setgid executable
  K_COLOR_TW="30;42" # tw: sticky + world-writable directory
  K_COLOR_OW="30;43" # ow: world-writable directory
  K_COLOR_BR="0;30"  # branch

  if [[ $(uname) == 'Darwin' && -n $LSCOLORS ]]; then
    K_COLOR_DI=$(_kk_bsd_to_ansi $LSCOLORS[1]  $LSCOLORS[2])
    K_COLOR_LN=$(_kk_bsd_to_ansi $LSCOLORS[3]  $LSCOLORS[4])
    K_COLOR_SO=$(_kk_bsd_to_ansi $LSCOLORS[5]  $LSCOLORS[6])
    K_COLOR_PI=$(_kk_bsd_to_ansi $LSCOLORS[7]  $LSCOLORS[8])
    K_COLOR_EX=$(_kk_bsd_to_ansi $LSCOLORS[9]  $LSCOLORS[10])
    K_COLOR_BD=$(_kk_bsd_to_ansi $LSCOLORS[11] $LSCOLORS[12])
    K_COLOR_CD=$(_kk_bsd_to_ansi $LSCOLORS[13] $LSCOLORS[14])
    K_COLOR_SU=$(_kk_bsd_to_ansi $LSCOLORS[15] $LSCOLORS[16])
    K_COLOR_SG=$(_kk_bsd_to_ansi $LSCOLORS[17] $LSCOLORS[18])
    K_COLOR_TW=$(_kk_bsd_to_ansi $LSCOLORS[19] $LSCOLORS[20])
    K_COLOR_OW=$(_kk_bsd_to_ansi $LSCOLORS[21] $LSCOLORS[22])
  fi
}

# =============================================================================
# Resolve sort order from parsed options into a zsh glob qualifier
# Reads: o_sort, o_sort_reverse, o_group_directories
# Sets: SORT_GLOB
# =============================================================================
_kk_resolve_sort() {
  local s_ord="o" r_ord="O" spec="n"  # default: by name

  case ${o_sort:#--sort} in
    -U|none)                          spec="N";;
    -t|time)                          spec="m";;
    -c|ctime|status)                  spec="c";;
    -u|atime|access|use)              spec="a";;
    -S|size) s_ord="O" r_ord="o"      spec="L";;
  esac

  if [[ -z "$o_sort_reverse" ]]; then
    SORT_GLOB="${s_ord}${spec}"
  else
    SORT_GLOB="${r_ord}${spec}"
  fi

  [[ -n "$o_group_directories" ]] && \
    SORT_GLOB="oe:[[ -d \$REPLY ]];REPLY=\$?:$SORT_GLOB"
}

# =============================================================================
# Initialize numfmt for human-readable file sizes
# Reads: o_human, o_si
# Sets: numfmt_cmd (may clear o_human if numfmt unavailable)
# =============================================================================
_kk_init_numfmt() {
  numfmt_cmd=""
  [[ -z "$o_human" ]] && return

  if (( $+commands[numfmt] )); then
    numfmt_cmd=numfmt
  elif (( $+commands[gnumfmt] )); then
    numfmt_cmd=gnumfmt
  else
    print -u2 "'numfmt' or 'gnumfmt' command not found, human readable output will not work."
    print -u2 "\tFalling back to normal file size output"
    o_human=""
  fi
}

_kk_numfmt() {
  if [[ -n "$o_si" ]]; then
    $numfmt_cmd --to=si "$@"
  else
    $numfmt_cmd --to=iec "$@"
  fi
}

# =============================================================================
# Build the list of files to display for a directory
# Reads: base_dir, base_show_list, o_all, o_almost_all, o_directory,
#        o_no_directory, SORT_GLOB
# Sets: show_list
# =============================================================================
_kk_build_file_list() {
  show_list=()

  # Explicit file arguments: pass through as-is
  if [[ "$base_dir" == "." && ${#base_show_list} -gt 0 ]]; then
    show_list=("${base_show_list[@]}")
    return
  fi

  # Non-existent path
  if [[ ! -e $base_dir ]]; then
    print -u2 "kk: cannot access $base_dir: No such file or directory"
    return
  fi

  # Single file
  if [[ -f $base_dir ]]; then
    show_list=($base_dir)
    return
  fi

  # Directory: include . and .. when -a (but not -A or -n)
  if [[ -n "$o_all" && -z "$o_almost_all" && -z "$o_no_directory" ]]; then
    show_list+=($base_dir/.)
    show_list+=($base_dir/..)
  fi

  # Gather directory contents with appropriate filters
  if [[ -n "$o_all" || -n "$o_almost_all" ]]; then
    if   [[ -n "$o_directory" ]];    then show_list+=($base_dir/*(D/$SORT_GLOB))
    elif [[ -n "$o_no_directory" ]]; then show_list+=($base_dir/*(D^/$SORT_GLOB))
    else                                  show_list+=($base_dir/*(D$SORT_GLOB))
    fi
  else
    if   [[ -n "$o_directory" ]];    then show_list+=($base_dir)
    elif [[ -n "$o_no_directory" ]]; then show_list+=($base_dir/*(^/$SORT_GLOB))
    else                                  show_list+=($base_dir/*($SORT_GLOB))
    fi
  fi
}

# =============================================================================
# Collect git VCS status for the current directory
# Reads: o_no_vcs, o_all, o_almost_all, o_no_directory, base_dir
# Sets: IS_GIT_REPO, GIT_TOPLEVEL, VCS_STATUS
# =============================================================================
_kk_collect_vcs_status() {
  IS_GIT_REPO=0
  GIT_TOPLEVEL=""
  VCS_STATUS=()

  [[ -n "$o_no_vcs" ]] && return

  local old_dir="$PWD"
  builtin cd -q "$base_dir" 2>/dev/null || return

  GIT_TOPLEVEL=$(kk-git rev-parse --show-toplevel 2>/dev/null)
  if [[ $? -ne 0 ]]; then
    builtin cd -q "$old_dir" >/dev/null
    return
  fi

  IS_GIT_REPO=1

  # Mark all tracked files as clean
  local fn
  kk-git ls-files -c --deduplicate | cut -d/ -f1 | sort -u | while IFS= read fn; do
    VCS_STATUS["$fn"]="=="
  done

  # Overlay porcelain status
  local changed=0 ln st
  kk-git status --porcelain . 2>/dev/null | while IFS= read ln; do
    fn="${ln:3}"
    # Strip quotes from filenames with special characters (', ", \, emoji, hangul)
    [[ "$fn" == '"'*'"' ]] && fn=${fn:1:-1}
    fn="$GIT_TOPLEVEL/${fn}"
    fn="${${${fn#$PWD/}:-.}%/}"
    st="${ln:0:2}"
    VCS_STATUS["${fn}"]="$st"

    if [[ "$st" != "!!" && "$st" != "??" ]]; then
      if [[ "$fn" =~ .*/.* ]]; then
        fn="${fn%%/*}"
        st="//"
      else
        [[ "${st:0:1}" == "R" ]] && fn="${fn#*-> }"
      fi
      VCS_STATUS["${fn}"]="$st"
      changed=1
    fi
  done

  # Mark ignored files
  kk-git check-ignore .* * 2>/dev/null | while IFS= read fn; do
    VCS_STATUS["${fn}"]="!!"
  done

  # Propagate directory-level change status for . and ..
  if [[ -n "$o_all" && -z "$o_almost_all" && -z "$o_no_directory" ]]; then
    if [[ -z "${VCS_STATUS["."]}" && $changed -eq 1 ]]; then
      VCS_STATUS["."]="//"
      [[ "$PWD" =~ ${GIT_TOPLEVEL}/.* ]] && VCS_STATUS[".."]="//"
    fi
  fi

  builtin cd -q "$old_dir" >/dev/null
}

# =============================================================================
# Format a VCS repo marker for a given filename
# Reads: IS_GIT_REPO, VCS_STATUS
# Args: $1 = display filename
# Sets: REPOMARKER
# =============================================================================
_kk_format_repomarker() {
  local name="$1"
  REPOMARKER=""
  (( IS_GIT_REPO == 0 )) && return

  local st="${VCS_STATUS["$name"]}"

  # Inherit parent directory's ignored/untracked status
  if [[ "$name" != ".." ]]; then
    if [[ "${VCS_STATUS["."]}" == "!!" || "${VCS_STATUS[".."]}" == "!!" ]]; then
      st="!!"
    elif [[ "${VCS_STATUS["."]}" == "??" ]]; then
      st="??"
    fi
  fi

  case "$st" in
    "")    REPOMARKER="  ";;                                  # outside repository
    "==")  REPOMARKER=$' \e[38;5;82m|\e[0m';;                 # tracked, not modified
    "//")  REPOMARKER=$' \e[38;5;226m+\e[0m';;                # changes inside directory
    "!!")  REPOMARKER=$' \e[38;5;238m|\e[0m';;                 # ignored
    "??")  REPOMARKER=$' \e[38;5;238m?\e[0m';;                 # untracked
    ?" ")  REPOMARKER=$' \e[38;5;82m+\e[0m';;                 # index matches work tree
    " "?)  REPOMARKER=$' \e[38;5;196m+\e[0m';;                # work tree changed
    *)     REPOMARKER=$' \e[38;5;214m+\e[0m';;                # both index and work tree changed
  esac
}

# =============================================================================
# Color a filename based on its file type
# Args: $1 = file path (for type detection), $2 = raw permission string
# Uses/Sets: COLORED_NAME (must be set before calling)
# Reads: K_COLOR_* variables
# =============================================================================
_kk_color_filename() {
  local path="$1" perms="$2" color=""

  if [[ -d "$path" ]]; then
    if [[ $perms[9] == 'w' ]]; then
      [[ -k "$path" ]] && COLORED_NAME=$'\e['"$K_COLOR_TW"'m'"$COLORED_NAME"$'\e[0m'
      COLORED_NAME=$'\e['"$K_COLOR_OW"'m'"$COLORED_NAME"$'\e[0m'
    fi
    color="$K_COLOR_DI"
  elif [[ -L "$path" ]]; then color="$K_COLOR_LN"
  elif [[ -S "$path" ]]; then color="$K_COLOR_SO"
  elif [[ -p "$path" ]]; then color="$K_COLOR_PI"
  elif [[ -u "$path" ]]; then color="$K_COLOR_SU"
  elif [[ -g "$path" ]]; then color="$K_COLOR_SG"
  elif [[ -x "$path" ]]; then color="$K_COLOR_EX"
  elif [[ -b "$path" ]]; then color="$K_COLOR_BD"
  elif [[ -c "$path" ]]; then color="$K_COLOR_CD"
  fi

  [[ -n "$color" ]] && COLORED_NAME=$'\e['"${color}"'m'"$COLORED_NAME"$'\e[0m'
}

# =============================================================================
# Format and print a single file entry line
# Args: $1 = stat variable name
# Reads (via dynamic scoping from kk):
#   sz, MAX_LEN, K_EPOCH, SIX_MONTHS,
#   SIZELIMITS_TO_COLOR, LARGE_FILE_COLOR,
#   FILEAGES_TO_COLOR, ANCIENT_TIME_COLOR,
#   IS_GIT_REPO, VCS_STATUS, K_COLOR_*
# =============================================================================
_kk_format_and_print_entry() {
  typeset -A sv=("${(@Pkv)1}")

  local name="${sv[name]}"
  local raw_perms="${sv[mode]}"
  local symlink_target="${sv[link]}"
  local -i filesize="${sv[size]}"
  local -a date_parts=(${(s:^:)sv[mtime]})

  # --- Pad columns to align output ---
  local perms="${(r:MAX_LEN[1]:)raw_perms}"
  local nlinks="${(l:MAX_LEN[2]:)sv[nlink]}"
  local owner="${(l:MAX_LEN[3]:)sv[uid]}"
  local group="${(l:MAX_LEN[4]:)sv[gid]}"
  local size_display="${(l:MAX_LEN[5]:)sz[${sv[name]}]}"

  # --- Permissions ---
  local perm_out="${perms[1]}${perms[2,4]}${perms[5,7]}${perms[8,10]}"

  # --- Color owner and group ---
  owner=$'\e[38;5;241m'"$owner"$'\e[0m'
  group=$'\e[38;5;241m'"$group"$'\e[0m'

  # --- Color file size by threshold ---
  local -i size_color=LARGE_FILE_COLOR i j
  for i j in ${SIZELIMITS_TO_COLOR[@]}; do
    (( filesize <= i )) || continue
    size_color=$j; break
  done
  size_display=$'\e[38;5;'"${size_color}m${size_display}"$'\e[0m'

  # --- Color date by age ---
  local -i time_diff=$(( K_EPOCH - date_parts[1] ))
  local -i time_color=ANCIENT_TIME_COLOR
  for i j in ${FILEAGES_TO_COLOR[@]}; do
    (( time_diff < i )) || continue
    time_color=$j; break
  done

  local date_output
  if (( time_diff < SIX_MONTHS )); then
    date_output="${date_parts[2]} ${(r:5:: :)${date_parts[3][0,5]}} ${date_parts[4]}"
  else
    date_output="${date_parts[2]} ${(r:6:: :)${date_parts[3][0,5]}} ${date_parts[5]}"
  fi
  date_output[1]="${date_output[1]//0/ }"
  date_output=$'\e[38;5;'"${time_color}m${date_output}"$'\e[0m'

  # --- Display name: strip path, escape ANSI ---
  local display_name="${${${name%/}##*/}//$'\e'/\\e}"

  # --- Git repo marker ---
  local REPOMARKER
  _kk_format_repomarker "$display_name"

  # --- Color filename by type ---
  local COLORED_NAME="$display_name"
  _kk_color_filename "$name" "$raw_perms"

  # --- Symlink target ---
  local sym_target=""
  [[ -n "$symlink_target" ]] && sym_target=" -> ${symlink_target//$'\e'/\\e}"

  # --- Output ---
  print -r -- "$perm_out $nlinks $owner $group $size_display $date_output$REPOMARKER $COLORED_NAME$sym_target"
}

# =============================================================================
# Main entry point
# =============================================================================
kk() {
  setopt local_options null_glob typeset_silent no_auto_pushd nomarkdirs

  # ---------------------------------------------------------------------------
  # Parse command-line options
  # ---------------------------------------------------------------------------
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
             S=o_sort t=o_sort u=o_sort U=o_sort \
             -help=o_help

  if [[ $? != 0 || -n "$o_help" ]]; then
    _kk_print_help
    return 1
  fi

  if [[ -n "$o_directory" && -n "$o_no_directory" ]]; then
    print -u2 "$o_directory and $o_no_directory cannot be used together"
    return 1
  fi

  # ---------------------------------------------------------------------------
  # Initialization
  # ---------------------------------------------------------------------------
  typeset SORT_GLOB numfmt_cmd
  _kk_resolve_sort
  _kk_init_numfmt
  _kk_init_colors

  # ---------------------------------------------------------------------------
  # Resolve target paths
  # ---------------------------------------------------------------------------
  typeset -a base_dirs base_show_list
  typeset base_dir

  if [[ $# -gt 0 ]]; then
    if [[ -z "$o_directory" ]]; then
      for (( i=1; i <= $#; i++ )); do
        local p="${@[$i]}"
        if [[ -d "$p" ]]; then
          base_dirs+=("$p")
        else
          [[ "${base_dirs[1]}" != "." ]] && base_dirs=(. "${base_dirs[@]}")
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

  # ---------------------------------------------------------------------------
  # Per-directory processing
  # ---------------------------------------------------------------------------
  typeset -a show_list STATS_PARAMS_LIST MAX_LEN
  typeset -A sz VCS_STATUS
  typeset -i TOTAL_BLOCKS IS_GIT_REPO
  typeset GIT_TOPLEVEL
  typeset K_EPOCH="${EPOCHSECONDS:?}"
  typeset -i SIX_MONTHS=15724800

  # Size thresholds: (max_bytes color_code) pairs
  typeset -i LARGE_FILE_COLOR=196
  typeset -a SIZELIMITS_TO_COLOR=(
      1024  46    # <= 1kb
      2048  82    # <= 2kb
      3072  118   # <= 3kb
      5120  154   # <= 5kb
     10240  190   # <= 10kb
     20480  226   # <= 20kb
     40960  220   # <= 40kb
    102400  214   # <= 100kb
    262144  208   # <= 256kb
    524288  202   # <= 512kb
    )

  # Age thresholds: (max_seconds color_code) pairs
  typeset -i ANCIENT_TIME_COLOR=236
  typeset -a FILEAGES_TO_COLOR=(
           0 196  # future
          60 255  # < 1 min
        3600 252  # < 1 hour
       86400 250  # < 1 day
      604800 244  # < 1 week
     2419200 244  # < 4 weeks
    15724800 242  # < 6 months
    31449600 240  # < 1 year
    62899200 238  # < 2 years
    )

  for base_dir in $base_dirs; do
    # Print directory header when processing multiple targets
    if (( $#base_dirs > 1 )); then
      [[ "$base_dir" != "${base_dirs[1]}" ]] && print
      [[ "$base_dir" == "." && ${#base_show_list} -gt 0 ]] || print -r "${base_dir}:"
    fi

    _kk_build_file_list

    # ----- Stat all files and calculate column widths -----
    typeset -i i=1 j=1
    typeset -a fs=()
    typeset fn statvar h
    typeset -A sv=()
    STATS_PARAMS_LIST=()
    MAX_LEN=(0 0 0 0 0 0)
    TOTAL_BLOCKS=0
    sz=()

    for fn in $show_list; do
      statvar="stats_$i"
      typeset -A $statvar
      zstat -H $statvar -Lsn -F "%s^%d^%b^%H:%M^%Y" -- "$fn"
      [[ $? -ne 0 ]] && continue
      STATS_PARAMS_LIST+=($statvar)
      if [[ -n "$o_human" ]]; then
        sv=("${(@Pkv)statvar}")
        fs+=("${sv[size]}")
      fi
      i+=1
    done

    if [[ -n "$o_human" ]]; then
      fs=($( printf "%s\n" "${fs[@]}" | _kk_numfmt ))
      i=1
    fi

    for statvar in "${STATS_PARAMS_LIST[@]}"; do
      sv=("${(@Pkv)statvar}")
      (( ${#sv[mode]}  > MAX_LEN[1] )) && MAX_LEN[1]=${#sv[mode]}
      (( ${#sv[nlink]} > MAX_LEN[2] )) && MAX_LEN[2]=${#sv[nlink]}
      (( ${#sv[uid]}   > MAX_LEN[3] )) && MAX_LEN[3]=${#sv[uid]}
      (( ${#sv[gid]}   > MAX_LEN[4] )) && MAX_LEN[4]=${#sv[gid]}

      if [[ -n "$o_human" ]]; then
        h="${fs[$(( i++ ))]}"
      else
        h="${sv[size]}"
      fi
      sz[${sv[name]}]="$h"
      (( ${#h} > MAX_LEN[5] )) && MAX_LEN[5]=${#h}

      TOTAL_BLOCKS+=$sv[blocks]
    done

    [[ "$base_dir" == "." && ${#base_show_list} -gt 0 ]] || echo "total $TOTAL_BLOCKS"

    _kk_collect_vcs_status

    # ----- Format and print each entry -----
    for statvar in "${STATS_PARAMS_LIST[@]}"; do
      _kk_format_and_print_entry "$statvar"
    done
  done
}

# http://upload.wikimedia.org/wikipedia/en/1/15/Xterm_256color_chart.svg
# vim: set ts=2 sw=2 ft=zsh et :
