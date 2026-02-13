mod cli;
mod colors;
mod entry;
mod format;
mod git;
mod sort;

use clap::Parser;
use cli::Args;
use colors::FileColors;
use entry::FileEntry;
use sort::{resolve_sort_key, sort_entries};
use std::fs;
use std::path::{Path, PathBuf};
use std::process;

fn main() {
    let args = Args::parse();

    if args.help {
        print_help();
        process::exit(1);
    }

    if let Err(e) = args.validate() {
        eprintln!("kk: {}", e);
        process::exit(1);
    }

    let colors = FileColors::new();
    let sort_key = resolve_sort_key(&args);

    // Resolve target paths
    let (dirs, file_args) = resolve_targets(&args);

    let mut first = true;
    for dir in &dirs {
        // Print directory header when multiple targets
        if dirs.len() > 1 {
            if !first {
                println!();
            }
            // If this is the "." with explicit file args, skip header
            if !(dir.to_str() == Some(".") && !file_args.is_empty()) {
                println!("{}:", dir.display());
            }
            first = false;
        }

        // Build file list
        let entries_result = if dir.to_str() == Some(".") && !file_args.is_empty() {
            // Explicit file arguments
            build_file_list_from_args(&file_args)
        } else {
            build_file_list(dir, &args)
        };

        let mut entries = match entries_result {
            Some(e) => e,
            None => continue,
        };

        if entries.is_empty() {
            if dirs.len() <= 1 && file_args.is_empty() {
                println!("total 0");
            }
            continue;
        }

        // Sort
        sort_entries(&mut entries, sort_key, args.reverse, args.group_dirs);

        // Calculate total blocks
        let total_blocks: u64 = entries.iter().map(|e| e.blocks).sum();

        // Print "total" line (skip for explicit file args in "." dir)
        if !(dir.to_str() == Some(".") && !file_args.is_empty()) {
            println!("total {}", total_blocks);
        }

        // Collect VCS status
        let vcs_map = if !args.no_vcs {
            git::collect_vcs_status(dir, args.all, args.almost_all, args.no_directory)
        } else {
            None
        };

        // Print entries
        format::print_entries(&entries, &colors, &vcs_map, args.human, args.si);
    }
}

fn resolve_targets(args: &Args) -> (Vec<PathBuf>, Vec<PathBuf>) {
    let mut dirs: Vec<PathBuf> = Vec::new();
    let mut file_args: Vec<PathBuf> = Vec::new();

    if args.paths.is_empty() {
        dirs.push(PathBuf::from("."));
    } else if !args.directory {
        for p in &args.paths {
            if p.is_dir() {
                dirs.push(p.clone());
            } else {
                if dirs.first().map(|d| d.to_str()) != Some(Some(".")) {
                    dirs.insert(0, PathBuf::from("."));
                }
                file_args.push(p.clone());
            }
        }
    } else {
        dirs.push(PathBuf::from("."));
        file_args = args.paths.clone();
    }

    if dirs.is_empty() && !file_args.is_empty() {
        dirs.push(PathBuf::from("."));
    }

    (dirs, file_args)
}

fn print_help() {
    eprintln!("Usage: kk [options] DIR");
    eprintln!("Options:");
    eprintln!("\t-a      --all           list entries starting with .");
    eprintln!("\t-A      --almost-all    list all except . and ..");
    eprintln!("\t-c                      sort by ctime (inode change time)");
    eprintln!("\t-d      --directory     list only directories");
    eprintln!("\t-n      --no-directory  do not list directories");
    eprintln!("\t-h      --human         show filesizes in human-readable format");
    eprintln!("\t        --si            with -h, use powers of 1000 not 1024");
    eprintln!("\t-r      --reverse       reverse sort order");
    eprintln!("\t-S                      sort by size");
    eprintln!("\t-t                      sort by time (modification time)");
    eprintln!("\t-u                      sort by atime (use or access time)");
    eprintln!("\t-U                      Unsorted");
    eprintln!("\t        --sort WORD     sort by WORD: none (U), size (S),");
    eprintln!("\t                        time (t), ctime or status (c),");
    eprintln!("\t                        atime or access or use (u)");
    eprintln!("\t        --no-vcs        do not get VCS status (much faster)");
    eprintln!("\t        --help          show this help");
}

fn build_file_list_from_args(file_args: &[PathBuf]) -> Option<Vec<FileEntry>> {
    let mut entries = Vec::new();
    for path in file_args {
        if !path.exists() && !path.symlink_metadata().is_ok() {
            eprintln!(
                "kk: cannot access {}: No such file or directory",
                path.display()
            );
            continue;
        }
        if let Some(entry) = FileEntry::from_path(path) {
            entries.push(entry);
        }
    }
    Some(entries)
}

fn build_file_list(dir: &Path, args: &Args) -> Option<Vec<FileEntry>> {
    // Non-existent path
    if !dir.exists() {
        eprintln!(
            "kk: cannot access {}: No such file or directory",
            dir.display()
        );
        return None;
    }

    // Single file
    if dir.is_file() {
        return FileEntry::from_path(dir).map(|e| vec![e]);
    }

    let mut entries = Vec::new();

    // Include . and .. when -a (but not -A or -n)
    if args.all && !args.almost_all && !args.no_directory {
        if let Some(dot) = FileEntry::from_path(&dir.join(".")) {
            let mut dot = dot;
            dot.display_name = ".".to_string();
            entries.push(dot);
        }
        if let Some(dotdot) = FileEntry::from_path(&dir.join("..")) {
            let mut dotdot = dotdot;
            dotdot.display_name = "..".to_string();
            entries.push(dotdot);
        }
    }

    // Read directory contents
    let read_dir = match fs::read_dir(dir) {
        Ok(rd) => rd,
        Err(e) => {
            eprintln!("kk: cannot open directory {}: {}", dir.display(), e);
            return None;
        }
    };

    for dir_entry in read_dir {
        let dir_entry = match dir_entry {
            Ok(de) => de,
            Err(_) => continue,
        };

        let name = dir_entry.file_name().to_string_lossy().into_owned();

        // Hidden files filter
        if name.starts_with('.') && !args.all && !args.almost_all {
            continue;
        }

        let path = dir_entry.path();

        let entry = match FileEntry::from_path(&path) {
            Some(e) => e,
            None => continue,
        };

        // Directory filters
        if args.directory && !entry.is_dir() {
            continue;
        }
        if args.no_directory && entry.is_dir() {
            continue;
        }

        entries.push(entry);
    }

    Some(entries)
}
