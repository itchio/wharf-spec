
# The wharf signature format (.pwr.sig)

A signature describes a container and lists the hashes of every block of
every file, without including the file contents. It is used:

  * as the `old` side of the [diff algorithm](../algorithms/diff.md), so a
  new version can be diffed against a previous one without its files
  * to verify a container after patching, and to find damaged blocks
  (see [wounds](./wounds.md))

*Read the [framing rules](./README.md) first.*

The reference implementation writes a signature alongside every patch, and
can also compute one directly from a container's files. butler names them
`patch.pwr.sig`. The `.pws` extension is also used.

## Layout

```
magic             int32 LE = 0x0FEF5F01
SignatureHeader   (uncompressed)
--- compressed stream, as specified by SignatureHeader.compression ---
Container
BlockHash*        until end of stream
```

```protobuf
message SignatureHeader {
  CompressionSettings compression = 1;
}

message BlockHash {
  uint32 weakHash = 1;
  bytes strongHash = 2;
}
```

There is no per-file separator. Hashes are written for each file in
`Container.files` order, one per block, and the reader works out which hash
belongs to which block from the file sizes (see "Anchoring block hashes" in
[the diff algorithm](../algorithms/diff.md)).

## Blocks

Files are cut into blocks of 65536 bytes. The last block of a file is
shorter if the file size is not a multiple of 65536. A file of size `s` has:

  * `ceil(s / 65536)` hashes when `s > 0`
  * one hash when `s = 0`: the hash of a zero-length block

The single hash for empty files is kept for compatibility with existing
signatures. Readers must consume it.

Directories and symlinks have no hashes.

## Hashes

`strongHash` is the 16-byte MD5 digest of the block.

`weakHash` is the rsync rolling checksum of the block:

```
a = 0, b = 0                              (uint32, wrapping)
for i, byte in block:
  a += byte
  b += (len(block) - i) * byte
weakHash = (a mod 65536) + 65536 * (b mod 65536)
```

For a zero-length block, `weakHash` is 0 and is omitted from the encoded
message, and `strongHash` is the MD5 of the empty string
(`d41d8cd98f00b204e9800998ecf8427e`).

See the [Hashes appendix](../appendix/hashes.md) for why these two hashes
were chosen.
