//! Folders read through what was opened, not by their paths again: a folder swapped for a link while it waits to be
//! read is not followed out of the root.

use std::ffi::{CString, OsStr};
use std::fs::OpenOptions;
use std::os::fd::{AsRawFd, FromRawFd, IntoRawFd, OwnedFd};
use std::os::raw::{c_char, c_int, c_void};
use std::os::unix::ffi::OsStrExt;
use std::os::unix::fs::OpenOptionsExt;

// From macOS's fcntl.h and dirent.h.
const O_DIRECTORY: c_int = 0x0010_0000;
const O_CLOEXEC: c_int = 0x0100_0000;
/// Refuses a link anywhere on the way, the last step too. macOS refuses it together with O_NOFOLLOW.
const O_NOFOLLOW_ANY: c_int = 0x2000_0000;
const DT_UNKNOWN: u8 = 0;
const DT_DIR: u8 = 4;

/// macOS's `struct dirent` with 64-bit file numbers, the one the functions below fill.
#[repr(C)]
struct Dirent {
    _ino: u64,
    _seekoff: u64,
    _reclen: u16,
    namlen: u16,
    kind: u8,
    name: [c_char; 1024],
}

extern "C" {
    fn openat(folder: c_int, path: *const c_char, flags: c_int, ...) -> c_int;
    // On Intel the 64-bit file numbers have names of their own; on Apple silicon they are the only kind.
    #[cfg_attr(target_arch = "x86_64", link_name = "fdopendir$INODE64")]
    fn fdopendir(descriptor: c_int) -> *mut c_void;
    #[cfg_attr(target_arch = "x86_64", link_name = "readdir$INODE64")]
    fn readdir(listing: *mut c_void) -> *const Dirent;
    fn closedir(listing: *mut c_void) -> c_int;
}

/// An open folder.
pub(super) struct Folder(OwnedFd);

/// The folder `relative` below the open folder `folder`, or None when it is not a folder or any step of the way is a link.
fn open_below(folder: c_int, relative: &str) -> Option<Folder> {
    let path = CString::new(if relative.is_empty() { "." } else { relative }).ok()?;
    let descriptor = unsafe { openat(folder, path.as_ptr(), O_DIRECTORY | O_NOFOLLOW_ANY | O_CLOEXEC) };
    (descriptor >= 0).then(|| Folder(unsafe { OwnedFd::from_raw_fd(descriptor) }))
}

impl Folder {
    /// The folder at `path`, through whatever links lead there: the root the person chose.
    pub(super) fn open(path: &str) -> Option<Self> {
        let file = OpenOptions::new().read(true).custom_flags(O_DIRECTORY).open(path).ok()?;
        Some(Self(file.into()))
    }

    /// The folder `relative` below this one, or None when it is not a folder or any step of the way is a link.
    pub(super) fn inside(&self, relative: &str) -> Option<Self> {
        open_below(self.0.as_raw_fd(), relative)
    }

    /// Calls `each` with every name in the folder but `.` and `..`, and whether it is a folder. A link is not one.
    pub(super) fn list(self, mut each: impl FnMut(&OsStr, bool)) {
        let descriptor = self.0.into_raw_fd();
        let listing = unsafe { fdopendir(descriptor) };
        if listing.is_null() {
            drop(unsafe { OwnedFd::from_raw_fd(descriptor) });
            return;
        }
        // The listing holds the descriptor from here on, and closes it.
        while let Some(entry) = unsafe { readdir(listing).as_ref() } {
            let name = unsafe { std::slice::from_raw_parts(entry.name.as_ptr().cast::<u8>(), usize::from(entry.namlen)) };
            if name == b"." || name == b".." {
                continue;
            }
            let name = OsStr::from_bytes(name);
            // Some file systems do not say what an entry is: opening it as a folder, never through a link, does.
            let is_dir = match entry.kind {
                DT_DIR => true,
                DT_UNKNOWN => name.to_str().is_some_and(|name| open_below(descriptor, name).is_some()),
                _ => false,
            };
            each(name, is_dir);
        }
        unsafe { closedir(listing) };
    }
}
