
# Path safety

A [container](./README.md#containers) comes from whoever made the patch or
signature, so a reader must not trust its paths. Before creating anything on
disk, a reader must check every entry of every container it is about to apply
against the rules below. If any entry breaks a rule, it must reject the whole
container.

In the reference implementation, `Container.Validate` in [lake][] enforces
these rules and reports violations as an error wrapping `tlc.ErrUnsafePaths`.

[lake]: https://github.com/itchio/lake

## Entry paths

These rules apply to the `path` of every `File`, `Dir` and `Symlink`. A path
must:

  * not be empty or `.`
  * be at most 1024 bytes long
  * not contain NUL, `\` or `:`. Banning `:` also rules out drive letters
  (`C:/x`) and NTFS alternate data streams (`a.txt:stream`).
  * not start with `/`
  * be clean, meaning unchanged by Go's [`path.Clean`][path.Clean]. So no
  `//`, no trailing `/`, no `.` components, and no `x/..`.

Each `/`-separated component must:

  * not be `..`
  * not consist only of dots and spaces. Win32 strips trailing dots and
  spaces from names, so `.. ` would mean `..` and `...` would mean `.`.
  Names that merely start with dots, like `..hidden`, are fine.
  * be at most 255 bytes long
  * not be a Windows device name (see below)

[path.Clean]: https://pkg.go.dev/path#Clean

## Windows device names

Win32 opens a device instead of a file for these names, in any directory and
with any extension. To check a component:

  1. Strip trailing dots and spaces, and convert to upper case.
  2. Cut everything from the first `.`, then strip trailing spaces again.
  3. Reject the component if the result is `CON`, `PRN`, `AUX`, `NUL`,
  `CONIN$` or `CONOUT$`, or `COM` or `LPT` followed by exactly one of
  `1` to `9`, `¹`, `²` or `³`.

| Rejected | Accepted |
|---|---|
| `nul`, `nul `, `data/CON.txt`, `data/com1.`, `com¹.txt`, `CONIN$` | `console.txt`, `nullable.txt`, `auxiliary/x`, `com10`, `lpt0` |

## Entry modes

A `File` whose mode has the symlink bit set could be extracted as a symlink,
skipping every symlink check below. So:

  * The only type bit allowed is the one for the entry's own kind: `0x80000000`
  on a `Dir`, `0x08000000` on a `Symlink`, none on a `File`. No type bits at
  all is also fine. The type bits are `0x8F280000` (directory, symlink,
  device, named pipe, socket, character device, irregular).
  * Setuid (`0x00800000`) is rejected on every entry.
  * Setgid (`0x00400000`) is rejected on files and symlinks, and allowed on
  directories.

## Symlink targets

A symlink's `dest` must:

  * not be empty
  * be at most 1024 bytes long
  * not contain NUL, `\` or `:`, and not start with `/`
  * not have any component made only of dots and spaces, other than the empty
  component, `.` and `..`. Targets do not have to be clean: `lib/` and
  `../lib64/../lib/tool` are fine.

A target may point to something that isn't in the container
(`nowhere/at/all` is fine), but it must not escape the container.

To check, resolve the link's directory followed by its target, one component
at a time, starting from the container root. `.` and empty components do
nothing. `..` goes up one level, and the link escapes if that goes above the
root. When a component names another symlink in the container, replace it
with that symlink's target and keep going. Escaping through a chain such as
`d -> .` followed by `e -> d/../outside.txt` must be caught.

The container may be extracted onto a volume that ignores case, normalizes
Unicode, or strips trailing dots, where several spellings name the same entry.
To compare a component with symlink paths, a reader must fold both:

  1. Remove the code points HFS+ ignores: U+200C to U+200F, U+202A to U+202E,
  U+206A to U+206F, and U+FEFF.
  2. Strip trailing dots and spaces.
  3. Apply Unicode NFKD, then full Unicode case folding.
  4. Map U+2D00 to U+2D25 onto U+10D0 to U+10F5, so that Georgian matches
  both modern folding and HFS+.

When a component folds to the same key as one or more symlinks, the walk must
follow each of them. If none of them has exactly that spelling, it must also
go on as if the component were a plain directory, which is what a
case-sensitive volume would do. The link is rejected if any of these paths
escapes. Some escapes this catches:

| Symlinks | Escape |
|---|---|
| `d -> .`, `e -> D/../outside.txt` | case folding |
| `café -> .` with `é` as U+00E9, `e -> café/../outside` with `e` + U+0301 | Unicode normalization |
| `ſ -> .`, `e -> s/../outside` | full case folding |
| `d -> .`, `e -> d./../outside` | trailing dot stripping |
| `d -> .`, `e -> d‌/../outside` with U+200C after `d` | HFS+ ignorable code point |

The walk is bounded. A link is treated as escaping if resolving it follows
more than 40 symlinks (which also rejects cycles like `a -> b`, `b -> a`),
takes more than 10,000 component steps, or would push the container past
2,000,000 steps in total.

## Entries under symlinks

An entry whose parent directory, or any ancestor, folds to the path of a
symlink would be written through that link. Such entries are rejected. For
example, a container with a symlink `a -> dir` can't also hold a file `A/x`,
and one with a symlink `X -> .` can't hold `x/UP/poc.txt`.

## Structural checks

A container must also not have two entries with the same path, or use a
file or symlink as the parent of another entry. The reference implementation
reports these as ordinary validation errors, not `ErrUnsafePaths`.

## Checking the disk while writing

These rules only cover the container itself. Files already in the
destination, or entries created earlier in the same install, can still change
where a path leads. While writing, a reader should also refuse to:

  * write through a parent directory that is a symlink on disk
  * open a file path that is a symlink on disk
  * create a symlink whose target, joined to the link's directory, lands
  outside the destination
