use std::path::Path;
use std::process::Command;
use tempfile::TempDir;

/// Strip ANSI escape codes from a string
fn strip_ansi(s: &str) -> String {
    let mut result = String::new();
    let mut in_escape = false;
    for c in s.chars() {
        if c == '\x1b' {
            in_escape = true;
        } else if in_escape {
            if c == 'm' {
                in_escape = false;
            }
        } else {
            result.push(c);
        }
    }
    result
}

fn kk_binary() -> std::path::PathBuf {
    // Find the binary in target/debug or target/release
    let mut path = std::env::current_exe()
        .unwrap()
        .parent()
        .unwrap()
        .parent()
        .unwrap()
        .to_path_buf();
    path.push("kk");
    path
}

fn run_kk(args: &[&str]) -> (String, String, bool) {
    let output = Command::new(kk_binary())
        .args(args)
        .output()
        .expect("Failed to execute kk");
    let stdout = String::from_utf8_lossy(&output.stdout).to_string();
    let stderr = String::from_utf8_lossy(&output.stderr).to_string();
    (stdout, stderr, output.status.success())
}

fn run_kk_in_dir(dir: &Path, args: &[&str]) -> (String, String, bool) {
    let output = Command::new(kk_binary())
        .args(args)
        .current_dir(dir)
        .output()
        .expect("Failed to execute kk");
    let stdout = String::from_utf8_lossy(&output.stdout).to_string();
    let stderr = String::from_utf8_lossy(&output.stderr).to_string();
    (stdout, stderr, output.status.success())
}

fn git_init(dir: &Path) {
    Command::new("git")
        .args(["init"])
        .current_dir(dir)
        .output()
        .expect("git init failed");
    Command::new("git")
        .args(["config", "user.email", "test@test.com"])
        .current_dir(dir)
        .output()
        .unwrap();
    Command::new("git")
        .args(["config", "user.name", "Test"])
        .current_dir(dir)
        .output()
        .unwrap();
}

fn git_add_commit(dir: &Path, msg: &str) {
    Command::new("git")
        .args(["add", "."])
        .current_dir(dir)
        .output()
        .expect("git add failed");
    Command::new("git")
        .args(["commit", "-m", msg, "--allow-empty"])
        .current_dir(dir)
        .output()
        .expect("git commit failed");
}

// ---- Basic listing tests ----

#[test]
fn test_basic_listing() {
    let dir = TempDir::new().unwrap();
    std::fs::write(dir.path().join("hello.txt"), "hello").unwrap();
    std::fs::write(dir.path().join("world.txt"), "world").unwrap();
    std::fs::create_dir(dir.path().join("subdir")).unwrap();

    let (stdout, _, success) = run_kk(&["--no-vcs", dir.path().to_str().unwrap()]);
    assert!(success);
    assert!(stdout.contains("total"));
    assert!(stdout.contains("hello.txt"));
    assert!(stdout.contains("world.txt"));
    assert!(stdout.contains("subdir"));
}

#[test]
fn test_no_vcs_flag() {
    let dir = TempDir::new().unwrap();
    git_init(dir.path());
    std::fs::write(dir.path().join("file.txt"), "data").unwrap();
    git_add_commit(dir.path(), "initial");

    let (stdout, _, _) = run_kk(&["--no-vcs", dir.path().to_str().unwrap()]);
    // Without VCS, no git markers (|, +, ?) should appear in specific columns
    // The output should still contain the filename
    assert!(stdout.contains("file.txt"));
}

// ---- Hidden files tests ----

#[test]
fn test_hidden_files_not_shown_by_default() {
    let dir = TempDir::new().unwrap();
    std::fs::write(dir.path().join(".hidden"), "hidden").unwrap();
    std::fs::write(dir.path().join("visible"), "visible").unwrap();

    let (stdout, _, _) = run_kk(&["--no-vcs", dir.path().to_str().unwrap()]);
    assert!(stdout.contains("visible"));
    assert!(!stdout.contains(".hidden"));
}

#[test]
fn test_hidden_files_shown_with_a() {
    let dir = TempDir::new().unwrap();
    std::fs::write(dir.path().join(".hidden"), "hidden").unwrap();
    std::fs::write(dir.path().join("visible"), "visible").unwrap();

    let (stdout, _, _) = run_kk(&["-a", "--no-vcs", dir.path().to_str().unwrap()]);
    assert!(stdout.contains("visible"));
    assert!(stdout.contains(".hidden"));
    // -a also shows . and .. (may have ANSI color codes around them)
    let has_dot = stdout.lines().any(|l| {
        let stripped = strip_ansi(l);
        stripped.ends_with(" .")
    });
    let has_dotdot = stdout.lines().any(|l| {
        let stripped = strip_ansi(l);
        stripped.ends_with(" ..")
    });
    assert!(has_dot, "Should show . entry with -a");
    assert!(has_dotdot, "Should show .. entry with -a");
}

#[test]
fn test_almost_all_no_dot_dotdot() {
    let dir = TempDir::new().unwrap();
    std::fs::write(dir.path().join(".hidden"), "hidden").unwrap();

    let (stdout, _, _) = run_kk(&["-A", "--no-vcs", dir.path().to_str().unwrap()]);
    assert!(stdout.contains(".hidden"));
    // -A shows hidden files but NOT . and ..
    // Count lines that end with just " ." (dot entry)
    let has_dot_entry = stdout.lines().any(|l| {
        let trimmed = l.trim();
        trimmed.ends_with(" .") && !trimmed.ends_with("..")  && !trimmed.ends_with(".hidden")
    });
    assert!(!has_dot_entry, "Should not show . entry with -A");
}

// ---- Human readable flag ----

#[test]
fn test_human_readable_flag() {
    let dir = TempDir::new().unwrap();
    // Create a file > 1K
    let data = vec![0u8; 2048];
    std::fs::write(dir.path().join("bigfile"), &data).unwrap();

    let (stdout, _, _) = run_kk(&["-h", "--no-vcs", dir.path().to_str().unwrap()]);
    assert!(stdout.contains("bigfile"));
    // Should have K suffix in the size column
    assert!(stdout.contains("K"), "Expected K suffix in human readable output");
}

// ---- Sort tests ----

#[test]
fn test_sort_by_size() {
    let dir = TempDir::new().unwrap();
    std::fs::write(dir.path().join("small"), "a").unwrap();
    std::fs::write(dir.path().join("big"), &vec![0u8; 10000]).unwrap();

    let (stdout, _, _) = run_kk(&["-S", "--no-vcs", dir.path().to_str().unwrap()]);
    let lines: Vec<&str> = stdout.lines().filter(|l| !l.starts_with("total")).collect();
    // big should come before small (sorted by size, largest first)
    let big_pos = lines.iter().position(|l| l.contains("big")).unwrap();
    let small_pos = lines.iter().position(|l| l.contains("small")).unwrap();
    assert!(big_pos < small_pos, "big should appear before small when sorted by size");
}

#[test]
fn test_reverse_sort() {
    let dir = TempDir::new().unwrap();
    std::fs::write(dir.path().join("aaa"), "a").unwrap();
    std::fs::write(dir.path().join("zzz"), "z").unwrap();

    let (stdout, _, _) = run_kk(&["-r", "--no-vcs", dir.path().to_str().unwrap()]);
    let lines: Vec<&str> = stdout.lines().filter(|l| !l.starts_with("total")).collect();
    let a_pos = lines.iter().position(|l| l.contains("aaa")).unwrap();
    let z_pos = lines.iter().position(|l| l.contains("zzz")).unwrap();
    assert!(z_pos < a_pos, "zzz should come before aaa when reversed");
}

// ---- Directory filter tests ----

#[test]
fn test_directory_only() {
    let dir = TempDir::new().unwrap();
    std::fs::write(dir.path().join("file.txt"), "data").unwrap();
    std::fs::create_dir(dir.path().join("subdir")).unwrap();

    // -d without explicit path lists only directory entries within CWD
    let (stdout, _, _) = run_kk_in_dir(dir.path(), &["-d", "--no-vcs"]);
    assert!(stdout.contains("subdir"));
    assert!(!stdout.contains("file.txt"), "Should not show files with -d");
}

#[test]
fn test_no_directory() {
    let dir = TempDir::new().unwrap();
    std::fs::write(dir.path().join("file.txt"), "data").unwrap();
    std::fs::create_dir(dir.path().join("subdir")).unwrap();

    let (stdout, _, _) = run_kk(&["-n", "--no-vcs", dir.path().to_str().unwrap()]);
    assert!(stdout.contains("file.txt"));
    assert!(!stdout.contains("subdir"), "Should not show directories with -n");
}

// ---- Version flag ----

#[test]
fn test_version_flag() {
    let output = Command::new(kk_binary())
        .arg("--version")
        .output()
        .expect("Failed to execute kk --version");
    let stdout = String::from_utf8_lossy(&output.stdout).to_string();
    assert!(stdout.contains("kk"), "Version output should contain 'kk'");
    assert!(stdout.contains("0."), "Version output should contain version number");
}

// ---- Error handling ----

#[test]
fn test_nonexistent_path() {
    let (_, stderr, success) = run_kk(&["/nonexistent/path/xyz123"]);
    assert!(!success || stderr.contains("cannot access"));
}

#[test]
fn test_conflicting_flags() {
    let (_, stderr, success) = run_kk(&["-d", "-n", "."]);
    assert!(!success);
    assert!(stderr.contains("cannot be used together"));
}

// ---- Git status marker integration tests ----

#[test]
fn test_git_tracked_file_shows_clean_marker() {
    let dir = TempDir::new().unwrap();
    git_init(dir.path());
    std::fs::write(dir.path().join("tracked.txt"), "data").unwrap();
    git_add_commit(dir.path(), "add tracked file");

    let (stdout, _, _) = run_kk_in_dir(dir.path(), &["."]);
    // Clean tracked file should have | marker (green)
    let line = stdout.lines().find(|l| l.contains("tracked.txt")).unwrap();
    assert!(line.contains('|'), "Tracked clean file should have | marker, got: {}", line);
}

#[test]
fn test_git_untracked_file_shows_question_marker() {
    let dir = TempDir::new().unwrap();
    git_init(dir.path());
    // Create initial commit so HEAD exists
    std::fs::write(dir.path().join("init.txt"), "init").unwrap();
    git_add_commit(dir.path(), "initial");
    // Now create an untracked file
    std::fs::write(dir.path().join("untracked.txt"), "new").unwrap();

    let (stdout, _, _) = run_kk_in_dir(dir.path(), &["."]);
    let line = stdout.lines().find(|l| l.contains("untracked.txt")).unwrap();
    assert!(line.contains('?'), "Untracked file should have ? marker, got: {}", line);
}

#[test]
fn test_git_modified_file_shows_plus_marker() {
    let dir = TempDir::new().unwrap();
    git_init(dir.path());
    std::fs::write(dir.path().join("file.txt"), "original").unwrap();
    git_add_commit(dir.path(), "initial");
    // Modify the file
    std::fs::write(dir.path().join("file.txt"), "modified").unwrap();

    let (stdout, _, _) = run_kk_in_dir(dir.path(), &["."]);
    let line = stdout.lines().find(|l| l.contains("file.txt")).unwrap();
    assert!(line.contains('+'), "Modified file should have + marker, got: {}", line);
}

#[test]
fn test_git_staged_file_shows_plus_marker() {
    let dir = TempDir::new().unwrap();
    git_init(dir.path());
    std::fs::write(dir.path().join("file.txt"), "original").unwrap();
    git_add_commit(dir.path(), "initial");
    // Modify and stage
    std::fs::write(dir.path().join("file.txt"), "staged").unwrap();
    Command::new("git")
        .args(["add", "file.txt"])
        .current_dir(dir.path())
        .output()
        .unwrap();

    let (stdout, _, _) = run_kk_in_dir(dir.path(), &["."]);
    let line = stdout.lines().find(|l| l.contains("file.txt")).unwrap();
    assert!(line.contains('+'), "Staged file should have + marker, got: {}", line);
}

#[test]
fn test_git_ignored_file() {
    let dir = TempDir::new().unwrap();
    git_init(dir.path());
    std::fs::write(dir.path().join(".gitignore"), "ignored.txt\n").unwrap();
    std::fs::write(dir.path().join("ignored.txt"), "ignored").unwrap();
    std::fs::write(dir.path().join("tracked.txt"), "tracked").unwrap();
    git_add_commit(dir.path(), "initial");

    let (stdout, _, _) = run_kk_in_dir(dir.path(), &["-a", "."]);
    let ignored_line = stdout.lines().find(|l| l.contains("ignored.txt")).unwrap();
    // Ignored file should have | marker (dim)
    assert!(ignored_line.contains('|'), "Ignored file should have | marker, got: {}", ignored_line);
}

#[test]
fn test_git_dir_with_untracked_shows_dir_untracked() {
    let dir = TempDir::new().unwrap();
    git_init(dir.path());
    std::fs::write(dir.path().join("init.txt"), "init").unwrap();
    git_add_commit(dir.path(), "initial");
    // Create subdirectory with untracked file
    std::fs::create_dir(dir.path().join("subdir")).unwrap();
    std::fs::write(dir.path().join("subdir/new.txt"), "new").unwrap();

    let (stdout, _, _) = run_kk_in_dir(dir.path(), &["."]);
    let line = stdout.lines().find(|l| l.contains("subdir")).unwrap();
    assert!(line.contains('?'), "Dir with untracked should have ? marker, got: {}", line);
}

#[test]
fn test_git_dir_with_modified_shows_dir_changed() {
    let dir = TempDir::new().unwrap();
    git_init(dir.path());
    std::fs::create_dir(dir.path().join("subdir")).unwrap();
    std::fs::write(dir.path().join("subdir/file.txt"), "original").unwrap();
    git_add_commit(dir.path(), "initial");
    // Modify the file
    std::fs::write(dir.path().join("subdir/file.txt"), "modified").unwrap();

    let (stdout, _, _) = run_kk_in_dir(dir.path(), &["."]);
    let line = stdout.lines().find(|l| l.contains("subdir")).unwrap();
    assert!(line.contains('+'), "Dir with modified file should have + marker, got: {}", line);
}

// ---- Ignored dir with tracked file ----

#[test]
fn test_ignored_dir_with_tracked_file() {
    let dir = TempDir::new().unwrap();
    git_init(dir.path());
    // Create .gitignore that ignores mydir/
    std::fs::write(dir.path().join(".gitignore"), "mydir/\n").unwrap();
    std::fs::create_dir(dir.path().join("mydir")).unwrap();
    std::fs::write(dir.path().join("mydir/config"), "tracked config").unwrap();
    // Force-add the file inside ignored dir
    Command::new("git")
        .args(["add", "-f", "mydir/config"])
        .current_dir(dir.path())
        .output()
        .unwrap();
    Command::new("git")
        .args(["add", ".gitignore"])
        .current_dir(dir.path())
        .output()
        .unwrap();
    git_add_commit(dir.path(), "add ignored dir with tracked file");

    let (stdout, _, _) = run_kk_in_dir(dir.path(), &["."]);
    let line = stdout.lines().find(|l| l.contains("mydir")).unwrap();
    // mydir should show as Clean (has tracked clean file), not Ignored
    assert!(line.contains('|'), "Ignored dir with tracked file should show | (clean), got: {}", line);
}

// ---- Empty untracked dir ----

#[test]
fn test_empty_untracked_dir() {
    let dir = TempDir::new().unwrap();
    git_init(dir.path());
    std::fs::write(dir.path().join("init.txt"), "init").unwrap();
    git_add_commit(dir.path(), "initial");
    // Create empty directory
    std::fs::create_dir(dir.path().join("empty_dir")).unwrap();

    let (stdout, _, _) = run_kk_in_dir(dir.path(), &["."]);
    let line = stdout.lines().find(|l| l.contains("empty_dir")).unwrap();
    // Empty untracked dir should have ? marker (dim)
    assert!(line.contains('?'), "Empty untracked dir should have ? marker, got: {}", line);
}

// ---- Dot entry aggregation ----

#[test]
fn test_dot_entry_aggregates_status() {
    let dir = TempDir::new().unwrap();
    git_init(dir.path());
    std::fs::write(dir.path().join("file.txt"), "data").unwrap();
    git_add_commit(dir.path(), "initial");
    // Add an untracked file
    std::fs::write(dir.path().join("new.txt"), "new").unwrap();

    let (stdout, _, _) = run_kk_in_dir(dir.path(), &["-a", "."]);
    // Find the . entry (not .gitignore, not ..)
    let dot_line = stdout.lines().find(|l| {
        let trimmed = l.trim();
        trimmed.ends_with(" .") || trimmed.ends_with("\x1b[0m .")
    });
    if let Some(line) = dot_line {
        // . should show ? (DirUntracked) because there's an untracked file
        assert!(line.contains('?'), ". should aggregate to untracked marker, got: {}", line);
    }
}

#[test]
fn test_dot_entry_clean_when_all_tracked() {
    let dir = TempDir::new().unwrap();
    git_init(dir.path());
    std::fs::write(dir.path().join("file.txt"), "data").unwrap();
    git_add_commit(dir.path(), "initial");

    let (stdout, _, _) = run_kk_in_dir(dir.path(), &["-a", "."]);
    let dot_line = stdout.lines().find(|l| {
        let trimmed = l.trim();
        trimmed.ends_with(" .") || trimmed.ends_with("\x1b[0m .")
    });
    if let Some(line) = dot_line {
        assert!(line.contains('|'), ". should be clean when all files tracked, got: {}", line);
    }
}

// ---- Multiple directories ----

#[test]
fn test_multiple_directories() {
    let dir1 = TempDir::new().unwrap();
    let dir2 = TempDir::new().unwrap();
    std::fs::write(dir1.path().join("a.txt"), "a").unwrap();
    std::fs::write(dir2.path().join("b.txt"), "b").unwrap();

    let (stdout, _, success) = run_kk(&[
        "--no-vcs",
        dir1.path().to_str().unwrap(),
        dir2.path().to_str().unwrap(),
    ]);
    assert!(success);
    assert!(stdout.contains("a.txt"));
    assert!(stdout.contains("b.txt"));
    // Should have directory headers
    assert!(stdout.contains(':'));
}

// ---- Group directories first ----

#[test]
fn test_group_directories_first() {
    let dir = TempDir::new().unwrap();
    std::fs::write(dir.path().join("aaa_file"), "data").unwrap();
    std::fs::create_dir(dir.path().join("zzz_dir")).unwrap();

    let (stdout, _, _) = run_kk(&["--group-directories-first", "--no-vcs", dir.path().to_str().unwrap()]);
    let lines: Vec<&str> = stdout.lines().filter(|l| !l.starts_with("total")).collect();
    let dir_pos = lines.iter().position(|l| l.contains("zzz_dir")).unwrap();
    let file_pos = lines.iter().position(|l| l.contains("aaa_file")).unwrap();
    assert!(dir_pos < file_pos, "Directories should come first with --group-directories-first");
}

// ---- SI mode ----

#[test]
fn test_si_mode() {
    let dir = TempDir::new().unwrap();
    let data = vec![0u8; 2000];
    std::fs::write(dir.path().join("file"), &data).unwrap();

    let (stdout, _, _) = run_kk(&["-h", "--si", "--no-vcs", dir.path().to_str().unwrap()]);
    assert!(stdout.contains("file"));
    assert!(stdout.contains("K"), "Expected K suffix with --si");
}

// ---- Empty directory ----

#[test]
fn test_empty_directory() {
    let dir = TempDir::new().unwrap();
    // Empty dir (no files)
    let (stdout, _, success) = run_kk(&["--no-vcs", dir.path().to_str().unwrap()]);
    assert!(success);
    assert!(stdout.contains("total 0"));
}

// ---- Sort by time ----

#[test]
fn test_sort_by_time() {
    let dir = TempDir::new().unwrap();
    std::fs::write(dir.path().join("old.txt"), "old").unwrap();
    // Sleep to ensure different mtime (1s for HFS+ / APFS second granularity)
    std::thread::sleep(std::time::Duration::from_secs(1));
    std::fs::write(dir.path().join("new.txt"), "new").unwrap();

    let (stdout, _, _) = run_kk(&["-t", "--no-vcs", dir.path().to_str().unwrap()]);
    let lines: Vec<&str> = stdout.lines().filter(|l| !l.starts_with("total")).collect();
    let new_pos = lines.iter().position(|l| l.contains("new.txt")).unwrap();
    let old_pos = lines.iter().position(|l| l.contains("old.txt")).unwrap();
    assert!(new_pos < old_pos, "Newer file should come first with -t sort");
}
