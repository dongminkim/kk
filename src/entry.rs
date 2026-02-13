use std::fs;
use std::os::unix::fs::MetadataExt;
use std::path::{Path, PathBuf};

#[allow(dead_code)]
pub struct FileEntry {
    pub path: PathBuf,
    pub display_name: String,
    pub metadata: fs::Metadata,
    pub mode: u32,
    pub nlinks: u64,
    pub owner: String,
    pub group: String,
    pub size: u64,
    pub mtime: i64,
    pub atime: i64,
    pub ctime: i64,
    pub blocks: u64,
    pub symlink_target: Option<String>,
    pub permission_string: String,
}

impl FileEntry {
    pub fn from_path(path: &Path) -> Option<FileEntry> {
        let metadata = fs::symlink_metadata(path).ok()?;
        let mode = metadata.mode();
        let nlinks = metadata.nlink();
        let uid = metadata.uid();
        let gid = metadata.gid();
        let size = metadata.size();
        let mtime = metadata.mtime();
        let atime = metadata.atime();
        let ctime = metadata.ctime();
        let blocks = metadata.blocks();

        let owner = uzers::get_user_by_uid(uid)
            .map(|u| u.name().to_string_lossy().into_owned())
            .unwrap_or_else(|| uid.to_string());
        let group = uzers::get_group_by_gid(gid)
            .map(|g| g.name().to_string_lossy().into_owned())
            .unwrap_or_else(|| gid.to_string());

        let symlink_target = if metadata.file_type().is_symlink() {
            fs::read_link(path)
                .ok()
                .map(|t| t.to_string_lossy().into_owned())
        } else {
            None
        };

        let display_name = path
            .file_name()
            .map(|n| n.to_string_lossy().into_owned())
            .unwrap_or_else(|| {
                // Handle "." and ".." by extracting the last component
                path.to_string_lossy().into_owned()
            });

        let permission_string = format_permissions(mode, &metadata);

        Some(FileEntry {
            path: path.to_path_buf(),
            display_name,
            metadata,
            mode,
            nlinks,
            owner,
            group,
            size,
            mtime,
            atime,
            ctime,
            blocks,
            symlink_target,
            permission_string,
        })
    }

    pub fn is_dir(&self) -> bool {
        // For symlinks, check the mode bits directly
        (self.mode & libc::S_IFMT as u32) == libc::S_IFDIR as u32
    }

    #[allow(dead_code)]
    pub fn is_executable(&self) -> bool {
        self.mode & 0o111 != 0
    }
}

fn format_permissions(mode: u32, metadata: &fs::Metadata) -> String {
    let file_type = match mode & libc::S_IFMT as u32 {
        m if m == libc::S_IFDIR as u32 => 'd',
        m if m == libc::S_IFLNK as u32 => 'l',
        m if m == libc::S_IFBLK as u32 => 'b',
        m if m == libc::S_IFCHR as u32 => 'c',
        m if m == libc::S_IFIFO as u32 => 'p',
        m if m == libc::S_IFSOCK as u32 => 's',
        _ => '-',
    };

    let mut perms = String::with_capacity(10);
    perms.push(file_type);

    // Owner
    perms.push(if mode & 0o400 != 0 { 'r' } else { '-' });
    perms.push(if mode & 0o200 != 0 { 'w' } else { '-' });
    perms.push(if mode & libc::S_ISUID as u32 != 0 {
        if mode & 0o100 != 0 { 's' } else { 'S' }
    } else if mode & 0o100 != 0 {
        'x'
    } else {
        '-'
    });

    // Group
    perms.push(if mode & 0o040 != 0 { 'r' } else { '-' });
    perms.push(if mode & 0o020 != 0 { 'w' } else { '-' });
    perms.push(if mode & libc::S_ISGID as u32 != 0 {
        if mode & 0o010 != 0 { 's' } else { 'S' }
    } else if mode & 0o010 != 0 {
        'x'
    } else {
        '-'
    });

    // Other
    perms.push(if mode & 0o004 != 0 { 'r' } else { '-' });
    perms.push(if mode & 0o002 != 0 { 'w' } else { '-' });
    perms.push(if mode & libc::S_ISVTX as u32 != 0 {
        if mode & 0o001 != 0 { 't' } else { 'T' }
    } else if mode & 0o001 != 0 {
        'x'
    } else {
        '-'
    });

    // Extended attributes marker
    let _ = metadata; // Could check xattr here
    perms
}

#[cfg(test)]
mod tests {
    use super::*;

    // Helper: create a dummy metadata for format_permissions testing
    fn perm_str(mode: u32) -> String {
        // We need a real Metadata for format_permissions, get one from /
        let metadata = fs::symlink_metadata("/").unwrap();
        format_permissions(mode, &metadata)
    }

    // ---- format_permissions tests ----

    #[test]
    fn test_permissions_regular_644() {
        assert_eq!(perm_str(0o100644), "-rw-r--r--");
    }

    #[test]
    fn test_permissions_regular_755() {
        assert_eq!(perm_str(0o100755), "-rwxr-xr-x");
    }

    #[test]
    fn test_permissions_directory_755() {
        assert_eq!(perm_str(0o040755), "drwxr-xr-x");
    }

    #[test]
    fn test_permissions_symlink() {
        assert_eq!(perm_str(0o120777), "lrwxrwxrwx");
    }

    #[test]
    fn test_permissions_no_perms() {
        assert_eq!(perm_str(0o100000), "----------");
    }

    #[test]
    fn test_permissions_all_perms() {
        assert_eq!(perm_str(0o100777), "-rwxrwxrwx");
    }

    #[test]
    fn test_permissions_setuid_with_exec() {
        // setuid + owner execute → 's'
        assert_eq!(perm_str(0o104755), "-rwsr-xr-x");
    }

    #[test]
    fn test_permissions_setuid_without_exec() {
        // setuid without owner execute → 'S'
        assert_eq!(perm_str(0o104644), "-rwSr--r--");
    }

    #[test]
    fn test_permissions_setgid_with_exec() {
        // setgid + group execute → 's'
        assert_eq!(perm_str(0o102755), "-rwxr-sr-x");
    }

    #[test]
    fn test_permissions_setgid_without_exec() {
        // setgid without group execute → 'S'
        assert_eq!(perm_str(0o102644), "-rw-r-Sr--");
    }

    #[test]
    fn test_permissions_sticky_with_exec() {
        // sticky + other execute → 't'
        assert_eq!(perm_str(0o041755), "drwxr-xr-t");
    }

    #[test]
    fn test_permissions_sticky_without_exec() {
        // sticky without other execute → 'T'
        assert_eq!(perm_str(0o041754), "drwxr-xr-T");
    }

    #[test]
    fn test_permissions_block_device() {
        assert_eq!(&perm_str(0o060660)[..1], "b");
    }

    #[test]
    fn test_permissions_char_device() {
        assert_eq!(&perm_str(0o020660)[..1], "c");
    }

    #[test]
    fn test_permissions_fifo() {
        assert_eq!(&perm_str(0o010644)[..1], "p");
    }

    #[test]
    fn test_permissions_socket() {
        assert_eq!(&perm_str(0o140755)[..1], "s");
    }

    // ---- is_dir tests ----

    #[test]
    fn test_is_dir_true() {
        // /usr is a real directory (not a symlink) on macOS
        let entry = FileEntry::from_path(Path::new("/usr")).unwrap();
        assert!(entry.is_dir());
    }

    #[test]
    fn test_is_dir_false_for_file() {
        let entry = FileEntry::from_path(Path::new("/etc/hosts")).unwrap();
        assert!(!entry.is_dir());
    }

    // ---- is_executable tests ----

    #[test]
    fn test_is_executable_for_dir() {
        // Directories have execute bit set
        let entry = FileEntry::from_path(Path::new("/tmp")).unwrap();
        assert!(entry.is_executable());
    }

    // ---- from_path tests ----

    #[test]
    fn test_from_path_nonexistent() {
        assert!(FileEntry::from_path(Path::new("/nonexistent_path_xyz")).is_none());
    }

    #[test]
    fn test_from_path_valid() {
        let entry = FileEntry::from_path(Path::new("/tmp"));
        assert!(entry.is_some());
        let entry = entry.unwrap();
        assert!(!entry.display_name.is_empty());
        assert!(entry.nlinks > 0);
    }
}
