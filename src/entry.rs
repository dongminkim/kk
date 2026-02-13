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
