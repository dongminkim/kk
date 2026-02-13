# kk

A fast, git-aware `ls` replacement written in Rust.

`kk` displays directory listings in a long format with file metadata, colorized output, and inline git status markers. It uses [libgit2](https://libgit2.org/) directly (via `git2` crate) instead of shelling out to `git`, making it significantly faster in large repositories.

## Features

- Color-coded file types (directories, symlinks, executables, etc.)
- Inline git status markers per file (`|` clean, `+` modified, `?` untracked, `!` ignored)
- Human-readable file sizes (`-h`)
- macOS `LSCOLORS` support
- Single static binary with zero runtime dependencies

## Installation

### From source

```
cargo install --path .
```

### Build manually

```
git clone https://github.com/dongminkim/kk.git
cd kk
cargo build --release
# Binary at ./target/release/kk
```

## Usage

```
kk [options] [DIR...]
```

### Options

| Flag | Long | Description |
|------|------|-------------|
| `-a` | `--all` | List entries starting with `.` |
| `-A` | `--almost-all` | List all except `.` and `..` |
| `-h` | `--human` | Show file sizes in human-readable format |
| | `--si` | With `-h`, use powers of 1000 instead of 1024 |
| `-d` | `--directory` | List only directories |
| `-n` | `--no-directory` | Do not list directories |
| `-r` | `--reverse` | Reverse sort order |
| `-S` | | Sort by size |
| `-t` | | Sort by modification time |
| `-c` | | Sort by ctime (inode change time) |
| `-u` | | Sort by atime (access time) |
| `-U` | | Unsorted |
| | `--sort WORD` | Sort by: `none`, `size`, `time`, `ctime`, `status`, `atime`, `access`, `use` |
| | `--no-vcs` | Do not show git status (faster) |
| | `--group-directories-first` | Group directories before files |

### Examples

```bash
kk              # List current directory with git status
kk -a           # Include hidden files
kk -h           # Human-readable sizes
kk -t           # Sort by modification time
kk --no-vcs .   # Skip git status (faster)
kk -S -r        # Sort by size, reversed (smallest first)
kk dir1 dir2    # List multiple directories
```

### Git status markers

Each file displays a git status marker in the column before the filename:

| Marker | Color | Meaning |
|--------|-------|---------|
| `\|` | green | Tracked, clean |
| `+` | green | Staged (index modified) |
| `+` | red | Work tree modified |
| `+` | orange | Both index and work tree modified |
| `+` | yellow | Directory contains changes |
| `?` | dim | Untracked |
| `\|` | dim | Ignored |

## Project structure

```
src/
  main.rs      Entry point, path resolution, file listing
  cli.rs       Command-line argument parsing (clap)
  entry.rs     FileEntry struct, file metadata collection (lstat)
  git.rs       Git status collection via libgit2
  format.rs    Output formatting (column alignment, colors, dates, sizes)
  colors.rs    File type colors, LSCOLORS parsing
  sort.rs      Sorting logic
```

## Dependencies

| Crate | Purpose |
|-------|---------|
| [clap](https://crates.io/crates/clap) | CLI argument parsing |
| [git2](https://crates.io/crates/git2) | libgit2 bindings for git status |
| [libgit2-sys](https://crates.io/crates/libgit2-sys) | Vendored libgit2 (static linking) |
| [libc](https://crates.io/crates/libc) | Unix file metadata (mode, blocks) |
| [chrono](https://crates.io/crates/chrono) | Date formatting |
| [uzers](https://crates.io/crates/uzers) | uid/gid to username/group name |

## License

MIT License

## History

Originally a [zsh script](https://github.com/supercrabtree/k) (`k`), rewritten in Rust for performance and portability.
