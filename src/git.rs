use git2::{Repository, StatusOptions, Status};
use std::collections::{HashMap, HashSet};
use std::path::{Path, PathBuf};

#[derive(Debug, Clone, PartialEq)]
pub enum VcsStatus {
    Clean,          // "==" tracked, not modified
    DirChanged,     // "//" changes inside directory
    DirUntracked,   // directory contains untracked files
    DirEmptyUntracked, // empty directory, not tracked
    Ignored,        // "!!" ignored
    Untracked,      // "??" untracked
    Staged,         // index modified, work tree clean
    WorkTreeChanged,// index clean, work tree modified
    BothChanged,    // both index and work tree changed
    None,           // outside repository
}

pub(crate) fn status_priority(status: &VcsStatus) -> u8 {
    match status {
        VcsStatus::Untracked | VcsStatus::DirUntracked | VcsStatus::DirEmptyUntracked => 4,
        VcsStatus::BothChanged | VcsStatus::WorkTreeChanged | VcsStatus::DirChanged => 3,
        VcsStatus::Staged => 2,
        VcsStatus::Clean => 1,
        VcsStatus::Ignored | VcsStatus::None => 0,
    }
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
            let dir_vcs = match &vcs {
                VcsStatus::Ignored => VcsStatus::Ignored,
                VcsStatus::Untracked => VcsStatus::DirUntracked,
                _ => VcsStatus::DirChanged,
            };
            let should_upgrade = match result.get(&first_component) {
                None => true,
                Some(existing) => status_priority(&dir_vcs) > status_priority(existing),
            };
            if should_upgrade {
                result.insert(first_component.clone(), dir_vcs);
            }
        } else {
            result.insert(first_component.clone(), vcs);
        }
    }

    // Mark tracked files that have no status as Clean
    // Walk the tree at HEAD to find all tracked files
    if let Ok(head) = repo.head() {
        if let Some(tree) = head.peel_to_tree().ok() {
            mark_tracked_clean(&repo, &tree, &workdir, &abs_dir, &mut result);
        }
    }

    let workdir_canonical = workdir.canonicalize().unwrap_or(workdir.clone());
    let dir_rel = abs_dir.strip_prefix(&workdir_canonical).ok();
    let dir_is_ignored = match dir_rel {
        Some(rel) if !rel.as_os_str().is_empty() => repo.is_path_ignored(rel).unwrap_or(false),
        _ => false,
    };

    // If inside an ignored directory, mark unlisted entries as Ignored
    if dir_is_ignored {
        if let Ok(dir_entries) = std::fs::read_dir(dir) {
            for entry in dir_entries.flatten() {
                let name = entry.file_name().to_string_lossy().into_owned();
                result.entry(name).or_insert(VcsStatus::Ignored);
            }
        }
    }

    // Detect empty untracked subdirectories (git doesn't report empty dirs)
    if let Ok(dir_entries) = std::fs::read_dir(dir) {
        for entry in dir_entries.flatten() {
            if entry.file_type().map(|ft| ft.is_dir()).unwrap_or(false) {
                let name = entry.file_name().to_string_lossy().into_owned();
                if !result.contains_key(&name) {
                    let entry_rel: PathBuf = dir_rel
                        .map(|r| r.join(&name))
                        .unwrap_or_else(|| PathBuf::from(&name));
                    if repo.is_path_ignored(&entry_rel).unwrap_or(false) {
                        result.insert(name, VcsStatus::Ignored);
                    } else {
                        result.insert(name, VcsStatus::DirEmptyUntracked);
                    }
                }
            }
        }
    }

    // Handle . and .. for -a flag
    if show_all && !almost_all && !no_directory {
        let dot_status = {
            let has_content = result.iter().any(|(n, _)| n != "." && n != "..");
            if has_content {
                aggregate_entries_status(&result)
            } else {
                // Empty directory
                let is_repo_root = dir_rel.map(|r| r.as_os_str().is_empty()).unwrap_or(true);
                if is_repo_root {
                    VcsStatus::Clean
                } else if dir_is_ignored {
                    VcsStatus::Ignored
                } else {
                    VcsStatus::DirEmptyUntracked
                }
            }
        };
        result.entry(".".to_string()).or_insert(dot_status);

        if abs_dir != workdir_canonical {
            let parent_is_ignored = abs_dir.parent().and_then(|parent| {
                let parent_rel = parent.strip_prefix(&workdir_canonical).ok()?;
                if parent_rel.as_os_str().is_empty() {
                    return Some(false);
                }
                Some(repo.is_path_ignored(parent_rel).unwrap_or(false))
            }).unwrap_or(false);

            let dotdot_status = if parent_is_ignored {
                VcsStatus::Ignored
            } else if let Some(parent_dir) = abs_dir.parent() {
                compute_dir_status_from_statuses(&statuses, &workdir, parent_dir)
            } else {
                VcsStatus::Clean
            };
            result.entry("..".to_string()).or_insert(dotdot_status);
        }
    }

    Some(result)
}

pub(crate) fn aggregate_entries_status(result: &HashMap<String, VcsStatus>) -> VcsStatus {
    let mut best: Option<&VcsStatus> = None;
    for (name, status) in result.iter() {
        if name == "." || name == ".." { continue; }
        match best {
            None => best = Some(status),
            Some(current) if status_priority(status) > status_priority(current) => {
                best = Some(status);
            }
            _ => {}
        }
    }
    match best {
        Some(s) => {
            // Map file-level statuses to dir-level statuses
            if matches!(s, VcsStatus::Untracked | VcsStatus::DirEmptyUntracked) {
                VcsStatus::DirUntracked
            } else if matches!(s, VcsStatus::WorkTreeChanged | VcsStatus::BothChanged | VcsStatus::Staged) {
                VcsStatus::DirChanged
            } else {
                s.clone()
            }
        }
        None => VcsStatus::Clean,
    }
}

fn compute_dir_status_from_statuses(
    statuses: &git2::Statuses,
    workdir: &Path,
    target_dir: &Path,
) -> VcsStatus {
    let mut best = VcsStatus::Clean;
    for status_entry in statuses.iter() {
        let path_str = match status_entry.path() {
            Some(p) => p,
            None => continue,
        };
        let full_path = workdir.join(path_str);
        let rel = match full_path.strip_prefix(target_dir) {
            Ok(r) => r,
            Err(_) => continue,
        };
        if rel.components().count() == 0 { continue; }

        let vcs = git2_status_to_vcs(status_entry.status());
        let effective = if rel.components().count() > 1 {
            match vcs {
                VcsStatus::Ignored => VcsStatus::Ignored,
                VcsStatus::Untracked => VcsStatus::DirUntracked,
                _ => VcsStatus::DirChanged,
            }
        } else {
            vcs
        };
        if status_priority(&effective) > status_priority(&best) {
            best = effective;
        }
    }
    // Map file-level statuses to dir-level statuses
    if matches!(best, VcsStatus::Untracked) {
        VcsStatus::DirUntracked
    } else if matches!(best, VcsStatus::WorkTreeChanged | VcsStatus::BothChanged | VcsStatus::Staged) {
        VcsStatus::DirChanged
    } else {
        best
    }
}

fn mark_tracked_clean(
    repo: &Repository,
    tree: &git2::Tree,
    workdir: &Path,
    abs_dir: &Path,
    result: &mut HashMap<String, VcsStatus>,
) {
    // Collect directories currently marked as Ignored
    let ignored_dirs: HashSet<String> = result
        .iter()
        .filter(|(_, v)| matches!(v, VcsStatus::Ignored))
        .map(|(k, _)| k.clone())
        .collect();

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

            if ignored_dirs.contains(&first_component) {
                // This is a tracked file inside an ignored directory
                // Only check blob entries (actual files, not trees)
                if entry.kind() == Some(git2::ObjectType::Blob) {
                    let repo_rel = Path::new(&rel_path);
                    if let Ok(file_status) = repo.status_file(repo_rel) {
                        let vcs = git2_status_to_vcs(file_status);
                        match vcs {
                            VcsStatus::Clean => {
                                // Upgrade from Ignored to Clean, but don't downgrade from DirChanged
                                let current = result.get(&first_component);
                                if matches!(current, Some(VcsStatus::Ignored)) {
                                    result.insert(first_component, VcsStatus::Clean);
                                }
                            }
                            VcsStatus::Ignored | VcsStatus::Untracked => {}
                            _ => {
                                // Modified/Staged/etc → upgrade to DirChanged
                                result.insert(first_component, VcsStatus::DirChanged);
                            }
                        }
                    }
                }
            } else {
                // Normal directory: set Clean if no existing status
                result.entry(first_component).or_insert(VcsStatus::Clean);
            }
        }

        git2::TreeWalkResult::Ok
    }).ok();
}

pub(crate) fn git2_status_to_vcs(status: Status) -> VcsStatus {
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

#[cfg(test)]
mod tests {
    use super::*;

    // ---- status_priority tests ----

    #[test]
    fn test_status_priority_untracked_highest() {
        assert_eq!(status_priority(&VcsStatus::Untracked), 4);
        assert_eq!(status_priority(&VcsStatus::DirUntracked), 4);
        assert_eq!(status_priority(&VcsStatus::DirEmptyUntracked), 4);
    }

    #[test]
    fn test_status_priority_modified() {
        assert_eq!(status_priority(&VcsStatus::BothChanged), 3);
        assert_eq!(status_priority(&VcsStatus::WorkTreeChanged), 3);
        assert_eq!(status_priority(&VcsStatus::DirChanged), 3);
    }

    #[test]
    fn test_status_priority_staged() {
        assert_eq!(status_priority(&VcsStatus::Staged), 2);
    }

    #[test]
    fn test_status_priority_clean() {
        assert_eq!(status_priority(&VcsStatus::Clean), 1);
    }

    #[test]
    fn test_status_priority_ignored_and_none() {
        assert_eq!(status_priority(&VcsStatus::Ignored), 0);
        assert_eq!(status_priority(&VcsStatus::None), 0);
    }

    #[test]
    fn test_priority_ordering() {
        // untracked > modified > staged > clean > ignored
        assert!(status_priority(&VcsStatus::Untracked) > status_priority(&VcsStatus::WorkTreeChanged));
        assert!(status_priority(&VcsStatus::WorkTreeChanged) > status_priority(&VcsStatus::Staged));
        assert!(status_priority(&VcsStatus::Staged) > status_priority(&VcsStatus::Clean));
        assert!(status_priority(&VcsStatus::Clean) > status_priority(&VcsStatus::Ignored));
    }

    // ---- git2_status_to_vcs tests ----

    #[test]
    fn test_git2_status_ignored() {
        assert_eq!(git2_status_to_vcs(Status::IGNORED), VcsStatus::Ignored);
    }

    #[test]
    fn test_git2_status_untracked() {
        assert_eq!(git2_status_to_vcs(Status::WT_NEW), VcsStatus::Untracked);
    }

    #[test]
    fn test_git2_status_staged() {
        assert_eq!(git2_status_to_vcs(Status::INDEX_NEW), VcsStatus::Staged);
        assert_eq!(git2_status_to_vcs(Status::INDEX_MODIFIED), VcsStatus::Staged);
        assert_eq!(git2_status_to_vcs(Status::INDEX_DELETED), VcsStatus::Staged);
        assert_eq!(git2_status_to_vcs(Status::INDEX_RENAMED), VcsStatus::Staged);
        assert_eq!(git2_status_to_vcs(Status::INDEX_TYPECHANGE), VcsStatus::Staged);
    }

    #[test]
    fn test_git2_status_worktree_changed() {
        assert_eq!(git2_status_to_vcs(Status::WT_MODIFIED), VcsStatus::WorkTreeChanged);
        assert_eq!(git2_status_to_vcs(Status::WT_DELETED), VcsStatus::WorkTreeChanged);
        assert_eq!(git2_status_to_vcs(Status::WT_RENAMED), VcsStatus::WorkTreeChanged);
        assert_eq!(git2_status_to_vcs(Status::WT_TYPECHANGE), VcsStatus::WorkTreeChanged);
    }

    #[test]
    fn test_git2_status_both_changed() {
        let both = Status::INDEX_MODIFIED | Status::WT_MODIFIED;
        assert_eq!(git2_status_to_vcs(both), VcsStatus::BothChanged);

        let both2 = Status::INDEX_NEW | Status::WT_MODIFIED;
        assert_eq!(git2_status_to_vcs(both2), VcsStatus::BothChanged);
    }

    #[test]
    fn test_git2_status_clean() {
        assert_eq!(git2_status_to_vcs(Status::CURRENT), VcsStatus::Clean);
    }

    #[test]
    fn test_git2_status_ignored_takes_precedence() {
        // IGNORED flag should return Ignored even if other flags are set
        let status = Status::IGNORED | Status::WT_MODIFIED;
        assert_eq!(git2_status_to_vcs(status), VcsStatus::Ignored);
    }

    #[test]
    fn test_git2_status_wt_new_takes_precedence_over_index() {
        // WT_NEW should return Untracked even with index flags
        let status = Status::WT_NEW | Status::INDEX_NEW;
        assert_eq!(git2_status_to_vcs(status), VcsStatus::Untracked);
    }

    // ---- aggregate_entries_status tests ----

    #[test]
    fn test_aggregate_empty_map() {
        let map: HashMap<String, VcsStatus> = HashMap::new();
        assert_eq!(aggregate_entries_status(&map), VcsStatus::Clean);
    }

    #[test]
    fn test_aggregate_all_clean() {
        let mut map = HashMap::new();
        map.insert("a.txt".to_string(), VcsStatus::Clean);
        map.insert("b.txt".to_string(), VcsStatus::Clean);
        assert_eq!(aggregate_entries_status(&map), VcsStatus::Clean);
    }

    #[test]
    fn test_aggregate_with_untracked() {
        let mut map = HashMap::new();
        map.insert("a.txt".to_string(), VcsStatus::Clean);
        map.insert("b.txt".to_string(), VcsStatus::Untracked);
        // Untracked files → DirUntracked at dir level
        assert_eq!(aggregate_entries_status(&map), VcsStatus::DirUntracked);
    }

    #[test]
    fn test_aggregate_with_worktree_changed() {
        let mut map = HashMap::new();
        map.insert("a.txt".to_string(), VcsStatus::Clean);
        map.insert("b.txt".to_string(), VcsStatus::WorkTreeChanged);
        // WorkTreeChanged → DirChanged at dir level
        assert_eq!(aggregate_entries_status(&map), VcsStatus::DirChanged);
    }

    #[test]
    fn test_aggregate_with_staged() {
        let mut map = HashMap::new();
        map.insert("a.txt".to_string(), VcsStatus::Clean);
        map.insert("b.txt".to_string(), VcsStatus::Staged);
        assert_eq!(aggregate_entries_status(&map), VcsStatus::DirChanged);
    }

    #[test]
    fn test_aggregate_with_both_changed() {
        let mut map = HashMap::new();
        map.insert("a.txt".to_string(), VcsStatus::BothChanged);
        assert_eq!(aggregate_entries_status(&map), VcsStatus::DirChanged);
    }

    #[test]
    fn test_aggregate_dir_empty_untracked_maps_to_dir_untracked() {
        let mut map = HashMap::new();
        map.insert("empty_dir".to_string(), VcsStatus::DirEmptyUntracked);
        assert_eq!(aggregate_entries_status(&map), VcsStatus::DirUntracked);
    }

    #[test]
    fn test_aggregate_skips_dot_entries() {
        let mut map = HashMap::new();
        map.insert(".".to_string(), VcsStatus::Untracked);
        map.insert("..".to_string(), VcsStatus::Untracked);
        map.insert("a.txt".to_string(), VcsStatus::Clean);
        // . and .. should be ignored in aggregation
        assert_eq!(aggregate_entries_status(&map), VcsStatus::Clean);
    }

    #[test]
    fn test_aggregate_priority_untracked_over_modified() {
        let mut map = HashMap::new();
        map.insert("a.txt".to_string(), VcsStatus::WorkTreeChanged);
        map.insert("b.txt".to_string(), VcsStatus::Untracked);
        // Untracked (4) > WorkTreeChanged (3)
        assert_eq!(aggregate_entries_status(&map), VcsStatus::DirUntracked);
    }

    #[test]
    fn test_aggregate_priority_modified_over_staged() {
        let mut map = HashMap::new();
        map.insert("a.txt".to_string(), VcsStatus::Staged);
        map.insert("b.txt".to_string(), VcsStatus::WorkTreeChanged);
        // WorkTreeChanged (3) > Staged (2)
        assert_eq!(aggregate_entries_status(&map), VcsStatus::DirChanged);
    }

    #[test]
    fn test_aggregate_priority_staged_over_clean() {
        let mut map = HashMap::new();
        map.insert("a.txt".to_string(), VcsStatus::Clean);
        map.insert("b.txt".to_string(), VcsStatus::Staged);
        // Staged (2) > Clean (1) → DirChanged
        assert_eq!(aggregate_entries_status(&map), VcsStatus::DirChanged);
    }

    #[test]
    fn test_aggregate_ignored_entries_ignored() {
        let mut map = HashMap::new();
        map.insert("a.txt".to_string(), VcsStatus::Ignored);
        map.insert("b.txt".to_string(), VcsStatus::Ignored);
        // All ignored → Ignored (priority 0)
        assert_eq!(aggregate_entries_status(&map), VcsStatus::Ignored);
    }

    #[test]
    fn test_aggregate_clean_and_ignored() {
        let mut map = HashMap::new();
        map.insert("a.txt".to_string(), VcsStatus::Ignored);
        map.insert("b.txt".to_string(), VcsStatus::Clean);
        // Clean (1) > Ignored (0)
        assert_eq!(aggregate_entries_status(&map), VcsStatus::Clean);
    }

    #[test]
    fn test_aggregate_dir_changed_propagated() {
        let mut map = HashMap::new();
        map.insert("subdir".to_string(), VcsStatus::DirChanged);
        map.insert("a.txt".to_string(), VcsStatus::Clean);
        assert_eq!(aggregate_entries_status(&map), VcsStatus::DirChanged);
    }

    #[test]
    fn test_aggregate_dir_untracked_propagated() {
        let mut map = HashMap::new();
        map.insert("subdir".to_string(), VcsStatus::DirUntracked);
        map.insert("a.txt".to_string(), VcsStatus::Clean);
        assert_eq!(aggregate_entries_status(&map), VcsStatus::DirUntracked);
    }
}
