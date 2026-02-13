use git2::{Repository, StatusOptions, Status};
use std::collections::HashMap;
use std::path::Path;

#[derive(Debug, Clone, PartialEq)]
pub enum VcsStatus {
    Clean,          // "==" tracked, not modified
    DirChanged,     // "//" changes inside directory
    Ignored,        // "!!" ignored
    Untracked,      // "??" untracked
    Staged,         // index modified, work tree clean
    WorkTreeChanged,// index clean, work tree modified
    BothChanged,    // both index and work tree changed
    None,           // outside repository
}

pub fn collect_vcs_status(
    dir: &Path,
    show_all: bool,
    almost_all: bool,
    no_directory: bool,
) -> Option<HashMap<String, VcsStatus>> {
    let repo = Repository::discover(dir).ok()?;
    let workdir = repo.workdir()?.to_path_buf();

    let mut opts = StatusOptions::new();
    opts.include_untracked(true);
    opts.include_ignored(true);
    opts.recurse_untracked_dirs(true);
    opts.recurse_ignored_dirs(false);

    let statuses = repo.statuses(Some(&mut opts)).ok()?;

    // Canonical absolute path for the directory we're listing
    let abs_dir = std::fs::canonicalize(dir).ok()?;

    let mut result: HashMap<String, VcsStatus> = HashMap::new();
    let mut has_changes = false;

    for status_entry in statuses.iter() {
        let path_str = match status_entry.path() {
            Some(p) => p.to_string(),
            None => continue,
        };

        let status = status_entry.status();
        let full_path = workdir.join(&path_str);

        // Determine relative path from the listed directory
        let rel = match full_path.strip_prefix(&abs_dir) {
            Ok(r) => r,
            Err(_) => continue,
        };

        // Get the first component (file or directory name at depth 1)
        let first_component = match rel.components().next() {
            Some(c) => c.as_os_str().to_string_lossy().into_owned(),
            None => continue,
        };

        let vcs = git2_status_to_vcs(status);

        // If the file is deeper than 1 level, propagate status to directory
        let component_count = rel.components().count();
        if component_count > 1 {
            if matches!(vcs, VcsStatus::Ignored) {
                // Ignored files: mark directory as ignored if no other status
                result.entry(first_component.clone()).or_insert(VcsStatus::Ignored);
            } else if matches!(vcs, VcsStatus::Untracked) {
                // Untracked files: mark directory as untracked if no other status
                let existing = result.get(&first_component);
                if existing.is_none() || matches!(existing, Some(VcsStatus::Ignored)) {
                    result.insert(first_component.clone(), VcsStatus::Untracked);
                }
            } else {
                // Modified/staged/etc: propagate as DirChanged
                let existing = result.get(&first_component);
                if existing.is_none()
                    || matches!(
                        existing,
                        Some(VcsStatus::Clean)
                            | Some(VcsStatus::None)
                            | Some(VcsStatus::Ignored)
                            | Some(VcsStatus::Untracked)
                    )
                {
                    result.insert(first_component.clone(), VcsStatus::DirChanged);
                }
                has_changes = true;
            }
        } else {
            result.insert(first_component.clone(), vcs.clone());
            if !matches!(vcs, VcsStatus::Ignored | VcsStatus::Untracked) {
                has_changes = true;
            }
        }
    }

    // Mark tracked files that have no status as Clean
    // Walk the tree at HEAD to find all tracked files
    if let Ok(head) = repo.head() {
        if let Some(tree) = head.peel_to_tree().ok() {
            mark_tracked_clean(&repo, &tree, &workdir, &abs_dir, &mut result);
        }
    }

    // Handle . and .. for -a flag
    if show_all && !almost_all && !no_directory {
        if has_changes {
            result.entry(".".to_string()).or_insert(VcsStatus::DirChanged);
            // Check if we're in a subdirectory of the repo
            if abs_dir != workdir.canonicalize().unwrap_or(workdir.clone()) {
                result.entry("..".to_string()).or_insert(VcsStatus::DirChanged);
            }
        }
    }

    Some(result)
}

fn mark_tracked_clean(
    _repo: &Repository,
    tree: &git2::Tree,
    workdir: &Path,
    abs_dir: &Path,
    result: &mut HashMap<String, VcsStatus>,
) {
    tree.walk(git2::TreeWalkMode::PreOrder, |root, entry| {
        let entry_name = match entry.name() {
            Some(n) => n,
            None => return git2::TreeWalkResult::Ok,
        };

        let rel_path = if root.is_empty() {
            entry_name.to_string()
        } else {
            format!("{}{}", root, entry_name)
        };

        let full_path = workdir.join(&rel_path);

        if let Ok(rel) = full_path.strip_prefix(abs_dir) {
            let first_component = match rel.components().next() {
                Some(c) => c.as_os_str().to_string_lossy().into_owned(),
                None => return git2::TreeWalkResult::Ok,
            };

            // Only set Clean if there's no existing status
            result.entry(first_component).or_insert(VcsStatus::Clean);
        }

        git2::TreeWalkResult::Ok
    }).ok();
}

fn git2_status_to_vcs(status: Status) -> VcsStatus {
    if status.is_ignored() {
        return VcsStatus::Ignored;
    }
    if status.is_wt_new() {
        return VcsStatus::Untracked;
    }

    let index_changed = status.is_index_new()
        || status.is_index_modified()
        || status.is_index_deleted()
        || status.is_index_renamed()
        || status.is_index_typechange();

    let wt_changed = status.is_wt_modified()
        || status.is_wt_deleted()
        || status.is_wt_renamed()
        || status.is_wt_typechange();

    if index_changed && wt_changed {
        VcsStatus::BothChanged
    } else if index_changed {
        VcsStatus::Staged
    } else if wt_changed {
        VcsStatus::WorkTreeChanged
    } else {
        VcsStatus::Clean
    }
}
