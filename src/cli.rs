use clap::Parser;
use std::path::PathBuf;

#[derive(Parser, Debug)]
#[command(name = "kk", about = "A git-aware ls replacement", disable_help_flag = true)]
pub struct Args {
    /// List entries starting with .
    #[arg(short = 'a', long = "all")]
    pub all: bool,

    /// List all except . and ..
    #[arg(short = 'A', long = "almost-all")]
    pub almost_all: bool,

    /// Show filesizes in human-readable format
    #[arg(short = 'h', long = "human")]
    pub human: bool,

    /// With -h, use powers of 1000 not 1024
    #[arg(long = "si")]
    pub si: bool,

    /// List only directories
    #[arg(short = 'd', long = "directory")]
    pub directory: bool,

    /// Do not list directories
    #[arg(short = 'n', long = "no-directory")]
    pub no_directory: bool,

    /// Reverse sort order
    #[arg(short = 'r', long = "reverse")]
    pub reverse: bool,

    /// Sort by size
    #[arg(short = 'S')]
    pub sort_size: bool,

    /// Sort by modification time
    #[arg(short = 't')]
    pub sort_time: bool,

    /// Sort by ctime (inode change time)
    #[arg(short = 'c')]
    pub sort_ctime: bool,

    /// Sort by atime (access time)
    #[arg(short = 'u')]
    pub sort_atime: bool,

    /// Unsorted
    #[arg(short = 'U')]
    pub unsorted: bool,

    /// Sort by WORD: none, size, time, ctime, status, atime, access, use
    #[arg(long = "sort")]
    pub sort_word: Option<String>,

    /// Do not get VCS status
    #[arg(long = "no-vcs")]
    pub no_vcs: bool,

    /// Group directories before files
    #[arg(long = "group-directories-first")]
    pub group_dirs: bool,

    /// Print help
    #[arg(long = "help")]
    pub help: bool,

    /// Target paths
    #[arg()]
    pub paths: Vec<PathBuf>,
}

impl Args {
    pub fn validate(&self) -> Result<(), String> {
        if self.directory && self.no_directory {
            return Err("-d/--directory and -n/--no-directory cannot be used together".to_string());
        }
        Ok(())
    }
}
