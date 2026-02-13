use clap::Parser;
use std::path::PathBuf;

#[derive(Parser, Debug)]
#[command(name = "kk", version, about = "A git-aware ls replacement", disable_help_flag = true)]
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

#[cfg(test)]
mod tests {
    use super::*;

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

    #[test]
    fn test_validate_ok_default() {
        assert!(default_args().validate().is_ok());
    }

    #[test]
    fn test_validate_ok_with_flags() {
        let mut args = default_args();
        args.all = true;
        args.human = true;
        args.reverse = true;
        assert!(args.validate().is_ok());
    }

    #[test]
    fn test_validate_conflicting_directory_flags() {
        let mut args = default_args();
        args.directory = true;
        args.no_directory = true;
        let result = args.validate();
        assert!(result.is_err());
        assert!(result.unwrap_err().contains("cannot be used together"));
    }

    #[test]
    fn test_validate_directory_only() {
        let mut args = default_args();
        args.directory = true;
        assert!(args.validate().is_ok());
    }

    #[test]
    fn test_validate_no_directory_only() {
        let mut args = default_args();
        args.no_directory = true;
        assert!(args.validate().is_ok());
    }

    #[test]
    fn test_parse_version_flag() {
        // clap should handle --version via #[command(version)]
        let result = Args::try_parse_from(["kk", "--version"]);
        // --version causes early exit which is an Err in try_parse
        assert!(result.is_err());
    }

    #[test]
    fn test_parse_flags() {
        let args = Args::try_parse_from(["kk", "-a", "-h", "-r", "-S", "--no-vcs"]).unwrap();
        assert!(args.all);
        assert!(args.human);
        assert!(args.reverse);
        assert!(args.sort_size);
        assert!(args.no_vcs);
    }

    #[test]
    fn test_parse_sort_word() {
        let args = Args::try_parse_from(["kk", "--sort", "time"]).unwrap();
        assert_eq!(args.sort_word, Some("time".to_string()));
    }

    #[test]
    fn test_parse_paths() {
        let args = Args::try_parse_from(["kk", "/tmp", "/var"]).unwrap();
        assert_eq!(args.paths.len(), 2);
        assert_eq!(args.paths[0], PathBuf::from("/tmp"));
        assert_eq!(args.paths[1], PathBuf::from("/var"));
    }
}
