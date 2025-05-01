zmodload zsh/datetime
zmodload -F zsh/stat b:zstat

alias kk-git="command git -c core.quotepath=false"

debug () {
  if [[ $KK_DEBUG -gt 0 ]]; then
    echo "🚥 $@" 1>&2
  fi
}

kk () {
  # ----------------------------------------------------------------------------
  # Setup
  # ----------------------------------------------------------------------------

  # Stop stat failing when a directory contains either no files or no hidden files
  # Track if we _accidentally_ create a new global variable
  setopt local_options null_glob typeset_silent no_auto_pushd nomarkdirs

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

  # Print Help if bad usage, or they asked for it
  if [[ $? != 0 || "$o_help" != "" ]]
  then
    print -u2 "Usage: $0 [options] DIR"
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
    return 1
  fi

  # Check for conflicts
  if [[ "$o_directory" != "" && "$o_no_directory" != "" ]]; then
    print -u2 "$o_directory and $o_no_directory cannot be used together"
    return 1
  fi

  # case is like a mnemonic for sort order:
  # lower-case for standard, upper-case for descending
  local S_ORD="o" R_ORD="O" SPEC="n"  # default: by name

  # translate ls options to glob-qualifiers,
  # ignoring "--sort" prefix of long-args form
  case ${o_sort:#--sort} in
    -U|none)                     SPEC="N";;
    -t|time)                     SPEC="m";;
    -c|ctime|status)             SPEC="c";;
    -u|atime|access|use)         SPEC="a";;
    # reverse default order for sort by size
    -S|size) S_ORD="O" R_ORD="o" SPEC="L";;
  esac

  if [[ "$o_sort_reverse" == "" ]]; then
    typeset SORT_GLOB="${S_ORD}${SPEC}"
  else
    typeset SORT_GLOB="${R_ORD}${SPEC}"
  fi
  if [[ "$o_group_directories" != "" ]]; then
    SORT_GLOB="oe:[[ -d \$REPLY ]];REPLY=\$?:$SORT_GLOB"
  fi

  # Check which numfmt available (if any), warn user if not available
  typeset numfmt_cmd
  if [[ "$o_human" != "" ]]; then
    if [[ $+commands[numfmt] == 1 ]]; then
      numfmt_cmd=numfmt
    elif [[ $+commands[gnumfmt] == 1 ]]; then
      numfmt_cmd=gnumfmt
    else
      print -u2 "'numfmt' or 'gnumfmt' command not found, human readable output will not work."
      print -u2 "\tFalling back to normal file size output"
      # Set o_human to off
      o_human=""
    fi
  fi

  # Create numfmt local function
  numfmt_local () {
    if [[ "$o_si" != "" ]]; then
      $numfmt_cmd --to=si "$@"
    else
      $numfmt_cmd --to=iec "$@"
    fi
  }

  # Set if we're in a repo or not
  typeset -i INSIDE_WORK_TREE=0
  if [[ $(kk-git rev-parse --is-inside-work-tree 2>/dev/null) == true ]]; then
    INSIDE_WORK_TREE=1
  fi

  # Setup array of directories to print
  typeset -a base_dirs
  typeset base_dir
  typeset -A white_list
  typeset -a base_show_list

  if [[ $# -gt 0 ]]; then
    if [[ "$o_directory" == "" ]]; then
      for (( i=1; i <= $#; i++ )); do
        p="${@[$i]}"
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

  # Colors
  # ----------------------------------------------------------------------------
  # default colors
  K_COLOR_DI="0;34"  # di:directory
  K_COLOR_LN="0;35"  # ln:symlink
  K_COLOR_SO="0;32"  # so:socket
  K_COLOR_PI="0;33"  # pi:pipe
  K_COLOR_EX="0;31"  # ex:executable
  K_COLOR_BD="34;46" # bd:block special
  K_COLOR_CD="34;43" # cd:character special
  K_COLOR_SU="30;41" # su:executable with setuid bit set
  K_COLOR_SG="30;46" # sg:executable with setgid bit set
  K_COLOR_TW="30;42" # tw:directory writable to others, with sticky bit
  K_COLOR_OW="30;43" # ow:directory writable to others, without sticky bit
  K_COLOR_BR="0;30"  # branch

  # read colors if osx and $LSCOLORS is defined
  if [[ $(uname) == 'Darwin' && -n $LSCOLORS ]]; then
    # Translate OSX/BSD's LSCOLORS so we can use the same here
    K_COLOR_DI=$(_k_bsd_to_ansi $LSCOLORS[1]  $LSCOLORS[2])
    K_COLOR_LN=$(_k_bsd_to_ansi $LSCOLORS[3]  $LSCOLORS[4])
    K_COLOR_SO=$(_k_bsd_to_ansi $LSCOLORS[5]  $LSCOLORS[6])
    K_COLOR_PI=$(_k_bsd_to_ansi $LSCOLORS[7]  $LSCOLORS[8])
    K_COLOR_EX=$(_k_bsd_to_ansi $LSCOLORS[9]  $LSCOLORS[10])
    K_COLOR_BD=$(_k_bsd_to_ansi $LSCOLORS[11] $LSCOLORS[12])
    K_COLOR_CD=$(_k_bsd_to_ansi $LSCOLORS[13] $LSCOLORS[14])
    K_COLOR_SU=$(_k_bsd_to_ansi $LSCOLORS[15] $LSCOLORS[16])
    K_COLOR_SG=$(_k_bsd_to_ansi $LSCOLORS[17] $LSCOLORS[18])
    K_COLOR_TW=$(_k_bsd_to_ansi $LSCOLORS[19] $LSCOLORS[20])
    K_COLOR_OW=$(_k_bsd_to_ansi $LSCOLORS[21] $LSCOLORS[22])
  fi

  # read colors if linux and $LS_COLORS is defined
  # if [[ $(uname) == 'Linux' && -n $LS_COLORS ]]; then

  # fi

  # ----------------------------------------------------------------------------
  # Loop over passed directories and files to display
  # ----------------------------------------------------------------------------
  for base_dir in $base_dirs
  do
    # ----------------------------------------------------------------------------
    # Display name if multiple paths were passed
    # ----------------------------------------------------------------------------
    if [[ "$#base_dirs" > 1 ]]; then
      # Only add a newline if its not the first iteration
      if [[ "$base_dir" != "${base_dirs[1]}" ]]; then
        print
      fi

      if ! [[ "$base_dir" == "." && ${#base_show_list} -gt 0 ]]; then
        print -r "${base_dir}:"
      fi
    fi

    # ----------------------------------------------------------------------------
    # Vars
    # ----------------------------------------------------------------------------

    typeset -a MAX_LEN A RESULTS STAT_RESULTS
    typeset TOTAL_BLOCKS

    # Get now
    typeset K_EPOCH="${EPOCHSECONDS:?}"

    typeset -i TOTAL_BLOCKS=0

    MAX_LEN=(0 0 0 0 0 0)

    # Array to hold results from `stat` call
    RESULTS=()

    # only set once per directory so must be out of the main loop
    typeset -i IS_GIT_REPO=0
    typeset GIT_TOPLEVEL=''

    typeset -i LARGE_FILE_COLOR=196
    typeset -a SIZELIMITS_TO_COLOR
    SIZELIMITS_TO_COLOR=(
        1024  46    # <= 1kb
        2048  82    # <= 2kb
        3072  118   # <= 3kb
        5120  154   # <= 5kb
       10240  190   # <= 10kb
       20480  226   # <= 20kb
       40960  220   # <= 40kb
      102400  214   # <= 100kb
      262144  208   # <= 0.25mb || 256kb
      524288  202   # <= 0.5mb || 512kb
      )
    typeset -i ANCIENT_TIME_COLOR=236  # > more than 2 years old
    typeset -a FILEAGES_TO_COLOR
    FILEAGES_TO_COLOR=(
             0 196  # < in the future, #spooky
            60 255  # < less than a min old
          3600 252  # < less than an hour old
         86400 250  # < less than 1 day old
        604800 244  # < less than 1 week old
       2419200 244  # < less than 28 days (4 weeks) old
      15724800 242  # < less than 26 weeks (6 months) old
      31449600 240  # < less than 1 year old
      62899200 238  # < less than 2 years old
      )

    # ----------------------------------------------------------------------------
    # Build up list of files/directories to show
    # ----------------------------------------------------------------------------

    if [[ "$base_dir" == "." && ${#base_show_list} -gt 0 ]]; then
      show_list=("${base_show_list[@]}")
    else
      show_list=()

      # Check if it even exists
      if [[ ! -e $base_dir ]]; then
        print -u2 "kk: cannot access $base_dir: No such file or directory"

      # If its just a file, skip the directory handling
      elif [[ -f $base_dir ]]; then
        show_list=($base_dir)

      #Directory, add its contents
      else
        # Break total blocks of the front of the stat call, then push the rest to results
        if [[ "$o_all" != "" && "$o_almost_all" == "" && "$o_no_directory" == "" ]]; then
          show_list+=($base_dir/.)
          show_list+=($base_dir/..)
        fi

        if [[ "$o_all" != "" || "$o_almost_all" != "" ]]; then
          if [[ "$o_directory" != "" ]]; then
            show_list+=($base_dir/*(D/$SORT_GLOB))
          elif [[ "$o_no_directory" != "" ]]; then
            #Use (^/) instead of (.) so sockets and symlinks get displayed
            show_list+=($base_dir/*(D^/$SORT_GLOB))
          else
            show_list+=($base_dir/*(D$SORT_GLOB))
          fi
        else
          if [[ "$o_directory" != "" ]]; then
            #show_list+=($base_dir/*(/$SORT_GLOB))
            show_list+=($base_dir)
          elif [[ "$o_no_directory" != "" ]]; then
            #Use (^/) instead of (.) so sockets and symlinks get displayed
            show_list+=($base_dir/*(^/$SORT_GLOB))
          else
            show_list+=($base_dir/*($SORT_GLOB))
          fi
        fi
      fi
    fi

    # ----------------------------------------------------------------------------
    # Stat call to get directory listing
    # ----------------------------------------------------------------------------
    typeset -i i=1 j=1 k=1
    typeset -a STATS_PARAMS_LIST=()
    typeset fn statvar h
    typeset -A sv=()
    typeset -a fs=()
    typeset -A sz=()

    for fn in $show_list
    do
      statvar="stats_$i"
      typeset -A $statvar
      zstat -H $statvar -Lsn -F "%s^%d^%b^%H:%M^%Y" -- "$fn"  # use lstat, render mode/uid/gid to strings
      if [[ $? -ne 0 ]]; then continue; fi
      STATS_PARAMS_LIST+=($statvar)
      if [[ "$o_human" != "" ]]; then
        sv=("${(@Pkv)statvar}")
        fs+=("${sv[size]}")
      fi
      i+=1
    done

    if [[ "$o_human" != "" ]]; then
      fs=($( printf "%s\n" "${fs[@]}" | numfmt_local ))
      i=1
    fi

    # On each result calculate padding by getting max length on each array member
    for statvar in "${STATS_PARAMS_LIST[@]}"
    do
      sv=("${(@Pkv)statvar}")
      if [[ ${#sv[mode]}  -gt $MAX_LEN[1] ]]; then MAX_LEN[1]=${#sv[mode]}  ; fi
      if [[ ${#sv[nlink]} -gt $MAX_LEN[2] ]]; then MAX_LEN[2]=${#sv[nlink]} ; fi
      if [[ ${#sv[uid]}   -gt $MAX_LEN[3] ]]; then MAX_LEN[3]=${#sv[uid]}   ; fi
      if [[ ${#sv[gid]}   -gt $MAX_LEN[4] ]]; then MAX_LEN[4]=${#sv[gid]}   ; fi

      if [[ "$o_human" != "" ]]; then
        h="${fs[$(( i++ ))]}"
      else
        h="${sv[size]}"
      fi
      sz[${sv[name]}]="$h"
      if (( ${#h} > $MAX_LEN[5] )); then MAX_LEN[5]=${#h}; fi

      TOTAL_BLOCKS+=$sv[blocks]
    done

    # Print total block before listing
    if ! [[ "$base_dir" == "." && ${#base_show_list} -gt 0 ]]; then
      echo "total $TOTAL_BLOCKS"
    fi

    # ----------------------------------------------------------------------------
    # Loop through each line of stat, pad where appropriate and do git dirty checking
    # ----------------------------------------------------------------------------

    typeset REPOMARKER
    typeset PERMISSIONS HARDLINKCOUNT OWNER GROUP FILESIZE FILESIZE_OUT DATE NAME SYMLINK_TARGET
    typeset FILETYPE PER1 PER2 PER3 PERMISSIONS_OUTPUT STATUS
    typeset TIME_DIFF TIME_COLOR DATE_OUTPUT
    typeset -i IS_DIRECTORY IS_SYMLINK IS_SOCKET IS_PIPE IS_EXECUTABLE IS_BLOCK_SPECIAL IS_CHARACTER_SPECIAL HAS_UID_BIT HAS_GID_BIT HAS_STICKY_BIT IS_WRITABLE_BY_OTHERS
    typeset -i COLOR
    typeset -A VCS_STATUS=()

    if [[ "$o_no_vcs" == "" ]]; then
      local old_dir="$PWD"
      if builtin cd -q "$base_dir" 2>/dev/null; then
        GIT_TOPLEVEL=$(kk-git -c core.quotepath=false rev-parse --show-toplevel 2>/dev/null)
        if [[ $? -eq 0 ]]; then
          IS_GIT_REPO=1
          kk-git ls-files -c --deduplicate | cut -d/ -f1 | sort -u | while IFS= read fn; do
            VCS_STATUS["$fn"]="=="
          done

          local changed=0
          kk-git status --porcelain --ignored . 2>/dev/null | while IFS= read ln; do
            fn="${ln:3}"
            if [[ "$fn" == '"'*'"' ]]; then
              # Remove quotes(") from the file names containing special characters(', ", \, emoji, hangul)
              fn=${fn:1:-1}
            fi
            fn="$GIT_TOPLEVEL/${fn}"
            fn="${${${fn#$PWD/}:-.}%/}"
            st="${ln:0:2}"
            VCS_STATUS["${fn}"]="$st"
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
              VCS_STATUS["${fn}"]="$st"
              changed=1
            fi
          done

          if [[ "$o_all" != "" && "$o_almost_all" == "" && "$o_no_directory" == "" ]]; then
            if [[ -z "${VCS_STATUS["."]}" ]]; then
              if [[ $changed -eq 1 ]]; then
                VCS_STATUS["."]="//"
                if [[ "$PWD" =~ ${GIT_TOPLEVEL}/.* ]]; then
                  VCS_STATUS[".."]="//"
                fi
              fi
            fi
          fi
        fi
      fi
      builtin cd -q "$old_dir" >/dev/null
    fi

    k=1
    for statvar in "${STATS_PARAMS_LIST[@]}"
    do
      sv=("${(@Pkv)statvar}")

      # We check if the result is a git repo later, so set a blank marker indication the result is not a git repo
      REPOMARKER=""
      IS_DIRECTORY=0
      IS_SYMLINK=0
      IS_SOCKET=0
      IS_PIPE=0
      IS_EXECUTABLE=0
      IS_BLOCK_SPECIAL=0
      IS_CHARACTER_SPECIAL=0
      HAS_UID_BIT=0
      HAS_GID_BIT=0
      HAS_STICKY_BIT=0
      IS_WRITABLE_BY_OTHERS=0

         PERMISSIONS="${sv[mode]}"
       HARDLINKCOUNT="${sv[nlink]}"
               OWNER="${sv[uid]}"
               GROUP="${sv[gid]}"
            FILESIZE="${sv[size]}"
        FILESIZE_OUT="${sz[${sv[name]}]}"
                DATE=(${(s:^:)sv[mtime]}) # Split date on ^
                NAME="${sv[name]}"
      SYMLINK_TARGET="${sv[link]}"

      # Check for file types
      if [[ -d "$NAME" ]]; then IS_DIRECTORY=1; fi
      if [[ -L "$NAME" ]]; then IS_SYMLINK=1; fi
      if [[ -S "$NAME" ]]; then IS_SOCKET=1; fi
      if [[ -p "$NAME" ]]; then IS_PIPE=1; fi
      if [[ -x "$NAME" ]]; then IS_EXECUTABLE=1; fi
      if [[ -b "$NAME" ]]; then IS_BLOCK_SPECIAL=1; fi
      if [[ -c "$NAME" ]]; then IS_CHARACTER_SPECIAL=1; fi
      if [[ -u "$NAME" ]]; then HAS_UID_BIT=1; fi
      if [[ -g "$NAME" ]]; then HAS_GID_BIT=1; fi
      if [[ -k "$NAME" ]]; then HAS_STICKY_BIT=1; fi
      if [[ $PERMISSIONS[9] == 'w' ]]; then IS_WRITABLE_BY_OTHERS=1; fi

      # Pad so all the lines align - firstline gets padded the other way
        PERMISSIONS="${(r:MAX_LEN[1]:)PERMISSIONS}"
      HARDLINKCOUNT="${(l:MAX_LEN[2]:)HARDLINKCOUNT}"
              OWNER="${(l:MAX_LEN[3]:)OWNER}"
              GROUP="${(l:MAX_LEN[4]:)GROUP}"
       FILESIZE_OUT="${(l:MAX_LEN[5]:)FILESIZE_OUT}"

      # --------------------------------------------------------------------------
      # Colour the permissions - TODO
      # --------------------------------------------------------------------------
      # Colour the first character based on filetype
      FILETYPE="${PERMISSIONS[1]}"

      # Permissions Owner
      PER1="${PERMISSIONS[2,4]}"

      # Permissions Group
      PER2="${PERMISSIONS[5,7]}"

      # Permissions User
      PER3="${PERMISSIONS[8,10]}"

      PERMISSIONS_OUTPUT="$FILETYPE$PER1$PER2$PER3"

      # --------------------------------------------------------------------------
      # Colour the symlinks
      # --------------------------------------------------------------------------

      # --------------------------------------------------------------------------
      # Colour Owner and Group
      # --------------------------------------------------------------------------
      OWNER=$'\e[38;5;241m'"$OWNER"$'\e[0m'
      GROUP=$'\e[38;5;241m'"$GROUP"$'\e[0m'

      # --------------------------------------------------------------------------
      # Colour file weights
      # --------------------------------------------------------------------------
      COLOR=LARGE_FILE_COLOR
      for i j in ${SIZELIMITS_TO_COLOR[@]}
      do
        (( FILESIZE <= i )) || continue
        COLOR=$j
        break
      done

      FILESIZE_OUT=$'\e[38;5;'"${COLOR}m$FILESIZE_OUT"$'\e[0m'

      # --------------------------------------------------------------------------
      # Colour the date and time based on age, then format for output
      # --------------------------------------------------------------------------
      # Setup colours based on time difference
      TIME_DIFF=$(( K_EPOCH - DATE[1] ))
      TIME_COLOR=$ANCIENT_TIME_COLOR
      for i j in ${FILEAGES_TO_COLOR[@]}
      do
        (( TIME_DIFF < i )) || continue
        TIME_COLOR=$j
        break
      done

      # Format date to show year if more than 6 months since last modified
      if (( TIME_DIFF < 15724800 )); then
        DATE_OUTPUT="${DATE[2]} ${(r:5:: :)${DATE[3][0,5]}} ${DATE[4]}"
      else
        DATE_OUTPUT="${DATE[2]} ${(r:6:: :)${DATE[3][0,5]}} ${DATE[5]}"  # extra space; 4 digit year instead of 5 digit HH:MM
      fi;
      DATE_OUTPUT[1]="${DATE_OUTPUT[1]//0/ }" # If day of month begins with zero, replace zero with space

      # Apply colour to formated date
      DATE_OUTPUT=$'\e[38;5;'"${TIME_COLOR}m${DATE_OUTPUT}"$'\e[0m'


      NAME="${${${NAME%/}##*/}//$'\e'/\\e}"    # also propagate changes to SYMLINK_TARGET below

      # --------------------------------------------------------------------------
      # Colour the repomarker
      # --------------------------------------------------------------------------
      if (( IS_GIT_REPO != 0 )); then
        STATUS="${VCS_STATUS["$NAME"]}"
        if [[ "$NAME" != ".." ]]; then
          if [[ "${VCS_STATUS["."]}" == "!!" || "${VCS_STATUS[".."]}" == "!!" ]]; then
            STATUS="!!"
          elif [[ "${VCS_STATUS["."]}" == "??" ]]; then
            STATUS="??"
          fi
        fi

        if [[ "$STATUS" == "" ]]; then
          REPOMARKER="  "; # outside repository
        elif [[ "$STATUS" == "==" ]]; then
          REPOMARKER=$' \e[38;5;82m|\e[0m'; # not updated
        elif [[ "$STATUS" == "//" ]]; then
          REPOMARKER=$' \e[38;5;226m+\e[0m'; # changes exist inside the directory
        elif [[ "$STATUS" == "!!"  ]]; then
          REPOMARKER=$' \e[38;5;238m|\e[0m'; # ignored
        elif [[ "$STATUS" == "??" ]]; then
          REPOMARKER=$' \e[38;5;238m?\e[0m'; # untracked
        elif [[ "${STATUS:1:1}" == " " ]]; then
          REPOMARKER=$' \e[38;5;82m+\e[0m'; # index and work tree matches
        elif [[ "${STATUS:0:1}" == " " ]]; then
          REPOMARKER=$' \e[38;5;196m+\e[0m'; # work tree changed since index
        else
          REPOMARKER=$' \e[38;5;214m+\e[0m'; # work tree changed since index and index is updated
        fi
      fi

      # --------------------------------------------------------------------------
      # Colour the filename
      # --------------------------------------------------------------------------
      # Unfortunately, the choices for quoting which escape ANSI color sequences are q & qqqq; none of q- qq qqq work.
      # But we don't want to quote '.'; so instead we escape the escape manually and use q-
      if [[ $IS_DIRECTORY == 1 ]]; then
        if [[ $IS_WRITABLE_BY_OTHERS == 1 ]]; then
          if [[ $HAS_STICKY_BIT == 1 ]]; then
            NAME=$'\e['"$K_COLOR_TW"'m'"$NAME"$'\e[0m';
          fi
          NAME=$'\e['"$K_COLOR_OW"'m'"$NAME"$'\e[0m';
        fi
        NAME=$'\e['"$K_COLOR_DI"'m'"$NAME"$'\e[0m';
      elif [[ $IS_SYMLINK           == 1 ]]; then NAME=$'\e['"$K_COLOR_LN"'m'"$NAME"$'\e[0m';
      elif [[ $IS_SOCKET            == 1 ]]; then NAME=$'\e['"$K_COLOR_SO"'m'"$NAME"$'\e[0m';
      elif [[ $IS_PIPE              == 1 ]]; then NAME=$'\e['"$K_COLOR_PI"'m'"$NAME"$'\e[0m';
      elif [[ $HAS_UID_BIT          == 1 ]]; then NAME=$'\e['"$K_COLOR_SU"'m'"$NAME"$'\e[0m';
      elif [[ $HAS_GID_BIT          == 1 ]]; then NAME=$'\e['"$K_COLOR_SG"'m'"$NAME"$'\e[0m';
      elif [[ $IS_EXECUTABLE        == 1 ]]; then NAME=$'\e['"$K_COLOR_EX"'m'"$NAME"$'\e[0m';
      elif [[ $IS_BLOCK_SPECIAL     == 1 ]]; then NAME=$'\e['"$K_COLOR_BD"'m'"$NAME"$'\e[0m';
      elif [[ $IS_CHARACTER_SPECIAL == 1 ]]; then NAME=$'\e['"$K_COLOR_CD"'m'"$NAME"$'\e[0m';
      fi

      # --------------------------------------------------------------------------
      # Format symlink target
      # --------------------------------------------------------------------------
      if [[ $SYMLINK_TARGET != "" ]]; then SYMLINK_TARGET=" -> ${SYMLINK_TARGET//$'\e'/\\e}"; fi

      # --------------------------------------------------------------------------
      # Display final result
      # --------------------------------------------------------------------------
      print -r -- "$PERMISSIONS_OUTPUT $HARDLINKCOUNT $OWNER $GROUP $FILESIZE_OUT $DATE_OUTPUT$REPOMARKER $NAME$SYMLINK_TARGET"

      k=$((k+1)) # Bump loop index
    done
  done
}

_k_bsd_to_ansi() {
  local foreground=$1 background=$2 foreground_ansi background_ansi
  case $foreground in
    a) foreground_ansi=30;;
    b) foreground_ansi=31;;
    c) foreground_ansi=32;;
    d) foreground_ansi=33;;
    e) foreground_ansi=34;;
    f) foreground_ansi=35;;
    g) foreground_ansi=36;;
    h) foreground_ansi=37;;
    x) foreground_ansi=0;;
  esac
  case $background in
    a) background_ansi=40;;
    b) background_ansi=41;;
    c) background_ansi=42;;
    d) background_ansi=43;;
    e) background_ansi=44;;
    f) background_ansi=45;;
    g) background_ansi=46;;
    h) background_ansi=47;;
    x) background_ansi=0;;
  esac
  printf "%s;%s" $background_ansi $foreground_ansi
}

# http://upload.wikimedia.org/wikipedia/en/1/15/Xterm_256color_chart.svg
# vim: set ts=2 sw=2 ft=zsh et :
