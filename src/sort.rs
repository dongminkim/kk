use crate::cli::Args;
use crate::entry::FileEntry;

#[derive(Debug, Clone, Copy)]
pub enum SortKey {
    Name,
    Size,
    Mtime,
    Ctime,
    Atime,
    Unsorted,
}

pub fn resolve_sort_key(args: &Args) -> SortKey {
    // --sort WORD takes precedence
    if let Some(ref word) = args.sort_word {
        return match word.as_str() {
            "none" => SortKey::Unsorted,
            "size" => SortKey::Size,
            "time" => SortKey::Mtime,
            "ctime" | "status" => SortKey::Ctime,
            "atime" | "access" | "use" => SortKey::Atime,
            _ => SortKey::Name,
        };
    }
    if args.unsorted {
        SortKey::Unsorted
    } else if args.sort_size {
        SortKey::Size
    } else if args.sort_time {
        SortKey::Mtime
    } else if args.sort_ctime {
        SortKey::Ctime
    } else if args.sort_atime {
        SortKey::Atime
    } else {
        SortKey::Name
    }
}

pub fn sort_entries(entries: &mut Vec<FileEntry>, key: SortKey, reverse: bool, group_dirs: bool) {
    if matches!(key, SortKey::Unsorted) && !group_dirs {
        return;
    }

    entries.sort_by(|a, b| {
        // Group directories first if requested
        if group_dirs {
            let a_dir = a.is_dir();
            let b_dir = b.is_dir();
            if a_dir && !b_dir {
                return std::cmp::Ordering::Less;
            }
            if !a_dir && b_dir {
                return std::cmp::Ordering::Greater;
            }
        }

        if matches!(key, SortKey::Unsorted) {
            return std::cmp::Ordering::Equal;
        }

        // zsh glob qualifiers: when primary sort key is equal,
        // ties are broken by name in reverse order (Z→A), case-sensitive
        let name_cmp_rev = || {
            b.display_name.cmp(&a.display_name)
        };

        let ord = match key {
            SortKey::Name => a
                .display_name
                .to_lowercase()
                .cmp(&b.display_name.to_lowercase()),
            SortKey::Size => {
                // Size: largest first by default
                b.size.cmp(&a.size).then_with(name_cmp_rev)
            }
            SortKey::Mtime => b.mtime.cmp(&a.mtime).then_with(name_cmp_rev),
            SortKey::Ctime => b.ctime.cmp(&a.ctime).then_with(name_cmp_rev),
            SortKey::Atime => b.atime.cmp(&a.atime).then_with(name_cmp_rev),
            SortKey::Unsorted => std::cmp::Ordering::Equal,
        };

        if reverse { ord.reverse() } else { ord }
    });
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::path::PathBuf;

    fn default_args() -> Args {
        Args {
            all: false,
            almost_all: false,
            human: false,
            si: false,
            directory: false,
            no_directory: false,
            reverse: false,
            sort_size: false,
            sort_time: false,
            sort_ctime: false,
            sort_atime: false,
            unsorted: false,
            sort_word: None,
            no_vcs: false,
            group_dirs: false,
            help: false,
            paths: vec![],
        }
    }

    fn make_entry(name: &str, size: u64, mtime: i64, is_dir: bool) -> FileEntry {
        let mode = if is_dir { 0o040755 } else { 0o100644 };
        FileEntry {
            path: PathBuf::from(name),
            display_name: name.to_string(),
            metadata: std::fs::symlink_metadata("/").unwrap(), // dummy
            mode,
            nlinks: 1,
            owner: "user".to_string(),
            group: "staff".to_string(),
            size,
            mtime,
            atime: mtime,
            ctime: mtime,
            blocks: 0,
            symlink_target: None,
            permission_string: "drwxr-xr-x".to_string(),
        }
    }

    // ---- resolve_sort_key tests ----

    #[test]
    fn test_resolve_default_name() {
        let args = default_args();
        assert!(matches!(resolve_sort_key(&args), SortKey::Name));
    }

    #[test]
    fn test_resolve_sort_size() {
        let mut args = default_args();
        args.sort_size = true;
        assert!(matches!(resolve_sort_key(&args), SortKey::Size));
    }

    #[test]
    fn test_resolve_sort_time() {
        let mut args = default_args();
        args.sort_time = true;
        assert!(matches!(resolve_sort_key(&args), SortKey::Mtime));
    }

    #[test]
    fn test_resolve_sort_ctime() {
        let mut args = default_args();
        args.sort_ctime = true;
        assert!(matches!(resolve_sort_key(&args), SortKey::Ctime));
    }

    #[test]
    fn test_resolve_sort_atime() {
        let mut args = default_args();
        args.sort_atime = true;
        assert!(matches!(resolve_sort_key(&args), SortKey::Atime));
    }

    #[test]
    fn test_resolve_unsorted() {
        let mut args = default_args();
        args.unsorted = true;
        assert!(matches!(resolve_sort_key(&args), SortKey::Unsorted));
    }

    #[test]
    fn test_resolve_sort_word_takes_precedence() {
        let mut args = default_args();
        args.sort_size = true; // flag says size
        args.sort_word = Some("time".to_string()); // --sort says time
        assert!(matches!(resolve_sort_key(&args), SortKey::Mtime));
    }

    #[test]
    fn test_resolve_sort_word_none() {
        let mut args = default_args();
        args.sort_word = Some("none".to_string());
        assert!(matches!(resolve_sort_key(&args), SortKey::Unsorted));
    }

    #[test]
    fn test_resolve_sort_word_ctime_status() {
        let mut args = default_args();
        args.sort_word = Some("ctime".to_string());
        assert!(matches!(resolve_sort_key(&args), SortKey::Ctime));

        args.sort_word = Some("status".to_string());
        assert!(matches!(resolve_sort_key(&args), SortKey::Ctime));
    }

    #[test]
    fn test_resolve_sort_word_atime_aliases() {
        let mut args = default_args();
        args.sort_word = Some("atime".to_string());
        assert!(matches!(resolve_sort_key(&args), SortKey::Atime));

        args.sort_word = Some("access".to_string());
        assert!(matches!(resolve_sort_key(&args), SortKey::Atime));

        args.sort_word = Some("use".to_string());
        assert!(matches!(resolve_sort_key(&args), SortKey::Atime));
    }

    #[test]
    fn test_resolve_sort_word_unknown_defaults_to_name() {
        let mut args = default_args();
        args.sort_word = Some("unknown".to_string());
        assert!(matches!(resolve_sort_key(&args), SortKey::Name));
    }

    // ---- sort_entries tests ----

    #[test]
    fn test_sort_by_name_case_insensitive() {
        let mut entries = vec![
            make_entry("Banana", 0, 0, false),
            make_entry("apple", 0, 0, false),
            make_entry("Cherry", 0, 0, false),
        ];
        sort_entries(&mut entries, SortKey::Name, false, false);
        let names: Vec<&str> = entries.iter().map(|e| e.display_name.as_str()).collect();
        assert_eq!(names, vec!["apple", "Banana", "Cherry"]);
    }

    #[test]
    fn test_sort_by_size_largest_first() {
        let mut entries = vec![
            make_entry("small", 100, 0, false),
            make_entry("big", 5000, 0, false),
            make_entry("medium", 1000, 0, false),
        ];
        sort_entries(&mut entries, SortKey::Size, false, false);
        let names: Vec<&str> = entries.iter().map(|e| e.display_name.as_str()).collect();
        assert_eq!(names, vec!["big", "medium", "small"]);
    }

    #[test]
    fn test_sort_by_mtime_newest_first() {
        let mut entries = vec![
            make_entry("old", 0, 1000, false),
            make_entry("new", 0, 3000, false),
            make_entry("mid", 0, 2000, false),
        ];
        sort_entries(&mut entries, SortKey::Mtime, false, false);
        let names: Vec<&str> = entries.iter().map(|e| e.display_name.as_str()).collect();
        assert_eq!(names, vec!["new", "mid", "old"]);
    }

    #[test]
    fn test_sort_reverse() {
        let mut entries = vec![
            make_entry("a", 0, 0, false),
            make_entry("c", 0, 0, false),
            make_entry("b", 0, 0, false),
        ];
        sort_entries(&mut entries, SortKey::Name, true, false);
        let names: Vec<&str> = entries.iter().map(|e| e.display_name.as_str()).collect();
        assert_eq!(names, vec!["c", "b", "a"]);
    }

    #[test]
    fn test_sort_group_dirs_first() {
        let mut entries = vec![
            make_entry("file_a", 0, 0, false),
            make_entry("dir_b", 0, 0, true),
            make_entry("file_c", 0, 0, false),
            make_entry("dir_a", 0, 0, true),
        ];
        sort_entries(&mut entries, SortKey::Name, false, true);
        // Dirs first, then files, both sorted by name
        assert!(entries[0].is_dir());
        assert!(entries[1].is_dir());
        assert!(!entries[2].is_dir());
        assert!(!entries[3].is_dir());
        assert_eq!(entries[0].display_name, "dir_a");
        assert_eq!(entries[1].display_name, "dir_b");
        assert_eq!(entries[2].display_name, "file_a");
        assert_eq!(entries[3].display_name, "file_c");
    }

    #[test]
    fn test_sort_unsorted_no_change() {
        let mut entries = vec![
            make_entry("c", 0, 0, false),
            make_entry("a", 0, 0, false),
            make_entry("b", 0, 0, false),
        ];
        sort_entries(&mut entries, SortKey::Unsorted, false, false);
        let names: Vec<&str> = entries.iter().map(|e| e.display_name.as_str()).collect();
        assert_eq!(names, vec!["c", "a", "b"]);
    }
}
