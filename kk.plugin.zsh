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
# Reads: K_COLOR_* variables
# Args: $1=name $2=is_dir $3=is_sym $4=is_sock $5=is_pipe $6=is_exec
#       $7=is_block $8=is_char $9=has_uid $10=has_gid $11=has_sticky $12=is_world_w
# Sets: COLORED_NAME
# =============================================================================
_kk_color_filename() {
  COLORED_NAME="$1"
  local -i is_dir=$2 is_sym=$3 is_sock=$4 is_pipe=$5 is_exec=$6
  local -i is_block=$7 is_char=$8 has_uid=$9 has_gid=${10} has_sticky=${11} is_world_w=${12}

  if (( is_dir )); then
    (( is_world_w && has_sticky )) && COLORED_NAME=$'\e['"$K_COLOR_TW"'m'"$COLORED_NAME"$'\e[0m'
    (( is_world_w ))               && COLORED_NAME=$'\e['"$K_COLOR_OW"'m'"$COLORED_NAME"$'\e[0m'
    COLORED_NAME=$'\e['"$K_COLOR_DI"'m'"$COLORED_NAME"$'\e[0m'
  elif (( is_sym ));   then COLORED_NAME=$'\e['"$K_COLOR_LN"'m'"$COLORED_NAME"$'\e[0m'
  elif (( is_sock ));  then COLORED_NAME=$'\e['"$K_COLOR_SO"'m'"$COLORED_NAME"$'\e[0m'
  elif (( is_pipe ));  then COLORED_NAME=$'\e['"$K_COLOR_PI"'m'"$COLORED_NAME"$'\e[0m'
  elif (( has_uid ));  then COLORED_NAME=$'\e['"$K_COLOR_SU"'m'"$COLORED_NAME"$'\e[0m'
  elif (( has_gid ));  then COLORED_NAME=$'\e['"$K_COLOR_SG"'m'"$COLORED_NAME"$'\e[0m'
  elif (( is_exec ));  then COLORED_NAME=$'\e['"$K_COLOR_EX"'m'"$COLORED_NAME"$'\e[0m'
  elif (( is_block )); then COLORED_NAME=$'\e['"$K_COLOR_BD"'m'"$COLORED_NAME"$'\e[0m'
  elif (( is_char ));  then COLORED_NAME=$'\e['"$K_COLOR_CD"'m'"$COLORED_NAME"$'\e[0m'
  fi
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

    # ----- Build file list -----
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

    # Print total block count
    [[ "$base_dir" == "." && ${#base_show_list} -gt 0 ]] || echo "total $TOTAL_BLOCKS"

    # ----- Collect VCS status -----
    _kk_collect_vcs_status

    # ----- Format and print each entry -----
    typeset REPOMARKER COLORED_NAME
    typeset PERMISSIONS HARDLINKCOUNT OWNER GROUP FILESIZE_OUT
    typeset -a DATE
    typeset NAME SYMLINK_TARGET
    typeset -i IS_DIRECTORY IS_SYMLINK IS_SOCKET IS_PIPE IS_EXECUTABLE
    typeset -i IS_BLOCK_SPECIAL IS_CHARACTER_SPECIAL
    typeset -i HAS_UID_BIT HAS_GID_BIT HAS_STICKY_BIT IS_WRITABLE_BY_OTHERS
    typeset -i FILESIZE COLOR TIME_DIFF TIME_COLOR
    typeset DATE_OUTPUT STATUS

    for statvar in "${STATS_PARAMS_LIST[@]}"; do
      sv=("${(@Pkv)statvar}")

         PERMISSIONS="${sv[mode]}"
       HARDLINKCOUNT="${sv[nlink]}"
               OWNER="${sv[uid]}"
               GROUP="${sv[gid]}"
            FILESIZE="${sv[size]}"
        FILESIZE_OUT="${sz[${sv[name]}]}"
                DATE=(${(s:^:)sv[mtime]})
                NAME="${sv[name]}"
      SYMLINK_TARGET="${sv[link]}"

      # Detect file types
      IS_DIRECTORY=0  IS_SYMLINK=0  IS_SOCKET=0  IS_PIPE=0
      IS_EXECUTABLE=0  IS_BLOCK_SPECIAL=0  IS_CHARACTER_SPECIAL=0
      HAS_UID_BIT=0  HAS_GID_BIT=0  HAS_STICKY_BIT=0  IS_WRITABLE_BY_OTHERS=0

      [[ -d "$NAME" ]] && IS_DIRECTORY=1
      [[ -L "$NAME" ]] && IS_SYMLINK=1
      [[ -S "$NAME" ]] && IS_SOCKET=1
      [[ -p "$NAME" ]] && IS_PIPE=1
      [[ -x "$NAME" ]] && IS_EXECUTABLE=1
      [[ -b "$NAME" ]] && IS_BLOCK_SPECIAL=1
      [[ -c "$NAME" ]] && IS_CHARACTER_SPECIAL=1
      [[ -u "$NAME" ]] && HAS_UID_BIT=1
      [[ -g "$NAME" ]] && HAS_GID_BIT=1
      [[ -k "$NAME" ]] && HAS_STICKY_BIT=1
      [[ $PERMISSIONS[9] == 'w' ]] && IS_WRITABLE_BY_OTHERS=1

      # Pad columns
        PERMISSIONS="${(r:MAX_LEN[1]:)PERMISSIONS}"
      HARDLINKCOUNT="${(l:MAX_LEN[2]:)HARDLINKCOUNT}"
              OWNER="${(l:MAX_LEN[3]:)OWNER}"
              GROUP="${(l:MAX_LEN[4]:)GROUP}"
       FILESIZE_OUT="${(l:MAX_LEN[5]:)FILESIZE_OUT}"

      # Permissions output
      typeset PERMISSIONS_OUTPUT="${PERMISSIONS[1]}${PERMISSIONS[2,4]}${PERMISSIONS[5,7]}${PERMISSIONS[8,10]}"

      # Color owner and group
      OWNER=$'\e[38;5;241m'"$OWNER"$'\e[0m'
      GROUP=$'\e[38;5;241m'"$GROUP"$'\e[0m'

      # Color file size
      COLOR=LARGE_FILE_COLOR
      for i j in ${SIZELIMITS_TO_COLOR[@]}; do
        (( FILESIZE <= i )) || continue
        COLOR=$j
        break
      done
      FILESIZE_OUT=$'\e[38;5;'"${COLOR}m$FILESIZE_OUT"$'\e[0m'

      # Color date based on age
      TIME_DIFF=$(( K_EPOCH - DATE[1] ))
      TIME_COLOR=$ANCIENT_TIME_COLOR
      for i j in ${FILEAGES_TO_COLOR[@]}; do
        (( TIME_DIFF < i )) || continue
        TIME_COLOR=$j
        break
      done

      if (( TIME_DIFF < 15724800 )); then
        DATE_OUTPUT="${DATE[2]} ${(r:5:: :)${DATE[3][0,5]}} ${DATE[4]}"
      else
        DATE_OUTPUT="${DATE[2]} ${(r:6:: :)${DATE[3][0,5]}} ${DATE[5]}"
      fi
      DATE_OUTPUT[1]="${DATE_OUTPUT[1]//0/ }"
      DATE_OUTPUT=$'\e[38;5;'"${TIME_COLOR}m${DATE_OUTPUT}"$'\e[0m'

      # Prepare display name (strip path, escape ANSI)
      NAME="${${${NAME%/}##*/}//$'\e'/\\e}"

      # Git repo marker
      _kk_format_repomarker "$NAME"

      # Color filename
      _kk_color_filename "$NAME" \
        $IS_DIRECTORY $IS_SYMLINK $IS_SOCKET $IS_PIPE $IS_EXECUTABLE \
        $IS_BLOCK_SPECIAL $IS_CHARACTER_SPECIAL \
        $HAS_UID_BIT $HAS_GID_BIT $HAS_STICKY_BIT $IS_WRITABLE_BY_OTHERS

      # Format symlink target
      if [[ -n "$SYMLINK_TARGET" ]]; then SYMLINK_TARGET=" -> ${SYMLINK_TARGET//$'\e'/\\e}"; fi

      # Output
      print -r -- "$PERMISSIONS_OUTPUT $HARDLINKCOUNT $OWNER $GROUP $FILESIZE_OUT $DATE_OUTPUT$REPOMARKER $COLORED_NAME$SYMLINK_TARGET"
    done
  done
}

# http://upload.wikimedia.org/wikipedia/en/1/15/Xterm_256color_chart.svg
# vim: set ts=2 sw=2 ft=zsh et :
