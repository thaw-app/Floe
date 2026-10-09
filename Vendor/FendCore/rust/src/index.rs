//! The names of the files under one folder, held in memory and matched fuzzily.

use std::collections::HashMap;
use std::ffi::{CStr, OsStr};
use std::os::raw::c_char;
use std::panic::{catch_unwind, AssertUnwindSafe};
use std::path::Path;
use std::ptr;
use std::slice;
use std::sync::{Mutex, RwLock};

use ignore::{DirEntry, ParallelVisitor, ParallelVisitorBuilder, WalkBuilder, WalkState};
use nucleo_matcher::pattern::{AtomKind, CaseMatching, Normalization, Pattern};
use nucleo_matcher::{Config, Matcher, Utf32Str};
use rayon::prelude::*;

const DIR: u8 = 1;
const DEAD: u8 = 2;

/// One file or folder: its name in the arena and the entry of the folder it is in.
#[derive(Clone, Copy)]
struct Entry {
    parent: u32,
    name_start: u32,
    name_len: u16,
    depth: u8,
    flags: u8,
}

/// Which names are left out, and which folders are listed without being entered.
#[derive(Default)]
struct Rules {
    excluded_names: Vec<String>,
    package_suffixes: Vec<String>,
}

#[derive(PartialEq, Eq, Clone, Copy, Debug)]
enum Kind {
    Skip,
    File,
    Folder,
    /// A folder that is one entry: a bundle, whose contents are not the user's files.
    Package,
}

impl Rules {
    fn classify(&self, name: &OsStr, is_dir: bool) -> Kind {
        let Some(name) = name.to_str() else { return Kind::Skip };
        if name.is_empty() || name.starts_with('.') || name.len() > usize::from(u16::MAX) {
            return Kind::Skip;
        }
        if !is_dir {
            return Kind::File;
        }
        if self.excluded_names.iter().any(|excluded| excluded == name) {
            return Kind::Skip;
        }
        let lowered = name.to_ascii_lowercase();
        if self.package_suffixes.iter().any(|suffix| lowered.ends_with(suffix.as_str())) {
            return Kind::Package;
        }
        Kind::Folder
    }
}

/// The entries under a root. Entry 0 is the root itself and has no name.
struct Tree {
    root: String,
    entries: Vec<Entry>,
    names: Vec<u8>,
    /// The entries directly inside each folder that has any.
    children: HashMap<u32, Vec<u32>>,
    dead: usize,
}

/// What one walking thread found: paths relative to the root, in one buffer.
#[derive(Default)]
struct Found {
    bytes: Vec<u8>,
    items: Vec<(u32, u32, bool)>,
}

struct Collector<'a> {
    root: &'a Path,
    rules: &'a Rules,
    found: Found,
    all: &'a Mutex<Vec<Found>>,
    lowered: bool,
}

impl ParallelVisitor for Collector<'_> {
    fn visit(&mut self, entry: Result<DirEntry, ignore::Error>) -> WalkState {
        if !self.lowered {
            lower_priority();
            self.lowered = true;
        }
        let Ok(entry) = entry else { return WalkState::Continue };
        if entry.depth() == 0 {
            return WalkState::Continue;
        }
        let is_dir = entry.file_type().is_some_and(|kind| kind.is_dir());
        let kind = self.rules.classify(entry.file_name(), is_dir);
        if kind == Kind::Skip {
            return WalkState::Skip;
        }
        let relative = entry.path().strip_prefix(self.root).ok().and_then(Path::to_str);
        let Some(relative) = relative else { return WalkState::Skip };
        let (Ok(start), Ok(len)) = (u32::try_from(self.found.bytes.len()), u32::try_from(relative.len())) else {
            return WalkState::Skip;
        };
        self.found.bytes.extend_from_slice(relative.as_bytes());
        self.found.items.push((start, len, is_dir));
        if kind == Kind::Folder { WalkState::Continue } else { WalkState::Skip }
    }
}

impl Drop for Collector<'_> {
    fn drop(&mut self) {
        let found = std::mem::take(&mut self.found);
        self.all.lock().unwrap_or_else(|poisoned| poisoned.into_inner()).push(found);
    }
}

struct Collectors<'a> {
    root: &'a Path,
    rules: &'a Rules,
    all: &'a Mutex<Vec<Found>>,
}

impl<'s> ParallelVisitorBuilder<'s> for Collectors<'s> {
    fn build(&mut self) -> Box<dyn ParallelVisitor + 's> {
        Box::new(Collector { root: self.root, rules: self.rules, found: Found::default(), all: self.all, lowered: false })
    }
}

/// The walk is background work: its threads step aside for whatever the user is doing.
fn lower_priority() {
    #[cfg(target_os = "macos")]
    {
        extern "C" {
            fn pthread_set_qos_class_self_np(qos_class: u32, relative_priority: i32) -> i32;
        }
        const QOS_CLASS_UTILITY: u32 = 0x11;
        unsafe {
            pthread_set_qos_class_self_np(QOS_CLASS_UTILITY, 0);
        }
    }
}

impl Tree {
    fn empty(root: &str) -> Self {
        let top = Entry { parent: 0, name_start: 0, name_len: 0, depth: 0, flags: DIR };
        Self { root: root.to_owned(), entries: vec![top], names: Vec::new(), children: HashMap::new(), dead: 0 }
    }

    /// Everything under `root` that the rules keep. A root that is missing or unreadable gives an empty tree.
    fn walk(root: &str, rules: &Rules, threads: usize) -> Self {
        let all = Mutex::new(Vec::new());
        let path = Path::new(root);
        WalkBuilder::new(path)
            .standard_filters(false)
            .follow_links(false)
            .threads(threads)
            .build_parallel()
            .visit(&mut Collectors { root: path, rules, all: &all });
        let found = all.into_inner().unwrap_or_else(|poisoned| poisoned.into_inner());
        let mut items: Vec<(&str, bool)> = found
            .iter()
            .flat_map(|chunk| {
                chunk.items.iter().filter_map(|&(start, len, is_dir)| {
                    let bytes = chunk.bytes.get(start as usize..(start + len) as usize)?;
                    Some((std::str::from_utf8(bytes).ok()?, is_dir))
                })
            })
            .collect();
        // Folder by folder, so each folder comes right before what is in it.
        items.par_sort_unstable_by(|a, b| a.0.split('/').cmp(b.0.split('/')));

        let mut tree = Self::empty(root);
        tree.entries.reserve_exact(items.len());
        let mut open: Vec<u32> = vec![0];
        for (relative, is_dir) in items {
            let depth = relative.bytes().filter(|byte| *byte == b'/').count() + 1;
            open.truncate(depth);
            // A folder that vanished while it was read leaves entries with nowhere to go.
            let (Some(&parent), true) = (open.last(), open.len() == depth) else { continue };
            let name = relative.rsplit('/').next().unwrap_or(relative);
            let id = tree.push(parent, name, is_dir);
            if is_dir {
                open.push(id);
            }
        }
        tree.names.shrink_to_fit();
        tree.children.values_mut().for_each(Vec::shrink_to_fit);
        tree.children.shrink_to_fit();
        tree
    }

    fn count(&self) -> usize {
        self.entries.len() - 1 - self.dead
    }

    fn byte_size(&self) -> usize {
        let lists: usize = self.children.values().map(|list| list.capacity() * 4).sum();
        let table = self.children.capacity() * (std::mem::size_of::<(u32, Vec<u32>)>() + 1);
        self.entries.capacity() * std::mem::size_of::<Entry>() + self.names.capacity() + lists + table + self.root.len()
    }

    fn name(&self, entry: &Entry) -> &str {
        let start = entry.name_start as usize;
        let bytes = &self.names[start..start + usize::from(entry.name_len)];
        // Only whole strings are ever written to the arena.
        std::str::from_utf8(bytes).unwrap_or("")
    }

    fn push(&mut self, parent: u32, name: &str, is_dir: bool) -> u32 {
        let id = self.entries.len() as u32;
        let depth = self.entries[parent as usize].depth.saturating_add(1);
        self.entries.push(Entry {
            parent,
            name_start: self.names.len() as u32,
            name_len: name.len() as u16,
            depth,
            flags: if is_dir { DIR } else { 0 },
        });
        self.names.extend_from_slice(name.as_bytes());
        self.children.entry(parent).or_default().push(id);
        id
    }

    /// Takes an entry out, with everything inside it.
    fn remove(&mut self, id: u32) {
        let parent = self.entries[id as usize].parent;
        if let Some(siblings) = self.children.get_mut(&parent) {
            siblings.retain(|sibling| *sibling != id);
        }
        let mut pending = vec![id];
        while let Some(current) = pending.pop() {
            self.entries[current as usize].flags |= DEAD;
            self.dead += 1;
            if let Some(inside) = self.children.remove(&current) {
                pending.extend(inside);
            }
        }
    }

    /// Hangs a tree walked on its own under `parent`, as the folder `name`.
    fn graft(&mut self, parent: u32, name: &str, other: Tree) {
        let top = self.push(parent, name, true);
        let top_depth = self.entries[top as usize].depth;
        let first = self.entries.len() as u32;
        let moved = |id: u32| if id == 0 { top } else { first + id - 1 };
        let names_start = self.names.len() as u32;
        self.names.extend_from_slice(&other.names);
        self.entries.extend(other.entries.iter().skip(1).map(|entry| Entry {
            parent: moved(entry.parent),
            name_start: entry.name_start + names_start,
            depth: top_depth.saturating_add(entry.depth),
            ..*entry
        }));
        for (folder, inside) in other.children {
            self.children.insert(moved(folder), inside.into_iter().map(moved).collect());
        }
    }

    /// Drops the removed entries and their names once they are a good part of the whole.
    fn compact_if_due(&mut self) {
        if self.dead < 4096 || self.dead < self.count() / 2 {
            return;
        }
        let mut fresh = Self::empty(&self.root);
        let mut moved = vec![0u32; self.entries.len()];
        // A folder always comes before what is in it, so its new place is known by then.
        for (id, entry) in self.entries.iter().enumerate().skip(1) {
            if entry.flags & DEAD == 0 {
                moved[id] = fresh.push(moved[entry.parent as usize], self.name(entry), entry.flags & DIR != 0);
            }
        }
        *self = fresh;
    }

    fn child(&self, folder: u32, name: &str) -> Option<u32> {
        let inside = self.children.get(&folder)?;
        inside.iter().copied().find(|id| self.name(&self.entries[*id as usize]) == name)
    }

    /// The path from the root down to an entry, without the root.
    fn relative_path(&self, id: u32, into: &mut String) {
        let mut chain = Vec::new();
        let mut current = id;
        while current != 0 {
            chain.push(current);
            current = self.entries[current as usize].parent;
        }
        into.clear();
        for (position, link) in chain.iter().rev().enumerate() {
            if position > 0 {
                into.push('/');
            }
            into.push_str(self.name(&self.entries[*link as usize]));
        }
    }

    fn search(&self, query: &str, limit: usize) -> Vec<Hit> {
        let query = query.trim();
        if query.is_empty() || limit == 0 {
            return Vec::new();
        }
        let by_path = query.contains('/');
        let mut config = Config::DEFAULT.match_paths();
        config.prefer_prefix = true;
        let pattern = Pattern::new(query, CaseMatching::Smart, Normalization::Smart, AtomKind::Fuzzy);

        let mut found: Vec<(u32, u32)> = self
            .entries
            .par_iter()
            .enumerate()
            .with_min_len(4096)
            .map_init(
                || (Matcher::new(config.clone()), Vec::new(), String::new()),
                |(matcher, buffer, path), (id, entry)| {
                    if id == 0 || entry.flags & DEAD != 0 {
                        return None;
                    }
                    let text = if by_path {
                        self.relative_path(id as u32, path);
                        path.as_str()
                    } else {
                        self.name(entry)
                    };
                    let score = pattern.score(Utf32Str::new(text, buffer), matcher)?;
                    Some((score, id as u32))
                },
            )
            .flatten()
            .collect();

        // Best score first; among equals the one nearer the root, then the shorter name.
        let rank = |hit: &(u32, u32)| {
            let entry = &self.entries[hit.1 as usize];
            (std::cmp::Reverse(hit.0), entry.depth, entry.name_len, hit.1)
        };
        if found.len() > limit {
            found.select_nth_unstable_by_key(limit, rank);
            found.truncate(limit);
        }
        found.sort_unstable_by_key(rank);

        let mut matcher = Matcher::new(config);
        let (mut buffer, mut prefix_buffer, mut positions) = (Vec::new(), Vec::new(), Vec::new());
        let mut relative = String::new();
        found
            .into_iter()
            .map(|(score, id)| {
                let entry = &self.entries[id as usize];
                let name = self.name(entry);
                self.relative_path(id, &mut relative);
                positions.clear();
                if by_path {
                    // The positions are in the path; the ones before the name are dropped.
                    let before = Utf32Str::new(&relative[..relative.len() - name.len()], &mut prefix_buffer).len() as u32;
                    pattern.indices(Utf32Str::new(&relative, &mut buffer), &mut matcher, &mut positions);
                    positions.retain(|position| *position >= before);
                    positions.iter_mut().for_each(|position| *position -= before);
                } else {
                    pattern.indices(Utf32Str::new(name, &mut buffer), &mut matcher, &mut positions);
                }
                positions.sort_unstable();
                positions.dedup();
                Hit {
                    path: format!("{}/{}", self.root, relative),
                    is_folder: entry.flags & DIR != 0,
                    score,
                    positions: positions.clone(),
                }
            })
            .collect()
    }
}

#[derive(Debug, PartialEq, Eq)]
struct Hit {
    path: String,
    is_folder: bool,
    score: u32,
    /// The matched characters of the file name, counted the way the matcher counts them.
    positions: Vec<u32>,
}

struct State {
    tree: Tree,
    rules: Rules,
}

/// What a rescan found on disk and will change in the tree, worked out before the tree is locked for writing.
struct Change {
    folder: u32,
    removed: Vec<u32>,
    added: Vec<(String, Kind)>,
}

pub struct FileIndex {
    state: RwLock<State>,
    /// Held by whichever build or rescan is changing the tree, so the entries one of them looked up stay where they were.
    writer: Mutex<()>,
}

fn walk_threads() -> usize {
    std::thread::available_parallelism().map_or(2, |count| count.get().min(8))
}

fn without_trailing_slash(path: &str) -> &str {
    if path.len() > 1 { path.trim_end_matches('/') } else { path }
}

impl FileIndex {
    fn new() -> Self {
        Self { state: RwLock::new(State { tree: Tree::empty(""), rules: Rules::default() }), writer: Mutex::new(()) }
    }

    fn read(&self) -> std::sync::RwLockReadGuard<'_, State> {
        self.state.read().unwrap_or_else(|poisoned| poisoned.into_inner())
    }

    fn write(&self) -> std::sync::RwLockWriteGuard<'_, State> {
        self.state.write().unwrap_or_else(|poisoned| poisoned.into_inner())
    }

    fn build(&self, root: &str, rules: Rules) -> usize {
        let _writing = self.writer.lock().unwrap_or_else(|poisoned| poisoned.into_inner());
        let tree = Tree::walk(without_trailing_slash(root), &rules, walk_threads());
        let count = tree.count();
        *self.write() = State { tree, rules };
        count
    }

    /// Brings one folder in line with the disk: only what is directly in it, or with `recursive` everything under it.
    fn rescan(&self, path: &str, recursive: bool) {
        let _writing = self.writer.lock().unwrap_or_else(|poisoned| poisoned.into_inner());
        let path = without_trailing_slash(path);
        let (change, walked) = {
            let state = self.read();
            let Some(change) = state.change(path, recursive) else { return };
            let folder = state.tree.absolute_path(change.folder);
            let walked: Vec<Option<Tree>> = change
                .added
                .iter()
                .map(|(name, kind)| (*kind == Kind::Folder).then(|| Tree::walk(&format!("{folder}/{name}"), &state.rules, 2)))
                .collect();
            (change, walked)
        };
        let mut state = self.write();
        let tree = &mut state.tree;
        for id in change.removed {
            tree.remove(id);
        }
        for ((name, kind), walked) in change.added.into_iter().zip(walked) {
            match walked {
                Some(walked) => tree.graft(change.folder, &name, walked),
                None => {
                    tree.push(change.folder, &name, kind != Kind::File);
                }
            }
        }
        tree.compact_if_due();
    }
}

impl Tree {
    fn absolute_path(&self, id: u32) -> String {
        let mut relative = String::new();
        self.relative_path(id, &mut relative);
        if relative.is_empty() { self.root.clone() } else { format!("{}/{}", self.root, relative) }
    }
}

impl State {
    /// What differs between a folder on disk and the tree. None when the path is outside the index or left out by the rules.
    fn change(&self, path: &str, recursive: bool) -> Option<Change> {
        let tree = &self.tree;
        if tree.root.is_empty() {
            return None;
        }
        let below = path.strip_prefix(tree.root.as_str())?;
        if !below.is_empty() && !below.starts_with('/') {
            return None;
        }
        let mut folder = 0;
        let mut is_known = true;
        for part in below.split('/').filter(|part| !part.is_empty()) {
            // Nothing inside a folder the walk does not enter is in the index.
            if self.rules.classify(OsStr::new(part), true) != Kind::Folder {
                return None;
            }
            match tree.child(folder, part).filter(|id| is_known && tree.entries[*id as usize].flags & DIR != 0) {
                Some(id) => folder = id,
                None => is_known = false,
            }
        }
        // A folder the index has not seen yet is found, and walked whole, from the last one it knows.
        let everything = recursive && is_known;

        loop {
            let on_disk = match std::fs::read_dir(tree.absolute_path(folder)) {
                Ok(listing) => listing,
                Err(_) if folder == 0 => {
                    let removed = tree.children.get(&0).cloned().unwrap_or_default();
                    return Some(Change { folder, removed, added: Vec::new() });
                }
                // The folder is gone: the one above it is where that shows.
                Err(_) => {
                    folder = tree.entries[folder as usize].parent;
                    continue;
                }
            };
            let mut there: HashMap<String, Kind> = HashMap::new();
            for entry in on_disk.flatten() {
                let is_dir = entry.file_type().is_ok_and(|kind| kind.is_dir());
                let kind = self.rules.classify(&entry.file_name(), is_dir);
                if let (Some(name), true) = (entry.file_name().to_str(), kind != Kind::Skip) {
                    there.insert(name.to_owned(), kind);
                }
            }
            let mut removed = Vec::new();
            for id in tree.children.get(&folder).into_iter().flatten().copied() {
                let entry = &tree.entries[id as usize];
                let is_dir = entry.flags & DIR != 0;
                let name = tree.name(entry);
                match there.get(name) {
                    Some(kind) if !everything && (*kind != Kind::File) == is_dir => {
                        there.remove(name);
                    }
                    _ => removed.push(id),
                }
            }
            let mut added: Vec<(String, Kind)> = there.into_iter().collect();
            added.sort_unstable_by(|a, b| a.0.cmp(&b.0));
            return Some(Change { folder, removed, added });
        }
    }
}

/// The hits in one block: a count, then for each hit its score, whether it is a folder, the path's
/// length and bytes, and the number of matched positions and the positions. Numbers are little-endian u32.
fn encode(hits: &[Hit]) -> Vec<u8> {
    let mut block = Vec::new();
    let number = |block: &mut Vec<u8>, value: usize| block.extend_from_slice(&(value as u32).to_le_bytes());
    number(&mut block, hits.len());
    for hit in hits {
        number(&mut block, hit.score as usize);
        block.push(u8::from(hit.is_folder));
        number(&mut block, hit.path.len());
        block.extend_from_slice(hit.path.as_bytes());
        number(&mut block, hit.positions.len());
        for position in &hit.positions {
            number(&mut block, *position as usize);
        }
    }
    block
}

unsafe fn text<'a>(pointer: *const c_char) -> Option<&'a str> {
    if pointer.is_null() {
        return None;
    }
    CStr::from_ptr(pointer).to_str().ok()
}

unsafe fn texts(list: *const *const c_char, count: usize) -> Vec<String> {
    if list.is_null() {
        return Vec::new();
    }
    slice::from_raw_parts(list, count).iter().filter_map(|item| text(*item)).map(str::to_owned).collect()
}

#[no_mangle]
pub extern "C" fn floe_index_new() -> *mut FileIndex {
    catch_unwind(|| Box::into_raw(Box::new(FileIndex::new()))).unwrap_or(ptr::null_mut())
}

#[no_mangle]
pub unsafe extern "C" fn floe_index_free(index: *mut FileIndex) {
    if !index.is_null() {
        let _ = catch_unwind(AssertUnwindSafe(|| drop(Box::from_raw(index))));
    }
}

/// Walks `root` and replaces what the index holds. Returns the number of entries, or -1 when it could not run.
#[no_mangle]
pub unsafe extern "C" fn floe_index_build(
    index: *const FileIndex,
    root: *const c_char,
    excluded_names: *const *const c_char,
    excluded_name_count: usize,
    package_suffixes: *const *const c_char,
    package_suffix_count: usize,
) -> i64 {
    catch_unwind(AssertUnwindSafe(|| {
        let (Some(index), Some(root)) = (index.as_ref(), text(root)) else { return -1 };
        let rules = Rules {
            excluded_names: texts(excluded_names, excluded_name_count),
            package_suffixes: texts(package_suffixes, package_suffix_count).iter().map(|suffix| suffix.to_ascii_lowercase()).collect(),
        };
        index.build(root, rules) as i64
    }))
    .unwrap_or(-1)
}

#[no_mangle]
pub unsafe extern "C" fn floe_index_rescan(index: *const FileIndex, path: *const c_char, recursive: bool) {
    let _ = catch_unwind(AssertUnwindSafe(|| {
        if let (Some(index), Some(path)) = (index.as_ref(), text(path)) {
            index.rescan(path, recursive);
        }
    }));
}

/// The best `limit` matches as one block (see `encode`), its length in `length`. Freed with `floe_index_block_free`.
#[no_mangle]
pub unsafe extern "C" fn floe_index_search(
    index: *const FileIndex,
    query: *const c_char,
    limit: usize,
    length: *mut usize,
) -> *mut u8 {
    catch_unwind(AssertUnwindSafe(|| {
        let (Some(index), Some(query), Some(length)) = (index.as_ref(), text(query), length.as_mut()) else {
            return ptr::null_mut();
        };
        let block = encode(&index.read().tree.search(query, limit)).into_boxed_slice();
        *length = block.len();
        Box::into_raw(block).cast::<u8>()
    }))
    .unwrap_or(ptr::null_mut())
}

#[no_mangle]
pub unsafe extern "C" fn floe_index_block_free(block: *mut u8, length: usize) {
    if !block.is_null() {
        let _ = catch_unwind(AssertUnwindSafe(|| drop(Box::from_raw(ptr::slice_from_raw_parts_mut(block, length)))));
    }
}

#[no_mangle]
pub unsafe extern "C" fn floe_index_count(index: *const FileIndex) -> usize {
    catch_unwind(AssertUnwindSafe(|| index.as_ref().map_or(0, |index| index.read().tree.count()))).unwrap_or(0)
}

/// Roughly how much memory the index holds, in bytes.
#[no_mangle]
pub unsafe extern "C" fn floe_index_byte_size(index: *const FileIndex) -> usize {
    catch_unwind(AssertUnwindSafe(|| index.as_ref().map_or(0, |index| index.read().tree.byte_size()))).unwrap_or(0)
}

#[cfg(test)]
mod tests;
