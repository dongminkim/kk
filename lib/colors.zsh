# kk plugin color definitions and initialization

# Global associative array for file type colors
typeset -gA KK_COLORS

# Global arrays for size and age color mappings
typeset -ga KK_SIZELIMITS_TO_COLOR
typeset -ga KK_FILEAGES_TO_COLOR

# Global color constants
typeset -gi KK_LARGE_FILE_COLOR
typeset -gi KK_ANCIENT_TIME_COLOR

# Initialize file type colors
# Reads from LSCOLORS (BSD/macOS) or LS_COLORS (Linux) if available
_kk_init_colors() {
  # default colors
  KK_COLORS[di]="0;34"  # di:directory
  KK_COLORS[ln]="0;35"  # ln:symlink
  KK_COLORS[so]="0;32"  # so:socket
  KK_COLORS[pi]="0;33"  # pi:pipe
  KK_COLORS[ex]="0;31"  # ex:executable
  KK_COLORS[bd]="34;46" # bd:block special
  KK_COLORS[cd]="34;43" # cd:character special
  KK_COLORS[su]="30;41" # su:executable with setuid bit set
  KK_COLORS[sg]="30;46" # sg:executable with setgid bit set
  KK_COLORS[tw]="30;42" # tw:directory writable to others, with sticky bit
  KK_COLORS[ow]="30;43" # ow:directory writable to others, without sticky bit
  KK_COLORS[br]="0;30"  # branch

  # read colors if osx and $LSCOLORS is defined
  if [[ $(uname) == 'Darwin' && -n $LSCOLORS ]]; then
    # Translate OSX/BSD's LSCOLORS so we can use the same here
    KK_COLORS[di]=$(_kk_bsd_to_ansi $LSCOLORS[1]  $LSCOLORS[2])
    KK_COLORS[ln]=$(_kk_bsd_to_ansi $LSCOLORS[3]  $LSCOLORS[4])
    KK_COLORS[so]=$(_kk_bsd_to_ansi $LSCOLORS[5]  $LSCOLORS[6])
    KK_COLORS[pi]=$(_kk_bsd_to_ansi $LSCOLORS[7]  $LSCOLORS[8])
    KK_COLORS[ex]=$(_kk_bsd_to_ansi $LSCOLORS[9]  $LSCOLORS[10])
    KK_COLORS[bd]=$(_kk_bsd_to_ansi $LSCOLORS[11] $LSCOLORS[12])
    KK_COLORS[cd]=$(_kk_bsd_to_ansi $LSCOLORS[13] $LSCOLORS[14])
    KK_COLORS[su]=$(_kk_bsd_to_ansi $LSCOLORS[15] $LSCOLORS[16])
    KK_COLORS[sg]=$(_kk_bsd_to_ansi $LSCOLORS[17] $LSCOLORS[18])
    KK_COLORS[tw]=$(_kk_bsd_to_ansi $LSCOLORS[19] $LSCOLORS[20])
    KK_COLORS[ow]=$(_kk_bsd_to_ansi $LSCOLORS[21] $LSCOLORS[22])
  fi

  # TODO: read colors if linux and $LS_COLORS is defined
}

# Initialize file size to color mappings
_kk_init_size_colors() {
  KK_LARGE_FILE_COLOR=196
  KK_SIZELIMITS_TO_COLOR=(
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
}

# Initialize file age to color mappings
_kk_init_age_colors() {
  KK_ANCIENT_TIME_COLOR=236  # > more than 2 years old
  KK_FILEAGES_TO_COLOR=(
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
}

# vim: set ts=2 sw=2 ft=zsh et :
