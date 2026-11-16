
# The wharf patch format (.pwr)

A patch contains everything needed to turn the `old` container into the `new`
one: both containers' metadata, and, for every file of `new`, instructions to
rebuild it from `old` files and fresh data.

*Read the [framing rules](./README.md) first: the "messages" below are
length-prefixed protobuf messages, and the containers and compression settings
are described there.*

## Layout

```
magic           int32 LE = 0x0FEF5F00
PatchHeader     (uncompressed)
--- compressed stream, as specified by PatchHeader.compression ---
Container       old container
Container       new container
for each file in new.files, in order:
  SyncHeader
  if SyncHeader.type == RSYNC:
    SyncOp*                 BLOCK_RANGE or DATA
    SyncOp                  type = HEY_YOU_DID_IT
  if SyncHeader.type == BSDIFF:
    BsdiffHeader
    Control*                eof = false
    Control                 eof = true
    SyncOp                  type = HEY_YOU_DID_IT
--- end of stream ---
```

The `old` container comes first. There is exactly one file series per file in
`new.files`, in the same order, even for empty files. Directories and symlinks
have no series: they are fully described by the `new` container.

## Messages

These are defined in [pwr.proto][pwr.proto] (package `io.itch.wharf.pwr`)
and [bsdiff.proto][bsdiff.proto] (package `io.itch.wharf.bsdiff`).

```protobuf
message PatchHeader {
  CompressionSettings compression = 1;
}

message SyncHeader {
  enum Type {
    RSYNC = 0;
    BSDIFF = 1;
  }

  Type type = 1;
  int64 fileIndex = 16;
}

message SyncOp {
  enum Type {
    BLOCK_RANGE = 0;
    DATA = 1;
    HEY_YOU_DID_IT = 2049;
  }
  Type type = 1;

  int64 fileIndex = 2;
  int64 blockIndex = 3;
  int64 blockSpan = 4;
  bytes data = 5;
}

message BsdiffHeader {
  int64 targetIndex = 1;
}

// in package io.itch.wharf.bsdiff
message Control {
  bytes add = 1;
  bytes copy = 2;
  int64 seek = 3;
  bool eof = 4;
}
```

Note that `SyncHeader.fileIndex` is field number 16, not 2.

`PatchHeader.compression` must be present, even when both of its fields are
default. The reference reader rejects a header without it.

[pwr.proto]: https://github.com/itchio/wharf/blob/master/pwr/pwr.proto
[bsdiff.proto]: https://github.com/itchio/wharf/blob/master/bsdiff/bsdiff.proto

## File series

### SyncHeader

`SyncHeader.fileIndex` is the index of the file being rebuilt, in the `new`
container. Series are written in order, so for the *n*th series it is always
*n*. A reader should reject a patch where they differ.

`SyncHeader.type` selects how the file is rebuilt. Patches produced by
`butler diff` or `butler push` only contain `RSYNC` series. `BSDIFF` series
appear in patches that went through the [optimization pass](../algorithms/bsdiff.md).

### RSYNC series

An RSYNC series is a list of `SyncOp` messages, applied in order, each one
appending bytes to the new file. It ends with a `SyncOp` of type
`HEY_YOU_DID_IT`, whose other fields are unset.

A `DATA` op appends `data` verbatim. The reference differ never puts more
than 4 MiB in a single DATA op. `fileIndex`, `blockIndex` and `blockSpan`
are unset.

A `BLOCK_RANGE` op copies bytes from a file of the `old` container:

  * `fileIndex` is the index of the source file in the old container
  * the copy starts at byte offset `blockIndex * 65536`
  * it covers `blockSpan` blocks. All blocks are 65536 bytes except the last
  block of the old file, which may be shorter. The number of bytes copied is:

```
lastIndex = blockIndex + blockSpan - 1
lastSize  = 65536
if 65536 * (lastIndex + 1) > oldFileSize:
  lastSize = oldFileSize % 65536
count = (blockSpan - 1) * 65536 + lastSize
```

`data` is unset. The block size is fixed at 64 KiB and is not stored in the
patch.

Some details implementations should handle:

  * Empty new files. The differ emits one zero-length DATA op, then
  `HEY_YOU_DID_IT`. Writers must emit at least one op per RSYNC series: the
  reference patcher rejects a series whose first message is
  `HEY_YOU_DID_IT`.
  * Whole-file copies. If the first op is a BLOCK_RANGE with
  `blockIndex = 0`, the old file has the same size as the new file, and
  `blockSpan` equals the number of blocks in the new file, the file is a copy
  of that old file (unchanged, or renamed when the paths differ). A patcher
  can move or keep the old file instead of copying bytes. Older versions of
  butler sometimes wrote a zero-length DATA op after such a BLOCK_RANGE, so
  readers should ignore anything between a whole-file BLOCK_RANGE and the
  terminator.

See [Applying patches](../algorithms/apply.md) for how files, directories and
symlinks are created around these operations.

### BSDIFF series

A BSDIFF series rebuilds the new file from a single old file with the
[bsdiff](../algorithms/bsdiff.md) algorithm:

  1. A `BsdiffHeader`. `targetIndex` is the index of the old file in the
  old container.
  2. Zero or more `Control` messages with `eof = false`.
  3. One `Control` message with `eof = true`. Its other fields are ignored.
  4. A `SyncOp` of type `HEY_YOU_DID_IT`. Anything else here means the patch
  is corrupt.

To apply it, keep an `oldOffset` into the old file, starting at 0, and apply
each Control in order:

```
for i in 0 ..< len(add):
  output(byte((old[oldOffset + i] + add[i]) mod 256))
oldOffset += len(add)

output(copy)

oldOffset += seek
```

`seek` is signed and may be negative. After the last Control, the number of
bytes written must equal the new file's size in the `new` container,
otherwise the patch is corrupt.

## Example

This is the start and end of a real patch written by the reference
implementation with `NONE` compression, from `/dev/null` (the empty container) to a container
holding a 100,000-byte file `a.dat` and an empty file `empty`:

```
00 5F EF 0F                 magic
02 0A 00                    PatchHeader {compression: {}}  (NONE, quality 0)
00                          Container {}  (old: empty)
25 0A 0E 0A 05 61 2E ...    Container {files: [a.dat, empty], size: 100000}  (new)

00                          SyncHeader {type: RSYNC, fileIndex: 0}
A6 8D 06 08 01 2A A0 8D 06  SyncOp {type: DATA, data: <100000 bytes>}  (header only)
  ...100000 bytes...
03 08 81 10                 SyncOp {type: HEY_YOU_DID_IT}

03 80 01 01                 SyncHeader {type: RSYNC, fileIndex: 1}
02 08 01                    SyncOp {type: DATA}  (zero-length data)
03 08 81 10                 SyncOp {type: HEY_YOU_DID_IT}
```

## Relation to signatures

When the reference implementation writes a patch, it also writes a
[signature](./signatures.md) of the `new` container from the same reads of
the new files. A backend can store it to diff the next version against this
one without access to the files.
