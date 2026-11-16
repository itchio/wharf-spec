
# Optimizing patches with bsdiff

The [diff algorithm](./diff.md) only needs a signature of the `old` container,
which makes it cheap enough to run on the uploader's machine. Its weakness is
that any change inside a 64 KiB block makes the whole block fresh data.
Executables and packed assets often change a few bytes in many places, and
the resulting patches can be nearly as large as the files themselves.

To fix that, an existing patch can be rewritten, replacing some RSYNC file
series with BSDIFF series. The reference implementation calls this pass
"rediff", and butler exposes it as `butler rediff`. It needs full access to
both the `old` and `new` containers, so it is meant to run on a backend after
an upload, not on the uploader's machine.

The result uses the same [patch format](../file-formats/patches.md). A
patcher that supports both series types can apply either version.

## bsdiff

[bsdiff][] is Colin Percival's binary diff algorithm. It finds approximate
matches between the old and new file using a suffix array of the old file,
then encodes the new file as a sequence of controls, each made of three
parts:

  * add: a run of bytes that approximately matches a region of the old
  file, stored as the byte-wise difference `new - old` (mod 256). Where
  the two regions are identical, the difference is all zeros, which
  compresses very well.
  * copy: bytes from the new file with no match in the old file, stored
  verbatim (the "extra" string in the original bsdiff).
  * seek: how far to move in the old file before the next add.

Unlike the original bsdiff, wharf does not store these as three separately
compressed streams. Each control is one protobuf message:

```protobuf
message Control {
  bytes add = 1;
  bytes copy = 2;
  int64 seek = 3;
  bool eof = 4;
}
```

[bsdiff]: http://www.daemonology.net/bsdiff/

### Producing controls

The suffix array scan produces a list of matches. Each has an `addOldStart`,
an `addNewStart`, an `addLength`, and `copyEnd`, the end of the unmatched
region that follows it in the new file. Each match becomes one control:

```
add[k] = (new[addNewStart + k] - old[addOldStart + k]) mod 256,  for k in 0 ..< addLength
copy   = new[addNewStart + addLength ..< copyEnd]
seek   = next.addOldStart - (addOldStart + addLength)     // 0 for the last match
```

The last control is followed by `Control {eof: true}`. If the new file is
empty, that is the only control.

### Applying controls

Keep `oldOffset`, starting at 0. For each control with `eof = false`:

  1. Read `len(add)` bytes from the old file at `oldOffset`, add `add[k]` to
  each one (mod 256), and write the result. Advance `oldOffset` by `len(add)`.
  2. Write `copy`.
  3. Add `seek` (which may be negative) to `oldOffset`.

Reading past the end of the old file during step 1 is an error. When the
`eof` control is reached, the output size must equal the new file size
recorded in the `new` container.

### Limits

bsdiff holds both files in memory, along with a suffix array of the old file,
so memory use grows with file size. rediff therefore skips any pair where
either file is larger than a size limit, 4 GiB by default.

## The rediff pass

rediff reads the original patch twice.

### Analysis

For each file series of the original patch, rediff adds up how many bytes
each BLOCK_RANGE reuses from each `old` file. It then picks a single old file
to bsdiff the new file against:

  * Files that are empty in `new` are left alone.
  * Series made of exactly one BLOCK_RANGE and no DATA (unchanged or renamed
  files) are left alone.
  * Otherwise, the old file that contributed the most bytes is chosen. On a
  tie, an old file with the same path wins.
  * If no old file contributed any block, but an old file with the same path
  exists and is not empty, that one is chosen.
  * Files over the size limit are left alone.

### Optimization

rediff then writes a new patch:

  1. The magic, a new `PatchHeader`, and both containers, copied from the
  original. The compression settings may differ from the original's.
  2. For each file series:
     * If no old file was picked, the original `SyncHeader` and SyncOps are
     copied unchanged.
     * Otherwise, rediff writes `SyncHeader {type: BSDIFF}`, then
     `BsdiffHeader {targetIndex}` with the picked old file, then the bsdiff
     controls computed from the old and new file contents. The original
     SyncOps are discarded.
  3. Every series, of either type, ends with `SyncOp {type: HEY_YOU_DID_IT}`.

A BSDIFF series always rebuilds the whole file from one old file. It can't
mix in blocks from other old files the way RSYNC series can.
