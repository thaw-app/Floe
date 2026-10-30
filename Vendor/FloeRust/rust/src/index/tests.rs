use super::*;
use std::ffi::CString;
use std::fs;
use std::os::unix::ffi::OsStrExt;
use std::path::PathBuf;
use std::sync::atomic::{AtomicUsize, Ordering};
use std::time::{Duration, Instant};

/// A folder of its own under the system's temporary folder, removed when the test ends.
struct Scratch(PathBuf);

impl Scratch {
    fn new() -> Self {
        static NEXT: AtomicUsize = AtomicUsize::new(0);
        let name = format!("floe-index-{}-{}", std::process::id(), NEXT.fetch_add(1, Ordering::Relaxed));
        let path = std::env::temp_dir().join(name);
        fs::create_dir_all(&path).unwrap();
        Self(path)
    }

    fn root(&self) -> &str {
        self.0.to_str().unwrap()
    }

    fn path(&self, relative: &str) -> String {
        format!("{}/{relative}", self.root())
    }

    fn file(&self, relative: &str) {
        let path = self.0.join(relative);
        fs::create_dir_all(path.parent().unwrap()).unwrap();
        fs::write(path, "").unwrap();
    }

    fn folder(&self, relative: &str) {
        fs::create_dir_all(self.0.join(relative)).unwrap();
    }
}

impl Drop for Scratch {
    fn drop(&mut self) {
        let _ = fs::remove_dir_all(&self.0);
    }
}

fn rules() -> Rules {
    Rules { excluded_names: vec!["node_modules".into(), "Library".into()], package_suffixes: vec![".app".into(), ".photoslibrary".into()] }
}

fn built(scratch: &Scratch) -> FileIndex {
    let index = FileIndex::new();
    index.build(scratch.root(), rules());
    index
}

/// The paths a query finds, without the root, best first.
fn found(index: &FileIndex, scratch: &Scratch, query: &str) -> Vec<String> {
    let hits = index.read().tree.search(query, 50);
    hits.iter().map(|hit| hit.path.strip_prefix(&scratch.path("")).unwrap().to_owned()).collect()
}

fn count(index: &FileIndex) -> usize {
    index.read().tree.count()
}

#[test]
fn a_build_lists_files_and_folders_under_the_root() {
    let scratch = Scratch::new();
    scratch.file("notes.txt");
    scratch.file("Documents/invoice.pdf");
    scratch.folder("Documents/Empty");
    let index = FileIndex::new();
    assert_eq!(index.build(&scratch.path(""), rules()), 4, "a trailing slash on the root changes nothing");
    assert_eq!(found(&index, &scratch, "invoice"), ["Documents/invoice.pdf"]);

    let hits = index.read().tree.search("Documents", 10);
    assert_eq!(hits[0].path, scratch.path("Documents"));
    assert!(hits[0].is_folder);
    assert!(!index.read().tree.search("notes", 10)[0].is_folder);
    assert!(index.read().tree.byte_size() > 0);
}

#[test]
fn a_second_build_replaces_the_first() {
    let scratch = Scratch::new();
    scratch.file("old.txt");
    let index = built(&scratch);
    fs::remove_file(scratch.path("old.txt")).unwrap();
    scratch.file("new.txt");
    assert_eq!(index.build(scratch.root(), rules()), 1);
    assert!(found(&index, &scratch, "old").is_empty());
    assert_eq!(found(&index, &scratch, "new"), ["new.txt"]);
}

#[test]
fn excluded_folders_and_hidden_names_are_left_out() {
    let scratch = Scratch::new();
    scratch.file("app/node_modules/left-pad/index.js");
    scratch.file("Library/Caches/index.db");
    scratch.file(".git/index");
    scratch.file(".index-hidden");
    scratch.file("src/index.ts");
    // The names are those of folders: a file may carry one.
    scratch.file("src/Library");
    let index = built(&scratch);
    assert_eq!(found(&index, &scratch, "index"), ["src/index.ts"]);
    assert_eq!(found(&index, &scratch, "Library"), ["src/Library"]);
    assert!(found(&index, &scratch, "node_modules").is_empty());
    assert_eq!(count(&index), 4, "app, src and the two files in src");
}

#[test]
fn a_package_is_one_entry_and_nothing_inside_it_is_listed() {
    let scratch = Scratch::new();
    scratch.file("Pictures/Photos.photoslibrary/originals/holiday.jpg");
    scratch.file("Tools/Editor.APP/Contents/Info.plist");
    scratch.file("Pictures/holiday.png");
    let index = built(&scratch);
    assert_eq!(found(&index, &scratch, "holiday"), ["Pictures/holiday.png"]);
    assert!(found(&index, &scratch, "Info.plist").is_empty(), "the suffix is matched whatever its case");
    let hits = index.read().tree.search("photoslibrary", 10);
    assert_eq!(hits.len(), 1);
    assert!(hits[0].is_folder);
}

#[test]
fn symlinks_are_listed_and_never_followed() {
    let scratch = Scratch::new();
    scratch.file("real/report.txt");
    std::os::unix::fs::symlink(scratch.path("real"), scratch.path("shortcut")).unwrap();
    std::os::unix::fs::symlink(scratch.root(), scratch.path("real/around")).unwrap();
    let index = built(&scratch);
    assert_eq!(found(&index, &scratch, "report"), ["real/report.txt"]);
    let hits = index.read().tree.search("shortcut", 10);
    assert_eq!(hits.len(), 1);
    assert!(!hits[0].is_folder, "a link is an entry of its own, not the folder it points to");
    assert_eq!(count(&index), 4);
}

#[test]
fn a_name_that_is_not_text_is_skipped() {
    let name = OsStr::from_bytes(b"caf\xe9.txt");
    assert_eq!(rules().classify(name, false), Kind::Skip);
    assert_eq!(rules().classify(name, true), Kind::Skip);

    let scratch = Scratch::new();
    scratch.file("plain.txt");
    // APFS refuses such a name; a volume that takes it must not bring the walk down.
    let made = fs::write(scratch.0.join(name), "").is_ok();
    let index = built(&scratch);
    assert_eq!(count(&index), 1, "made on disk: {made}");
    index.rescan(scratch.root(), false);
    assert_eq!(count(&index), 1);
}

#[test]
fn an_empty_or_missing_root_gives_an_empty_index() {
    let scratch = Scratch::new();
    let index = FileIndex::new();
    assert_eq!(index.build(scratch.root(), rules()), 0);
    assert!(found(&index, &scratch, "a").is_empty());
    assert_eq!(index.build(&scratch.path("no-such-folder"), rules()), 0);
    index.rescan(&scratch.path("no-such-folder"), true);
    assert_eq!(count(&index), 0);

    let never_built = FileIndex::new();
    never_built.rescan(scratch.root(), true);
    assert_eq!(count(&never_built), 0);
    assert!(never_built.read().tree.search("a", 10).is_empty());
}

#[test]
fn a_rescan_sees_a_file_added_removed_and_renamed() {
    let scratch = Scratch::new();
    scratch.file("docs/first.txt");
    scratch.file("docs/deep/kept.txt");
    let index = built(&scratch);

    scratch.file("docs/second.txt");
    index.rescan(&scratch.path("docs"), false);
    assert_eq!(found(&index, &scratch, "second"), ["docs/second.txt"]);
    assert_eq!(count(&index), 5);

    fs::remove_file(scratch.path("docs/first.txt")).unwrap();
    index.rescan(&scratch.path("docs/"), false);
    assert!(found(&index, &scratch, "first").is_empty());
    assert_eq!(count(&index), 4);

    fs::rename(scratch.path("docs/second.txt"), scratch.path("docs/third.txt")).unwrap();
    index.rescan(&scratch.path("docs"), false);
    assert!(found(&index, &scratch, "second").is_empty());
    assert_eq!(found(&index, &scratch, "third"), ["docs/third.txt"]);
    assert_eq!(found(&index, &scratch, "kept"), ["docs/deep/kept.txt"], "what did not change is left alone");
    assert_eq!(count(&index), 4);
}

#[test]
fn a_walking_thread_keeps_a_folders_path_once_for_all_the_names_in_it() {
    let mut found = Found::default();
    found.add("", "docs", true);
    found.add("docs/deep", "one.txt", false);
    found.add("docs/deep", "two.txt", false);
    found.add("docs", "other.txt", false);

    let folders: Vec<(&str, u32)> = found.folders.iter().map(|listing| (found.folder(listing), listing.count)).collect();
    assert_eq!(folders, [("", 1), ("docs/deep", 2), ("docs", 1)]);
    let names: Vec<&str> = found.names.iter().map(|name| found.text(name.0, usize::from(name.1))).collect();
    assert_eq!(names, ["docs", "one.txt", "two.txt", "other.txt"]);
    assert_eq!(found.bytes.len(), "docs".len() + "docs/deep".len() + "one.txt".len() + "two.txt".len() + "docs".len() + "other.txt".len());
}

#[test]
fn a_full_tree_grows_by_a_little_when_one_more_name_arrives() {
    let mut tree = Tree::empty("/root");
    for number in 0..4000 {
        tree.push(0, &format!("file-{number}.txt"), false);
    }
    tree.entries.shrink_to_fit();
    tree.names.shrink_to_fit();
    let (entries, names) = (tree.entries.capacity(), tree.names.capacity());

    tree.push(0, "one-more.txt", false);
    assert!(tree.entries.capacity() <= entries + entries / 8);
    assert!(tree.names.capacity() <= names + names / 8);
}

#[test]
fn a_rescan_sees_a_folder_removed_renamed_and_moved_in() {
    let scratch = Scratch::new();
    scratch.file("work/old/a/one.txt");
    scratch.file("work/old/two.txt");
    let index = built(&scratch);
    assert_eq!(count(&index), 5);

    fs::rename(scratch.path("work/old"), scratch.path("work/new")).unwrap();
    index.rescan(&scratch.path("work"), false);
    assert_eq!(found(&index, &scratch, "one"), ["work/new/a/one.txt"], "a folder that appears is walked whole");
    assert_eq!(found(&index, &scratch, "two.txt"), ["work/new/two.txt"]);
    assert_eq!(count(&index), 5);

    fs::remove_dir_all(scratch.path("work/new")).unwrap();
    index.rescan(&scratch.path("work"), false);
    assert_eq!(count(&index), 1);
    assert!(found(&index, &scratch, "one").is_empty());

    // The folder itself is gone by the time its event is read: the one above it shows that.
    scratch.file("work/gone/x.txt");
    index.rescan(&scratch.path("work"), false);
    fs::remove_dir_all(scratch.path("work/gone")).unwrap();
    index.rescan(&scratch.path("work/gone"), false);
    assert_eq!(count(&index), 1);

    // A file where a folder was, under the same name.
    scratch.file("work/thing/inside.txt");
    index.rescan(&scratch.path("work"), false);
    fs::remove_dir_all(scratch.path("work/thing")).unwrap();
    scratch.file("work/thing");
    index.rescan(&scratch.path("work"), false);
    assert!(found(&index, &scratch, "inside").is_empty());
    assert!(!index.read().tree.search("thing", 10)[0].is_folder);
}

#[test]
fn a_folder_that_becomes_a_link_is_not_followed_out_of_the_root() {
    let scratch = Scratch::new();
    let outside = Scratch::new();
    outside.file("secret/private.txt");
    scratch.file("docs/report.txt");
    let index = built(&scratch);

    // The tree still has docs as a folder; the rescan must not read where the link now leads.
    fs::remove_dir_all(scratch.path("docs")).unwrap();
    std::os::unix::fs::symlink(outside.root(), scratch.path("docs")).unwrap();
    index.rescan(&scratch.path("docs"), false);
    index.rescan(&scratch.path("docs/secret"), true);
    assert!(found(&index, &scratch, "private").is_empty());
    assert!(found(&index, &scratch, "secret").is_empty());
    assert!(!index.read().tree.search("docs", 10)[0].is_folder, "the link is listed as an entry of its own");

    let top = Folder::open(scratch.root()).unwrap();
    assert!(top.inside("docs").is_none());
    assert!(top.inside("docs/secret").is_none(), "nor is a link on the way to a folder");
    assert!(Folder::open(&scratch.path("docs")).is_some(), "the root itself may be reached through a link");
}

#[test]
fn a_recursive_rescan_reads_the_whole_subtree_again() {
    let scratch = Scratch::new();
    scratch.file("tree/a/b/deep.txt");
    scratch.file("other/untouched.txt");
    let index = built(&scratch);

    scratch.file("tree/a/b/c/deeper.txt");
    fs::remove_file(scratch.path("tree/a/b/deep.txt")).unwrap();
    index.rescan(&scratch.path("tree"), false);
    assert_eq!(found(&index, &scratch, "deep"), ["tree/a/b/deep.txt"], "one level only");

    index.rescan(&scratch.path("tree"), true);
    assert_eq!(found(&index, &scratch, "deep"), ["tree/a/b/c/deeper.txt"]);
    assert_eq!(found(&index, &scratch, "untouched"), ["other/untouched.txt"]);
    assert_eq!(count(&index), 7);

    index.rescan(scratch.root(), true);
    assert_eq!(count(&index), 7);
}

#[test]
fn a_rescan_of_a_folder_the_index_has_not_seen_starts_from_one_it_knows() {
    let scratch = Scratch::new();
    scratch.folder("projects");
    let index = built(&scratch);
    scratch.file("projects/fresh/src/main.rs");
    index.rescan(&scratch.path("projects/fresh/src"), false);
    assert_eq!(found(&index, &scratch, "main"), ["projects/fresh/src/main.rs"]);
    assert_eq!(count(&index), 4);
}

#[test]
fn a_rescan_outside_the_index_changes_nothing() {
    let scratch = Scratch::new();
    scratch.file("app/node_modules/pkg/a.js");
    scratch.file("Tool.app/Contents/b.txt");
    scratch.file("kept.txt");
    let index = built(&scratch);
    let before = count(&index);
    assert_eq!(before, 3);

    scratch.file("app/node_modules/pkg/new.js");
    scratch.file("Tool.app/Contents/new.txt");
    scratch.file(".hidden/new.txt");
    for path in ["app/node_modules/pkg", "app/node_modules", "Tool.app/Contents", "Tool.app", ".hidden"] {
        index.rescan(&scratch.path(path), true);
    }
    index.rescan("/", true);
    index.rescan(&format!("{}-sibling", scratch.root()), true);
    assert_eq!(count(&index), before);
    assert!(found(&index, &scratch, "new").is_empty());
}

#[test]
fn a_root_that_goes_away_empties_the_index() {
    let scratch = Scratch::new();
    scratch.file("a/b.txt");
    let index = built(&scratch);
    fs::remove_dir_all(scratch.root()).unwrap();
    index.rescan(&scratch.path("a"), false);
    assert_eq!(count(&index), 0);
    assert!(found(&index, &scratch, "b").is_empty());
}

#[test]
fn equal_matches_come_shallower_first_then_shorter() {
    let scratch = Scratch::new();
    scratch.file("a/b/c/README.md");
    scratch.file("a/README.md");
    scratch.file("README.md");
    scratch.file("a/b/README.md");
    let index = built(&scratch);
    assert_eq!(found(&index, &scratch, "readme"), ["README.md", "a/README.md", "a/b/README.md", "a/b/c/README.md"]);

    let names = Scratch::new();
    names.file("x/report-final.txt");
    names.file("x/report.txt");
    names.file("x/quarterly-report.txt");
    let index = built(&names);
    let order = found(&index, &names, "report");
    assert_eq!(order.len(), 3);
    assert_eq!(order[0], "x/report.txt");
    assert_eq!(order[2], "x/quarterly-report.txt", "a match at the start of the name comes first");
}

#[test]
fn the_limit_keeps_the_best_matches() {
    let scratch = Scratch::new();
    for number in 0..40 {
        scratch.file(&format!("deep/er/note-{number:02}.txt"));
    }
    scratch.file("note.txt");
    let index = built(&scratch);
    let hits = index.read().tree.search("note", 5);
    assert_eq!(hits.len(), 5);
    assert_eq!(hits[0].path, scratch.path("note.txt"));
    assert!(hits.windows(2).all(|pair| pair[0].score >= pair[1].score));
    assert!(index.read().tree.search("note", 0).is_empty());
    assert!(index.read().tree.search("   ", 5).is_empty());
}

#[test]
fn the_name_is_matched_and_a_query_with_a_slash_matches_the_path() {
    let scratch = Scratch::new();
    scratch.file("invoices/2026/january.pdf");
    scratch.file("letters/invoice.pdf");
    let index = built(&scratch);
    assert_eq!(found(&index, &scratch, "invoice"), ["invoices", "letters/invoice.pdf"], "a folder's name does not match for the files in it");
    assert_eq!(found(&index, &scratch, "invoices/jan"), ["invoices/2026/january.pdf"]);
    assert_eq!(found(&index, &scratch, "inv pdf"), ["letters/invoice.pdf"], "every word has to match");
}

#[test]
fn capitals_in_the_query_match_as_small_letters_do_as_in_every_other_row() {
    let scratch = Scratch::new();
    scratch.file("Makefile");
    scratch.file("makefile.bak");
    let index = built(&scratch);
    assert_eq!(found(&index, &scratch, "make").len(), 2);
    assert_eq!(found(&index, &scratch, "Make").len(), 2);
    assert_eq!(found(&index, &scratch, "MAKE").len(), 2);
}

#[test]
fn the_matched_positions_are_those_of_the_name() {
    let scratch = Scratch::new();
    scratch.file("docs/invoice.pdf");
    scratch.file("docs/Übersicht.txt");
    let index = built(&scratch);
    let tree = &index.read().tree;
    assert_eq!(tree.search("inv", 10)[0].positions, [0, 1, 2]);
    assert_eq!(tree.search("ipdf", 10)[0].positions, [0, 8, 9, 10]);
    assert_eq!(tree.search("docs/inv", 10)[0].positions, [0, 1, 2], "the part of the match in the folders is left out");
    assert_eq!(tree.search("sich", 10)[0].positions, [4, 5, 6, 7], "counted in characters, not bytes");
}

#[test]
fn removed_entries_are_dropped_once_they_pile_up() {
    let mut tree = Tree::empty("/root");
    let keep = tree.push(0, "keep", true);
    tree.push(keep, "kept.txt", false);
    let churn = tree.push(0, "churn", true);
    for number in 0..5000 {
        tree.push(churn, &format!("temp-{number}"), false);
    }
    let before = tree.byte_size();
    tree.remove(churn);
    assert_eq!(tree.count(), 2);
    assert_eq!(tree.entries.len(), 5004);
    tree.compact_if_due();
    assert_eq!(tree.entries.len(), 3);
    assert_eq!(tree.count(), 2);
    assert!(tree.names.len() < 20 && before > 0);
    assert_eq!(tree.search("kept", 10)[0].path, "/root/keep/kept.txt");
    assert!(tree.search("temp", 10).is_empty());
}

fn number(block: &[u8], at: &mut usize) -> usize {
    let value = u32::from_le_bytes(block[*at..*at + 4].try_into().unwrap());
    *at += 4;
    value as usize
}

#[test]
fn the_c_functions_build_search_and_free() {
    let scratch = Scratch::new();
    scratch.file("docs/invoice.pdf");
    scratch.file("docs/node_modules/skipped.js");
    scratch.file("Photos.photoslibrary/inside.jpg");
    let root = CString::new(scratch.root()).unwrap();
    let names = [CString::new("node_modules").unwrap()];
    let suffixes = [CString::new(".PhotosLibrary").unwrap()];
    let name_pointers: Vec<*const c_char> = names.iter().map(|name| name.as_ptr()).collect();
    let suffix_pointers: Vec<*const c_char> = suffixes.iter().map(|suffix| suffix.as_ptr()).collect();
    unsafe {
        let index = floe_index_new();
        assert_eq!(floe_index_count(index), 0);
        let built = floe_index_build(index, root.as_ptr(), name_pointers.as_ptr(), 1, suffix_pointers.as_ptr(), 1, 0);
        assert_eq!(built, 3);
        assert_eq!(floe_index_count(index), 3);
        assert!(floe_index_byte_size(index) > 0);

        let query = CString::new("inv").unwrap();
        let mut length = 0;
        let block = floe_index_search(index, query.as_ptr(), 10, &mut length);
        let bytes = slice::from_raw_parts(block, length);
        let mut at = 0;
        assert_eq!(number(bytes, &mut at), 1);
        assert!(number(bytes, &mut at) > 0, "the score");
        assert_eq!(bytes[at], 0, "not a folder");
        at += 1;
        let path_length = number(bytes, &mut at);
        assert_eq!(std::str::from_utf8(&bytes[at..at + path_length]).unwrap(), scratch.path("docs/invoice.pdf"));
        at += path_length;
        assert_eq!(number(bytes, &mut at), 3);
        assert_eq!([number(bytes, &mut at), number(bytes, &mut at), number(bytes, &mut at)], [0, 1, 2]);
        assert_eq!(at, length);
        floe_index_block_free(block, length);

        scratch.file("docs/invitation.txt");
        let docs = CString::new(scratch.path("docs")).unwrap();
        floe_index_rescan(index, docs.as_ptr(), false);
        assert_eq!(floe_index_count(index), 4);

        assert!(floe_index_search(index, ptr::null(), 10, &mut length).is_null());
        assert_eq!(floe_index_build(index, ptr::null(), ptr::null(), 0, ptr::null(), 0, 0), -1);
        assert_eq!(floe_index_count(ptr::null()), 0);
        floe_index_block_free(ptr::null_mut(), 0);
        floe_index_free(index);
        floe_index_free(ptr::null_mut());
    }
}

#[test]
fn searches_run_while_the_index_is_rescanned() {
    let scratch = Scratch::new();
    for number in 0..200 {
        scratch.file(&format!("set/file-{number}.txt"));
    }
    let index = built(&scratch);
    std::thread::scope(|scope| {
        for _ in 0..4 {
            scope.spawn(|| {
                for _ in 0..50 {
                    assert!(!index.read().tree.search("file", 20).is_empty());
                }
            });
        }
        scope.spawn(|| {
            for round in 0..20 {
                scratch.file(&format!("set/extra-{round}/inner.txt"));
                index.rescan(&scratch.path("set"), round % 2 == 0);
            }
        });
    });
    assert_eq!(count(&index), 1 + 200 + 40);
}

fn best_of(runs: usize, mut work: impl FnMut()) -> Duration {
    (0..runs)
        .map(|_| {
            let started = Instant::now();
            work();
            started.elapsed()
        })
        .min()
        .unwrap_or_default()
}

/// Not a test of anything: prints how the index does on the real home folder. It reads names and nothing else.
#[test]
fn a_walk_to_a_depth_lists_that_many_levels_and_a_whole_walk_replaces_it() {
    let scratch = Scratch::new();
    scratch.file("top.txt");
    scratch.file("one/second.txt");
    scratch.file("one/two/third.txt");
    scratch.file("one/two/three/fourth.txt");
    let index = FileIndex::new();

    assert_eq!(index.build_to(scratch.root(), rules(), Some(2)), 4, "top.txt, one, and the two entries in one");
    assert_eq!(found(&index, &scratch, "second"), ["one/second.txt"]);
    assert_eq!(found(&index, &scratch, "two"), ["one/two"], "a folder at the last level is listed and not read");
    assert!(found(&index, &scratch, "third").is_empty());

    assert_eq!(index.build(scratch.root(), rules()), 7);
    assert_eq!(found(&index, &scratch, "fourth"), ["one/two/three/fourth.txt"]);
}

/// Where a test saves an index: a file of its own beside the scratch folders.
fn saved_file(scratch: &Scratch) -> String {
    format!("{}.index", scratch.root())
}

#[test]
fn a_saved_index_comes_back_with_the_same_names_and_keeps_following_the_disk() {
    let scratch = Scratch::new();
    scratch.file("docs/report.txt");
    scratch.file("docs/deep/notes.md");
    scratch.folder("Photos.photoslibrary/inside");
    let file = saved_file(&scratch);
    assert!(built(&scratch).save(&file));

    let loaded = FileIndex::new();
    assert_eq!(loaded.load(&file, scratch.root(), rules()), Some(5));
    assert_eq!(found(&loaded, &scratch, "report"), ["docs/report.txt"]);
    assert_eq!(found(&loaded, &scratch, "deep/notes"), ["docs/deep/notes.md"]);
    assert!(loaded.read().tree.search("photos", 10)[0].is_folder);

    scratch.file("docs/later.txt");
    loaded.rescan(&scratch.path("docs"), false);
    assert_eq!(found(&loaded, &scratch, "later"), ["docs/later.txt"]);
    assert_eq!(count(&loaded), 6);
    let _ = fs::remove_file(file);
}

#[test]
fn what_was_removed_before_saving_is_not_in_the_saved_index() {
    let scratch = Scratch::new();
    scratch.file("keep/one.txt");
    scratch.file("gone/two.txt");
    let index = built(&scratch);
    fs::remove_dir_all(scratch.path("gone")).unwrap();
    index.rescan(scratch.root(), false);
    let file = saved_file(&scratch);
    assert!(index.save(&file));

    let loaded = FileIndex::new();
    assert_eq!(loaded.load(&file, scratch.root(), rules()), Some(2));
    assert!(found(&loaded, &scratch, "two").is_empty());
    assert_eq!(loaded.read().tree.dead, 0, "the saved file holds no room for what was removed");
    let _ = fs::remove_file(file);
}

#[test]
fn a_saved_index_is_refused_for_another_folder_or_other_rules() {
    let scratch = Scratch::new();
    scratch.file("one.txt");
    let file = saved_file(&scratch);
    assert!(built(&scratch).save(&file));

    let loaded = FileIndex::new();
    assert_eq!(loaded.load(&file, "/somewhere/else", rules()), None);
    let other = Rules { excluded_names: vec!["node_modules".into()], ..rules() };
    assert_eq!(loaded.load(&file, scratch.root(), other), None);
    assert_eq!(count(&loaded), 0, "a refused file leaves the index as it was");
    assert_eq!(loaded.load(&file, scratch.root(), rules()), Some(1));
    let _ = fs::remove_file(file);
}

#[test]
fn a_file_that_is_cut_short_damaged_or_something_else_is_refused() {
    let scratch = Scratch::new();
    scratch.file("docs/one.txt");
    scratch.file("docs/two.txt");
    let file = saved_file(&scratch);
    assert!(built(&scratch).save(&file));
    let whole = fs::read(&file).unwrap();
    let loaded = FileIndex::new();

    for length in 0..whole.len() {
        fs::write(&file, &whole[..length]).unwrap();
        assert_eq!(loaded.load(&file, scratch.root(), rules()), None, "cut to {length} bytes");
    }
    // Every byte in turn: a damaged file is refused or read as names, and never brings the index down.
    for place in 0..whole.len() {
        let mut damaged = whole.clone();
        damaged[place] ^= 0xFF;
        fs::write(&file, &damaged).unwrap();
        if loaded.load(&file, scratch.root(), rules()).is_some() {
            let _ = loaded.read().tree.search("o", 10);
        }
    }
    fs::write(&file, "not an index").unwrap();
    assert_eq!(loaded.load(&file, scratch.root(), rules()), None);
    assert_eq!(loaded.load(&scratch.path("missing.index"), scratch.root(), rules()), None);
    let _ = fs::remove_file(file);
}

/// Saves a tree made by hand, as a damaged or crafted file could hold one.
fn saved_tree(scratch: &Scratch, tree: &Tree) -> String {
    let mut bytes = Vec::new();
    tree.write(&mut bytes, &rules()).unwrap();
    let file = saved_file(scratch);
    fs::write(&file, bytes).unwrap();
    file
}

#[test]
fn a_file_deeper_than_its_depths_say_or_with_too_long_a_path_is_refused() {
    let scratch = Scratch::new();
    let loaded = FileIndex::new();

    // A depth stops at 255, so the levels past it would carry the same depth as their folder.
    let mut deep = Tree::empty(scratch.root());
    let mut folder = 0;
    for _ in 0..300 {
        folder = deep.push(folder, "a", true);
    }
    let file = saved_tree(&scratch, &deep);
    assert_eq!(loaded.load(&file, scratch.root(), rules()), None);

    let mut long = Tree::empty(scratch.root());
    let name = "n".repeat(30_000);
    let mut folder = 0;
    for _ in 0..3 {
        folder = long.push(folder, &name, true);
    }
    let file = saved_tree(&scratch, &long);
    assert_eq!(loaded.load(&file, scratch.root(), rules()), None);

    let mut fine = Tree::empty(scratch.root());
    let top = fine.push(0, &name, true);
    fine.push(top, "inside.txt", false);
    let file = saved_tree(&scratch, &fine);
    assert_eq!(loaded.load(&file, scratch.root(), rules()), Some(2));
    let _ = fs::remove_file(file);
}

#[test]
fn rules_that_differ_never_save_as_the_same() {
    let joined = Rules { excluded_names: vec!["a\nb".into()], package_suffixes: Vec::new() };
    let split = Rules { excluded_names: vec!["a".into(), "b".into()], package_suffixes: Vec::new() };
    let moved = Rules { excluded_names: Vec::new(), package_suffixes: vec!["a\nb".into()] };
    assert_ne!(joined.identity(), split.identity());
    assert_ne!(joined.identity(), moved.identity());

    let scratch = Scratch::new();
    scratch.file("one.txt");
    let index = FileIndex::new();
    index.build(scratch.root(), joined);
    let file = saved_file(&scratch);
    assert!(index.save(&file));
    assert_eq!(FileIndex::new().load(&file, scratch.root(), split), None);

    let mut old = fs::read(&file).unwrap();
    old[7] = 1;
    fs::write(&file, old).unwrap();
    assert_eq!(FileIndex::new().load(&file, scratch.root(), Rules { excluded_names: vec!["a\nb".into()], package_suffixes: Vec::new() }), None, "a file of the version before");
    let _ = fs::remove_file(file);
}

#[test]
fn a_file_whose_names_share_bytes_or_leave_some_over_is_refused() {
    let scratch = Scratch::new();
    let loaded = FileIndex::new();
    let mut tree = Tree::empty(scratch.root());
    let folder = tree.push(0, "folder", true);
    tree.push(folder, "a", false);
    tree.push(folder, "b", false);
    let file = saved_tree(&scratch, &tree);
    assert_eq!(loaded.load(&file, scratch.root(), rules()), Some(3));

    // Every entry pointing at one long name would make each search put together far more than the file holds.
    let mut shared = Tree::empty(scratch.root());
    shared.push(0, &"n".repeat(1000), false);
    for _ in 0..3 {
        shared.entries.push(shared.entries[1]);
    }
    let file = saved_tree(&scratch, &shared);
    assert_eq!(loaded.load(&file, scratch.root(), rules()), None);

    let mut over = Tree::empty(scratch.root());
    over.push(0, "a", false);
    over.names.extend_from_slice(b"unused");
    let file = saved_tree(&scratch, &over);
    assert_eq!(loaded.load(&file, scratch.root(), rules()), None);
    assert_eq!(count(&loaded), 3, "a refused file leaves the index as it was");
    let _ = fs::remove_file(file);
}

#[test]
fn a_save_writes_over_nothing_but_its_own_file() {
    let scratch = Scratch::new();
    scratch.file("one.txt");
    let index = built(&scratch);
    let file = saved_file(&scratch);
    let victim = scratch.path("victim.txt");
    fs::write(&victim, "keep").unwrap();
    // The name the unfinished file once had, set as a trap: a link to a file of someone else's, and a plain file.
    std::os::unix::fs::symlink(&victim, format!("{file}.unfinished")).unwrap();

    assert!(index.save(&file));
    assert!(index.save(&file), "and again over the saved one");
    assert_eq!(fs::read_to_string(&victim).unwrap(), "keep");
    assert!(fs::symlink_metadata(format!("{file}.unfinished")).unwrap().file_type().is_symlink());
    assert_eq!(FileIndex::new().load(&file, scratch.root(), rules()), Some(1));

    let parent = std::path::Path::new(&file).parent().unwrap();
    let prefix = std::path::Path::new(&file).file_name().unwrap().to_str().unwrap().to_owned();
    let left: Vec<_> = fs::read_dir(parent).unwrap().flatten().filter(|entry| {
        let name = entry.file_name().to_string_lossy().into_owned();
        name.starts_with(&prefix) && name != prefix && name != format!("{prefix}.unfinished")
    }).collect();
    assert!(left.is_empty(), "no unfinished file is left behind");
    let _ = fs::remove_file(format!("{file}.unfinished"));
    let _ = fs::remove_file(file);
}

#[test]
fn a_save_clears_unfinished_files_left_long_ago_and_nothing_else() {
    let scratch = Scratch::new();
    scratch.file("one.txt");
    let index = built(&scratch);
    let file = saved_file(&scratch);
    let victim = scratch.path("victim.txt");
    fs::write(&victim, "keep").unwrap();
    let hours_ago = std::time::SystemTime::now() - std::time::Duration::from_secs(2 * 60 * 60);
    let left_long_ago = format!("{file}.00000000000000aa.unfinished");
    fs::File::create(&left_long_ago).unwrap().set_modified(hours_ago).unwrap();
    // Another save may be writing this one right now.
    let being_written = format!("{file}.00000000000000bb.unfinished");
    fs::write(&being_written, "").unwrap();
    let link = format!("{file}.00000000000000cc.unfinished");
    std::os::unix::fs::symlink(&victim, &link).unwrap();
    let not_ours = format!("{file}.notes.unfinished");
    fs::File::create(&not_ours).unwrap().set_modified(hours_ago).unwrap();

    assert!(index.save(&file));
    assert!(fs::symlink_metadata(&left_long_ago).is_err(), "an unfinished file hours old is removed");
    assert!(fs::metadata(&being_written).is_ok(), "a new one is left to the save writing it");
    assert!(fs::symlink_metadata(&link).unwrap().file_type().is_symlink(), "a link is left alone");
    assert_eq!(fs::read_to_string(&victim).unwrap(), "keep");
    assert!(fs::metadata(&not_ours).is_ok(), "a name the index does not make is left alone");
    for leftover in [&being_written, &link, &not_ours, &file] {
        let _ = fs::remove_file(leftover);
    }
}

#[test]
fn an_index_that_was_never_built_saves_nothing() {
    let scratch = Scratch::new();
    assert!(!FileIndex::new().save(&saved_file(&scratch)));
    assert!(!built(&scratch).save(&scratch.path("no/such/folder/saved.index")));
}

/// `cargo test --release -- --ignored --nocapture measures_the_home_folder`
#[test]
#[ignore]
fn measures_the_home_folder() {
    let home = std::env::var("HOME").unwrap();
    let names = ["Library", "node_modules", ".git", ".Trash", ".build", "target", "DerivedData", ".cache", "Pods", ".npm", ".cargo", ".rustup"];
    let suffixes = [".app", ".framework", ".bundle", ".plugin", ".kext", ".xcodeproj", ".xcworkspace", ".xcassets", ".photoslibrary", ".lproj"];
    let rules = || Rules {
        excluded_names: names.iter().map(|name| (*name).to_owned()).collect(),
        package_suffixes: suffixes.iter().map(|suffix| (*suffix).to_owned()).collect(),
    };
    let index = FileIndex::new();
    let started = Instant::now();
    let entries = index.build(&home, rules());
    println!("entries: {entries}");
    println!("first build: {:?}", started.elapsed());
    println!("second build: {:?}", best_of(2, || {
        index.build(&home, rules());
    }));
    let file = std::env::temp_dir().join(format!("floe-index-{}.measure", std::process::id()));
    let file = file.to_str().unwrap();
    println!("save: {:?}", best_of(3, || assert!(index.save(file))));
    println!("saved file: {:.1} MB", fs::metadata(file).unwrap().len() as f64 / 1e6);
    println!("load: {:?}", best_of(3, || assert!(FileIndex::new().load(file, &home, rules()).is_some())));
    let _ = fs::remove_file(file);
    let tree = &index.read().tree;
    println!("approximate memory: {:.1} MB ({:.1} MB of names)", tree.byte_size() as f64 / 1e6, tree.names.len() as f64 / 1e6);
    // A folder macOS would not let this process read shows up here with nothing in it.
    for folder in ["Desktop", "Documents", "Downloads"] {
        let inside = tree.child(0, folder).and_then(|id| tree.children.get(&id)).map_or(0, Vec::len);
        println!("directly in {folder}: {inside}");
    }
    for query in ["inv", "readme", "floe swift", "launcherpanel", "src/main", "zqxjkvwpyfgh"] {
        let mut hits = 0;
        let time = best_of(20, || hits = tree.search(query, 50).len());
        println!("search {query:?}: {time:?}, {hits} shown");
    }
}
