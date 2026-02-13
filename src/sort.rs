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
