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
fn capitals_in_the_query_have_to_match_and_small_letters_match_both() {
    let scratch = Scratch::new();
    scratch.file("Makefile");
    scratch.file("makefile.bak");
    let index = built(&scratch);
    assert_eq!(found(&index, &scratch, "Make"), ["Makefile"]);
    assert_eq!(found(&index, &scratch, "make").len(), 2);
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
        let built = floe_index_build(index, root.as_ptr(), name_pointers.as_ptr(), 1, suffix_pointers.as_ptr(), 1);
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
        assert_eq!(floe_index_build(index, ptr::null(), ptr::null(), 0, ptr::null(), 0), -1);
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
