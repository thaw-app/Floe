//! The index as a file, so a launch reads it back and need not walk the folder again.

use std::fs::File;
use std::io::{BufReader, BufWriter, Read, Write};

use super::*;

/// The first bytes of a saved index. The last one is the format's version.
const MAGIC: &[u8; 8] = b"FLOEIDX\x01";
/// What one entry takes in the file: its parent, where its name starts, the name's length, its depth, its flags.
const ENTRY_BYTES: usize = 12;
/// The longest path a read entry may have under the root: far past what macOS opens, and a bound on what a search
/// puts together for each entry, since names in a damaged file may share their bytes.
const PATH_BYTES: u32 = 64 * 1024;

impl Rules {
    /// The rules as one text. A file saved under other rules lists other names, so it is not read back.
    fn text(&self) -> String {
        format!("{}\0{}", self.excluded_names.join("\n"), self.package_suffixes.join("\n"))
    }
}

fn write_text(into: &mut impl Write, text: &str) -> std::io::Result<()> {
    into.write_all(&(text.len() as u32).to_le_bytes())?;
    into.write_all(text.as_bytes())
}

fn read_number(from: &mut impl Read) -> Option<u32> {
    let mut bytes = [0; 4];
    from.read_exact(&mut bytes).ok()?;
    Some(u32::from_le_bytes(bytes))
}

/// Reads a text only when it is the one expected, so a wrong length never asks for memory.
fn reads_text(from: &mut impl Read, expected: &str) -> bool {
    let mut bytes = vec![0; expected.len()];
    read_number(from) == Some(expected.len() as u32) && from.read_exact(&mut bytes).is_ok() && bytes == expected.as_bytes()
}

impl Tree {
    /// The tree without the entries that were removed.
    pub(super) fn compacted(&self) -> Self {
        let mut fresh = Self::empty(&self.root);
        fresh.entries.reserve_exact(self.count());
        fresh.names.reserve_exact(self.names.len());
        let mut moved = vec![0u32; self.entries.len()];
        // A folder always comes before what is in it, so its new place is known by then.
        for (id, entry) in self.entries.iter().enumerate().skip(1) {
            if entry.flags & DEAD == 0 {
                moved[id] = fresh.push(moved[entry.parent as usize], self.name(entry), entry.flags & DIR != 0);
            }
        }
        fresh.names.shrink_to_fit();
        fresh
    }

    /// Only a tree with nothing removed is written: the file has no way to say an entry is gone.
    pub(super) fn write(&self, into: &mut impl Write, rules: &Rules) -> std::io::Result<()> {
        into.write_all(MAGIC)?;
        write_text(into, &self.root)?;
        write_text(into, &rules.text())?;
        into.write_all(&(self.entries.len() as u32).to_le_bytes())?;
        into.write_all(&(self.names.len() as u32).to_le_bytes())?;
        for entry in &self.entries {
            into.write_all(&entry.parent.to_le_bytes())?;
            into.write_all(&entry.name_start.to_le_bytes())?;
            into.write_all(&entry.name_len.to_le_bytes())?;
            into.write_all(&[entry.depth, entry.flags])?;
        }
        into.write_all(&self.names)
    }

    /// The tree a file holds, or None for a file of another folder, other rules, another version, or one that
    /// is damaged. `size` is the file's length, checked before any room is made for what it claims to hold.
    fn read(from: &mut impl Read, size: u64, root: &str, rules: &Rules) -> Option<Self> {
        let mut magic = [0; 8];
        from.read_exact(&mut magic).ok()?;
        let rules = rules.text();
        if &magic != MAGIC || !reads_text(from, root) || !reads_text(from, &rules) {
            return None;
        }
        let (count, names_len) = (read_number(from)? as usize, read_number(from)? as usize);
        let header = MAGIC.len() + 4 + root.len() + 4 + rules.len() + 8;
        if count == 0 || size != (header + count * ENTRY_BYTES + names_len) as u64 {
            return None;
        }
        let mut entries = Vec::with_capacity(count);
        let mut inside = vec![0u32; count];
        let mut lengths = vec![0u32; count];
        for id in 0..count {
            let mut bytes = [0; ENTRY_BYTES];
            from.read_exact(&mut bytes).ok()?;
            let number = |at: usize| u32::from_le_bytes([bytes[at], bytes[at + 1], bytes[at + 2], bytes[at + 3]]);
            let entry = Entry { parent: number(0), name_start: number(4), name_len: u16::from_le_bytes([bytes[8], bytes[9]]), depth: bytes[10], flags: bytes[11] };
            let parent: &Entry = if id == 0 { &entry } else { entries.get(entry.parent as usize)? };
            let fits = entry.name_start as usize + usize::from(entry.name_len) <= names_len;
            let is_top = id == 0 && entry.parent == 0 && entry.name_len == 0 && entry.depth == 0;
            // Checked, not saturating: past 255 a saturated depth would let a chain of any length through.
            let is_inside = id > 0 && entry.name_len > 0 && parent.depth.checked_add(1) == Some(entry.depth);
            let length = if id == 0 { 0 } else { lengths[entry.parent as usize] + 1 + u32::from(entry.name_len) };
            if !fits || entry.flags & !DIR != 0 || parent.flags & DIR == 0 || !(is_top || is_inside) || length > PATH_BYTES {
                return None;
            }
            lengths[id] = length;
            inside[entry.parent as usize] += u32::from(id > 0);
            entries.push(entry);
        }
        let mut names = vec![0; names_len];
        from.read_exact(&mut names).ok()?;
        let mut tree = Self { root: root.to_owned(), entries, names, children: BTreeMap::new(), dead: 0 };
        // A name that is not text would be shown as nothing and found by nothing.
        if tree.entries.iter().skip(1).any(|entry| tree.name(entry).is_empty()) {
            return None;
        }
        for id in 1..count {
            let parent = tree.entries[id].parent;
            let list = tree.children.entry(parent).or_insert_with(|| Vec::with_capacity(inside[parent as usize] as usize));
            list.push(id as u32);
        }
        Some(tree)
    }
}

impl FileIndex {
    /// Writes the index beside `path` and moves it into place, so a file there is always a whole one.
    /// False for an index that was never built, or when the file could not be written.
    pub(super) fn save(&self, path: &str) -> bool {
        let state = self.read();
        if state.tree.root.is_empty() {
            return false;
        }
        let compact;
        let tree = if state.tree.dead == 0 {
            &state.tree
        } else {
            compact = state.tree.compacted();
            &compact
        };
        let unfinished = format!("{path}.unfinished");
        let written = File::create(&unfinished).and_then(|file| {
            let mut file = BufWriter::new(file);
            tree.write(&mut file, &state.rules)?;
            file.flush()
        });
        let saved = written.is_ok() && std::fs::rename(&unfinished, path).is_ok();
        if !saved {
            let _ = std::fs::remove_file(&unfinished);
        }
        saved
    }

    /// Replaces what the index holds with a saved one and returns the number of entries. None leaves the
    /// index as it was: the file is missing, damaged, or was saved for another folder or other rules.
    pub(super) fn load(&self, path: &str, root: &str, rules: Rules) -> Option<usize> {
        let _writing = self.writer.lock().unwrap_or_else(|poisoned| poisoned.into_inner());
        let file = File::open(path).ok()?;
        let size = file.metadata().ok()?.len();
        let tree = Tree::read(&mut BufReader::new(file), size, without_trailing_slash(root), &rules)?;
        let count = tree.count();
        *self.write() = State { tree, rules };
        Some(count)
    }
}
