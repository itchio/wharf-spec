
# The wharf wounds format (.pww)

A wounds file lists the parts of an installed container that don't match its
[signature](./signatures.md): missing directories, wrong or missing symlinks,
and damaged byte ranges of files. It is produced when verifying a
container (`butler verify --wounds`), and the list can be used to repair
("heal") only the damaged parts.

*Read the [framing rules](./README.md) first.*

## Layout

```
magic           int32 LE = 0x0FEF5F03
WoundsHeader
Container       the container that was checked
Wound*          until end of file
```

Wounds files are never compressed: `WoundsHeader` has no compression
settings, and every message follows the magic directly in plain
length-prefixed form. `WoundsHeader` currently has no fields, so it is always
written as the single byte `0x00`.

The reference implementation only creates the file when it finds the first
wound. If the container is intact, no file is written.

```protobuf
message WoundsHeader {}

enum WoundKind {
  FILE = 0;
  SYMLINK = 1;
  DIR = 2;
  CLOSED_FILE = 3;
}

message Wound {
  int64 index = 1;
  int64 start = 2;
  int64 end = 3;
  WoundKind kind = 4;
}
```

## Wounds

`index` is an index into the list of the container that matches `kind`:

| kind | `index` refers to | `start`, `end` |
|---|---|---|
| `FILE` | `Container.files` | the damaged byte range, `[start, end)` |
| `SYMLINK` | `Container.symlinks` | unused |
| `DIR` | `Container.dirs` | unused |
| `CLOSED_FILE` | `Container.files` | the byte range that was checked and found valid |

A `DIR` wound means the directory is missing or is not a directory. A
`SYMLINK` wound means the symlink is missing or doesn't point to
`Symlink.dest`.

`FILE` wounds come in two forms:

  * Whole-file and tail wounds. A missing file, or a path that is a
  directory or symlink, gets one wound covering the whole file: `start = 0`,
  `end = File.size`. A file shorter than expected gets one wound from its
  actual size to `File.size`. These are not merged with anything, so they can
  be as large as the file.
  * Block wounds. Each 64 KiB block that doesn't match the signature produces
  a wound for that block, so its boundaries are multiples of 65536 except at
  the end of the file. Runs of adjacent bad blocks in the same file are merged
  until they reach 4 MiB, so a merged wound can exceed 4 MiB by up to one
  block. A valid block in between ends the run.

Readers must not assume any upper bound on the size of a wound. The size of a
wound is `end - start`.

`CLOSED_FILE` is used inside the reference validator to report progress and
does not mean damage. It is never written to wounds files, and readers should
ignore it if they see one.
