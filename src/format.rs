use crate::colors::FileColors;
use crate::entry::FileEntry;
use crate::git::VcsStatus;
use chrono::{Local, TimeZone};
use std::collections::HashMap;
use std::io::{self, Write};
use std::time::SystemTime;

/// Size thresholds: (max_bytes, 256-color code)
const SIZELIMITS_TO_COLOR: &[(u64, u16)] = &[
    (1024, 46),
    (2048, 82),
    (3072, 118),
    (5120, 154),
    (10240, 190),
    (20480, 226),
    (40960, 220),
    (102400, 214),
    (262144, 208),
    (524288, 202),
];
const LARGE_FILE_COLOR: u16 = 196;

/// Age thresholds: (max_seconds, 256-color code)
const FILEAGES_TO_COLOR: &[(i64, u16)] = &[
    (0, 196),         // future
    (60, 255),        // < 1 min
    (3600, 252),      // < 1 hour
    (86400, 250),     // < 1 day
    (604800, 244),    // < 1 week
    (2419200, 244),   // < 4 weeks
    (15724800, 242),  // < 6 months
    (31449600, 240),  // < 1 year
    (62899200, 238),  // < 2 years
];
const ANCIENT_TIME_COLOR: u16 = 236;
const SIX_MONTHS: i64 = 15724800;

pub struct ColumnWidths {
    pub perms: usize,
    pub nlinks: usize,
    pub owner: usize,
    pub group: usize,
    pub size: usize,
}

impl ColumnWidths {
    pub fn compute(entries: &[FileEntry], human: bool, si: bool) -> (Self, Vec<String>) {
        let mut perms = 0usize;
        let mut nlinks = 0usize;
        let mut owner = 0usize;
        let mut group = 0usize;
        let mut size_w = 0usize;

        let size_strings: Vec<String> = entries
            .iter()
            .map(|e| {
                if human {
                    human_readable(e.size, si)
                } else {
                    e.size.to_string()
                }
            })
            .collect();

        for (i, e) in entries.iter().enumerate() {
            let p = e.permission_string.len();
            if p > perms { perms = p; }
            let n = e.nlinks.to_string().len();
            if n > nlinks { nlinks = n; }
            let o = e.owner.len();
            if o > owner { owner = o; }
            let g = e.group.len();
            if g > group { group = g; }
            let s = size_strings[i].len();
            if s > size_w { size_w = s; }
        }

        (ColumnWidths { perms, nlinks, owner, group, size: size_w }, size_strings)
    }
}

pub fn format_entry(
    entry: &FileEntry,
    widths: &ColumnWidths,
    size_str: &str,
    colors: &FileColors,
    vcs_status: Option<&VcsStatus>,
    now: i64,
) -> String {
    let mut out = String::with_capacity(256);

    // Permissions
    out.push_str(&format!("{:<width$}", entry.permission_string, width = widths.perms));

    // Nlinks
    out.push_str(&format!(
        " {:>width$}",
        entry.nlinks,
        width = widths.nlinks
    ));

    // Owner (dimmed)
    out.push_str(&format!(
        " \x1b[38;5;241m{:>width$}\x1b[0m",
        entry.owner,
        width = widths.owner
    ));

    // Group (dimmed)
    out.push_str(&format!(
        " \x1b[38;5;241m{:>width$}\x1b[0m",
        entry.group,
        width = widths.group
    ));

    // Size (colored by threshold)
    let size_color = color_for_size(entry.size);
    out.push_str(&format!(
        " \x1b[38;5;{}m{:>width$}\x1b[0m",
        size_color,
        size_str,
        width = widths.size
    ));

    // Date
    let time_diff = now - entry.mtime;
    let date_str = format_date(entry.mtime, time_diff);
    let time_color = color_for_age(time_diff);
    out.push_str(&format!(" \x1b[38;5;{}m{}\x1b[0m", time_color, date_str));

    // VCS marker
    if let Some(status) = vcs_status {
        out.push_str(&format_vcs_marker(status));
    }

    // Filename (colored by type)
    out.push(' ');
    if let Some(color) = colors.color_for(entry) {
        out.push_str(&format!(
            "\x1b[{}m{}\x1b[0m",
            color, entry.display_name
        ));
    } else {
        out.push_str(&entry.display_name);
    }

    // Symlink target
    if let Some(ref target) = entry.symlink_target {
        out.push_str(&format!(" -> {}", target));
    }

    out
}

fn color_for_size(size: u64) -> u16 {
    for &(limit, color) in SIZELIMITS_TO_COLOR {
        if size <= limit {
            return color;
        }
    }
    LARGE_FILE_COLOR
}

fn color_for_age(time_diff: i64) -> u16 {
    for &(limit, color) in FILEAGES_TO_COLOR {
        if time_diff < limit {
            return color;
        }
    }
    ANCIENT_TIME_COLOR
}

fn format_date(mtime: i64, time_diff: i64) -> String {
    let dt = Local.timestamp_opt(mtime, 0).single().unwrap_or_else(|| Local::now());

    // zsh version uses: DD Mon   HH:MM  or  DD Mon    YYYY
    // date_parts from zstat: [epoch, day, month, HH:MM, year]
    // output: "${date_parts[2]} ${(r:5:: :)${date_parts[3][0,5]}} ${date_parts[4]}"
    // which is: "day month(padded to 5)  HH:MM"
    let day = dt.format("%e").to_string(); // space-padded day
    let month = dt.format("%b").to_string(); // abbreviated month

    if time_diff < SIX_MONTHS {
        let time = dt.format("%H:%M").to_string();
        // Format: "DD Mon   HH:MM" - month padded to 5 chars (right-padded with spaces)
        format!("{} {:<5} {}", day, month, time)
    } else {
        let year = dt.format("%Y").to_string();
        // Format: "DD Mon    YYYY" - month padded to 6 chars
        format!("{} {:<6} {}", day, month, year)
    }
}

fn format_vcs_marker(status: &VcsStatus) -> String {
    match status {
        VcsStatus::Clean => format!(" \x1b[38;5;82m|\x1b[0m"),
        VcsStatus::DirChanged => format!(" \x1b[38;5;226m+\x1b[0m"),
        VcsStatus::DirUntracked => format!(" \x1b[38;5;226m?\x1b[0m"),
        VcsStatus::DirEmptyUntracked => format!(" \x1b[38;5;238m?\x1b[0m"),
        VcsStatus::Ignored => format!(" \x1b[38;5;238m|\x1b[0m"),
        VcsStatus::Untracked => format!(" \x1b[38;5;196m?\x1b[0m"),
        VcsStatus::Staged => format!(" \x1b[38;5;82m+\x1b[0m"),
        VcsStatus::WorkTreeChanged => format!(" \x1b[38;5;196m+\x1b[0m"),
        VcsStatus::BothChanged => format!(" \x1b[38;5;214m+\x1b[0m"),
        VcsStatus::None => "  ".to_string(),
    }
}

pub fn human_readable(size: u64, si: bool) -> String {
    let base: u64 = if si { 1000 } else { 1024 };
    let units = ["", "K", "M", "G", "T", "P"];

    if size < base {
        return size.to_string();
    }

    // Match numfmt behavior: use ceiling division
    let mut val = size;
    let mut unit_idx = 0;

    while val >= base * base && unit_idx < units.len() - 2 {
        val = (val + base - 1) / base;
        unit_idx += 1;
    }

    // Final division with ceiling
    let result = (val + base - 1) / base;
    unit_idx += 1;

    format!("{}{}", result, units[unit_idx])
}

pub fn print_entries(
    entries: &[FileEntry],
    colors: &FileColors,
    vcs_map: &Option<HashMap<String, VcsStatus>>,
    human: bool,
    si: bool,
) {
    let now = SystemTime::now()
        .duration_since(SystemTime::UNIX_EPOCH)
        .map(|d| d.as_secs() as i64)
        .unwrap_or(0);

    let (widths, size_strings) = ColumnWidths::compute(entries, human, si);

    let stdout = io::stdout();
    let mut out = io::BufWriter::new(stdout.lock());

    for (i, entry) in entries.iter().enumerate() {
        let vcs_status = vcs_map.as_ref().map(|m| {
            m.get(&entry.display_name)
                .cloned()
                .unwrap_or(VcsStatus::None)
        });

        let line = format_entry(
            entry,
            &widths,
            &size_strings[i],
            colors,
            vcs_status.as_ref(),
            now,
        );
        let _ = writeln!(out, "{}", line);
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    // ---- human_readable tests ----

    #[test]
    fn test_human_readable_zero() {
        assert_eq!(human_readable(0, false), "0");
    }

    #[test]
    fn test_human_readable_below_base() {
        assert_eq!(human_readable(512, false), "512");
        assert_eq!(human_readable(1023, false), "1023");
    }

    #[test]
    fn test_human_readable_kilobytes() {
        assert_eq!(human_readable(1024, false), "1K");
        assert_eq!(human_readable(2048, false), "2K");
    }

    #[test]
    fn test_human_readable_megabytes() {
        assert_eq!(human_readable(1048576, false), "1M");
    }

    #[test]
    fn test_human_readable_gigabytes() {
        assert_eq!(human_readable(1073741824, false), "1G");
    }

    #[test]
    fn test_human_readable_si_mode() {
        assert_eq!(human_readable(999, true), "999");
        assert_eq!(human_readable(1000, true), "1K");
        assert_eq!(human_readable(1000000, true), "1M");
    }

    #[test]
    fn test_human_readable_ceiling() {
        // 1025 bytes → should ceil to 2K (not 1K)
        assert_eq!(human_readable(1025, false), "2K");
    }

    // ---- color_for_size tests ----

    #[test]
    fn test_color_for_size_zero() {
        assert_eq!(color_for_size(0), 46);
    }

    #[test]
    fn test_color_for_size_boundaries() {
        assert_eq!(color_for_size(1024), 46);   // <= 1024
        assert_eq!(color_for_size(1025), 82);   // <= 2048
        assert_eq!(color_for_size(2048), 82);   // <= 2048
        assert_eq!(color_for_size(2049), 118);  // <= 3072
    }

    #[test]
    fn test_color_for_size_large() {
        assert_eq!(color_for_size(524288), 202);  // last threshold
        assert_eq!(color_for_size(524289), 196);  // beyond all → LARGE_FILE_COLOR
        assert_eq!(color_for_size(10_000_000), 196);
    }

    // ---- color_for_age tests ----

    #[test]
    fn test_color_for_age_future() {
        assert_eq!(color_for_age(-1), 196); // future timestamp
    }

    #[test]
    fn test_color_for_age_recent() {
        assert_eq!(color_for_age(0), 255);   // just now (< 60)
        assert_eq!(color_for_age(59), 255);  // still < 60
    }

    #[test]
    fn test_color_for_age_minutes() {
        assert_eq!(color_for_age(60), 252);   // 1 minute (< 3600)
        assert_eq!(color_for_age(3599), 252); // still < 3600
    }

    #[test]
    fn test_color_for_age_hours() {
        assert_eq!(color_for_age(3600), 250);  // 1 hour (< 86400)
    }

    #[test]
    fn test_color_for_age_ancient() {
        assert_eq!(color_for_age(100_000_000), 236); // very old → ANCIENT_TIME_COLOR
    }

    // ---- format_date tests ----

    #[test]
    fn test_format_date_recent() {
        // Recent date (< 6 months) should show HH:MM format
        let now = Local::now().timestamp();
        let date_str = format_date(now, 0);
        // Should contain colon (HH:MM)
        assert!(date_str.contains(':'), "Recent date should contain HH:MM, got: {}", date_str);
    }

    #[test]
    fn test_format_date_old() {
        // Old date (> 6 months) should show year
        let now = Local::now().timestamp();
        let old_time = now - 20_000_000; // ~7.6 months ago
        let date_str = format_date(old_time, 20_000_000);
        // Should contain 4-digit year
        assert!(date_str.contains("20"), "Old date should contain year, got: {}", date_str);
        // Should NOT contain colon
        assert!(!date_str.contains(':'), "Old date should not contain HH:MM, got: {}", date_str);
    }

    // ---- format_vcs_marker tests ----

    #[test]
    fn test_vcs_marker_clean() {
        let m = format_vcs_marker(&VcsStatus::Clean);
        assert!(m.contains('|'), "Clean should be |");
        assert!(m.contains("82"), "Clean should be green (82)");
    }

    #[test]
    fn test_vcs_marker_staged() {
        let m = format_vcs_marker(&VcsStatus::Staged);
        assert!(m.contains('+'), "Staged should be +");
        assert!(m.contains("82"), "Staged should be green (82)");
    }

    #[test]
    fn test_vcs_marker_worktree_changed() {
        let m = format_vcs_marker(&VcsStatus::WorkTreeChanged);
        assert!(m.contains('+'), "WorkTreeChanged should be +");
        assert!(m.contains("196"), "WorkTreeChanged should be red (196)");
    }

    #[test]
    fn test_vcs_marker_both_changed() {
        let m = format_vcs_marker(&VcsStatus::BothChanged);
        assert!(m.contains('+'), "BothChanged should be +");
        assert!(m.contains("214"), "BothChanged should be orange (214)");
    }

    #[test]
    fn test_vcs_marker_dir_changed() {
        let m = format_vcs_marker(&VcsStatus::DirChanged);
        assert!(m.contains('+'), "DirChanged should be +");
        assert!(m.contains("226"), "DirChanged should be yellow (226)");
    }

    #[test]
    fn test_vcs_marker_untracked() {
        let m = format_vcs_marker(&VcsStatus::Untracked);
        assert!(m.contains('?'), "Untracked should be ?");
        assert!(m.contains("196"), "Untracked should be red (196)");
    }

    #[test]
    fn test_vcs_marker_dir_untracked() {
        let m = format_vcs_marker(&VcsStatus::DirUntracked);
        assert!(m.contains('?'), "DirUntracked should be ?");
        assert!(m.contains("226"), "DirUntracked should be yellow (226)");
    }

    #[test]
    fn test_vcs_marker_dir_empty_untracked() {
        let m = format_vcs_marker(&VcsStatus::DirEmptyUntracked);
        assert!(m.contains('?'), "DirEmptyUntracked should be ?");
        assert!(m.contains("238"), "DirEmptyUntracked should be dim (238)");
    }

    #[test]
    fn test_vcs_marker_ignored() {
        let m = format_vcs_marker(&VcsStatus::Ignored);
        assert!(m.contains('|'), "Ignored should be |");
        assert!(m.contains("238"), "Ignored should be dim (238)");
    }

    #[test]
    fn test_vcs_marker_none() {
        let m = format_vcs_marker(&VcsStatus::None);
        assert_eq!(m, "  ", "None should be two spaces");
    }
}
