use crate::entry::FileEntry;

pub struct FileColors {
    pub di: String, // directory
    pub ln: String, // symlink
    pub so: String, // socket
    pub pi: String, // pipe
    pub ex: String, // executable
    pub bd: String, // block device
    pub cd: String, // character device
    pub su: String, // setuid
    pub sg: String, // setgid
    pub tw: String, // sticky + world-writable
    pub ow: String, // world-writable
}

impl FileColors {
    pub fn new() -> Self {
        let mut colors = FileColors {
            di: "0;34".to_string(),
            ln: "0;35".to_string(),
            so: "0;32".to_string(),
            pi: "0;33".to_string(),
            ex: "0;31".to_string(),
            bd: "34;46".to_string(),
            cd: "34;43".to_string(),
            su: "30;41".to_string(),
            sg: "30;46".to_string(),
            tw: "30;42".to_string(),
            ow: "30;43".to_string(),
        };

        // On macOS, parse LSCOLORS if available
        if cfg!(target_os = "macos") {
            if let Ok(lscolors) = std::env::var("LSCOLORS") {
                let chars: Vec<char> = lscolors.chars().collect();
                if chars.len() >= 22 {
                    colors.di = bsd_to_ansi(chars[0], chars[1]);
                    colors.ln = bsd_to_ansi(chars[2], chars[3]);
                    colors.so = bsd_to_ansi(chars[4], chars[5]);
                    colors.pi = bsd_to_ansi(chars[6], chars[7]);
                    colors.ex = bsd_to_ansi(chars[8], chars[9]);
                    colors.bd = bsd_to_ansi(chars[10], chars[11]);
                    colors.cd = bsd_to_ansi(chars[12], chars[13]);
                    colors.su = bsd_to_ansi(chars[14], chars[15]);
                    colors.sg = bsd_to_ansi(chars[16], chars[17]);
                    colors.tw = bsd_to_ansi(chars[18], chars[19]);
                    colors.ow = bsd_to_ansi(chars[20], chars[21]);
                }
            }
        }

        colors
    }

    /// Returns the ANSI color code for a file entry, or None for regular files.
    pub fn color_for(&self, entry: &FileEntry) -> Option<&str> {
        let mode = entry.mode;
        let ft = mode & libc::S_IFMT as u32;

        if ft == libc::S_IFDIR as u32 {
            // Check world-writable + sticky
            if mode & 0o002 != 0 {
                if mode & libc::S_ISVTX as u32 != 0 {
                    return Some(&self.tw);
                }
                return Some(&self.ow);
            }
            return Some(&self.di);
        }
        if ft == libc::S_IFLNK as u32 {
            return Some(&self.ln);
        }
        if ft == libc::S_IFSOCK as u32 {
            return Some(&self.so);
        }
        if ft == libc::S_IFIFO as u32 {
            return Some(&self.pi);
        }
        // setuid
        if mode & libc::S_ISUID as u32 != 0 {
            return Some(&self.su);
        }
        // setgid
        if mode & libc::S_ISGID as u32 != 0 {
            return Some(&self.sg);
        }
        // executable
        if mode & 0o111 != 0 && ft == libc::S_IFREG as u32 {
            return Some(&self.ex);
        }
        if ft == libc::S_IFBLK as u32 {
            return Some(&self.bd);
        }
        if ft == libc::S_IFCHR as u32 {
            return Some(&self.cd);
        }

        None
    }
}

/// Convert BSD LSCOLORS letter pair to ANSI color codes
fn bsd_to_ansi(foreground: char, background: char) -> String {
    let fg = match foreground.to_ascii_lowercase() {
        'a' => "30",
        'b' => "31",
        'c' => "32",
        'd' => "33",
        'e' => "34",
        'f' => "35",
        'g' => "36",
        'h' => "37",
        'x' => "0",
        _ => "0",
    };
    let bg = match background.to_ascii_lowercase() {
        'a' => "40",
        'b' => "41",
        'c' => "42",
        'd' => "43",
        'e' => "44",
        'f' => "45",
        'g' => "46",
        'h' => "47",
        'x' => "0",
        _ => "0",
    };
    format!("{};{}", bg, fg)
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::path::PathBuf;

    fn make_entry_with_mode(mode: u32) -> FileEntry {
        FileEntry {
            path: PathBuf::from("test"),
            display_name: "test".to_string(),
            metadata: std::fs::symlink_metadata("/").unwrap(), // dummy
            mode,
            nlinks: 1,
            owner: "user".to_string(),
            group: "staff".to_string(),
            size: 0,
            mtime: 0,
            atime: 0,
            ctime: 0,
            blocks: 0,
            symlink_target: None,
            permission_string: "----------".to_string(),
        }
    }

    // ---- bsd_to_ansi tests ----

    #[test]
    fn test_bsd_to_ansi_blue_fg_default_bg() {
        // 'e' = blue (34), 'x' = default (0)
        assert_eq!(bsd_to_ansi('e', 'x'), "0;34");
    }

    #[test]
    fn test_bsd_to_ansi_red_fg_green_bg() {
        // 'b' = red (31), 'c' = green bg (42)
        assert_eq!(bsd_to_ansi('b', 'c'), "42;31");
    }

    #[test]
    fn test_bsd_to_ansi_default_both() {
        assert_eq!(bsd_to_ansi('x', 'x'), "0;0");
    }

    #[test]
    fn test_bsd_to_ansi_all_colors() {
        assert_eq!(bsd_to_ansi('a', 'x'), "0;30");  // black
        assert_eq!(bsd_to_ansi('b', 'x'), "0;31");  // red
        assert_eq!(bsd_to_ansi('c', 'x'), "0;32");  // green
        assert_eq!(bsd_to_ansi('d', 'x'), "0;33");  // yellow
        assert_eq!(bsd_to_ansi('e', 'x'), "0;34");  // blue
        assert_eq!(bsd_to_ansi('f', 'x'), "0;35");  // magenta
        assert_eq!(bsd_to_ansi('g', 'x'), "0;36");  // cyan
        assert_eq!(bsd_to_ansi('h', 'x'), "0;37");  // white
    }

    #[test]
    fn test_bsd_to_ansi_all_bg_colors() {
        assert_eq!(bsd_to_ansi('x', 'a'), "40;0");  // black bg
        assert_eq!(bsd_to_ansi('x', 'b'), "41;0");  // red bg
        assert_eq!(bsd_to_ansi('x', 'c'), "42;0");  // green bg
        assert_eq!(bsd_to_ansi('x', 'd'), "43;0");  // yellow bg
        assert_eq!(bsd_to_ansi('x', 'e'), "44;0");  // blue bg
        assert_eq!(bsd_to_ansi('x', 'f'), "45;0");  // magenta bg
        assert_eq!(bsd_to_ansi('x', 'g'), "46;0");  // cyan bg
        assert_eq!(bsd_to_ansi('x', 'h'), "47;0");  // white bg
    }

    #[test]
    fn test_bsd_to_ansi_uppercase() {
        // Uppercase should work the same (to_ascii_lowercase)
        assert_eq!(bsd_to_ansi('E', 'X'), "0;34");
    }

    #[test]
    fn test_bsd_to_ansi_unknown_defaults() {
        assert_eq!(bsd_to_ansi('z', 'z'), "0;0"); // unknown → default
    }

    // ---- color_for tests ----

    #[test]
    fn test_color_for_directory() {
        let colors = FileColors::new();
        let entry = make_entry_with_mode(libc::S_IFDIR as u32 | 0o755);
        assert_eq!(colors.color_for(&entry), Some(colors.di.as_str()));
    }

    #[test]
    fn test_color_for_symlink() {
        let colors = FileColors::new();
        let entry = make_entry_with_mode(libc::S_IFLNK as u32 | 0o777);
        assert_eq!(colors.color_for(&entry), Some(colors.ln.as_str()));
    }

    #[test]
    fn test_color_for_socket() {
        let colors = FileColors::new();
        let entry = make_entry_with_mode(libc::S_IFSOCK as u32 | 0o755);
        assert_eq!(colors.color_for(&entry), Some(colors.so.as_str()));
    }

    #[test]
    fn test_color_for_fifo() {
        let colors = FileColors::new();
        let entry = make_entry_with_mode(libc::S_IFIFO as u32 | 0o644);
        assert_eq!(colors.color_for(&entry), Some(colors.pi.as_str()));
    }

    #[test]
    fn test_color_for_executable() {
        let colors = FileColors::new();
        let entry = make_entry_with_mode(libc::S_IFREG as u32 | 0o755);
        assert_eq!(colors.color_for(&entry), Some(colors.ex.as_str()));
    }

    #[test]
    fn test_color_for_regular_file() {
        let colors = FileColors::new();
        let entry = make_entry_with_mode(libc::S_IFREG as u32 | 0o644);
        assert_eq!(colors.color_for(&entry), None);
    }

    #[test]
    fn test_color_for_setuid() {
        let colors = FileColors::new();
        let entry = make_entry_with_mode(libc::S_IFREG as u32 | libc::S_ISUID as u32 | 0o755);
        assert_eq!(colors.color_for(&entry), Some(colors.su.as_str()));
    }

    #[test]
    fn test_color_for_setgid() {
        let colors = FileColors::new();
        let entry = make_entry_with_mode(libc::S_IFREG as u32 | libc::S_ISGID as u32 | 0o755);
        assert_eq!(colors.color_for(&entry), Some(colors.sg.as_str()));
    }

    #[test]
    fn test_color_for_world_writable_dir() {
        let colors = FileColors::new();
        let entry = make_entry_with_mode(libc::S_IFDIR as u32 | 0o777);
        assert_eq!(colors.color_for(&entry), Some(colors.ow.as_str()));
    }

    #[test]
    fn test_color_for_sticky_world_writable_dir() {
        let colors = FileColors::new();
        let entry = make_entry_with_mode(libc::S_IFDIR as u32 | libc::S_ISVTX as u32 | 0o777);
        assert_eq!(colors.color_for(&entry), Some(colors.tw.as_str()));
    }

    #[test]
    fn test_color_for_block_device() {
        let colors = FileColors::new();
        let entry = make_entry_with_mode(libc::S_IFBLK as u32 | 0o660);
        assert_eq!(colors.color_for(&entry), Some(colors.bd.as_str()));
    }

    #[test]
    fn test_color_for_char_device() {
        let colors = FileColors::new();
        let entry = make_entry_with_mode(libc::S_IFCHR as u32 | 0o660);
        assert_eq!(colors.color_for(&entry), Some(colors.cd.as_str()));
    }
}
