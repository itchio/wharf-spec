
# File formats

All wharf files share the same framing. This page describes it. The pages for
each format describe the sequence of messages inside it.

| Format | Magic (int32) | Bytes on disk | Usual extension |
|---|---|---|---|
| [Patch](./patches.md) | `0x0FEF5F00` | `00 5F EF 0F` | `.pwr` |
| [Signature](./signatures.md) | `0x0FEF5F01` | `01 5F EF 0F` | `.pwr.sig` (butler), `.pws` |
| [Manifest](./manifests.md) | `0x0FEF5F02` | `02 5F EF 0F` | `.pwm` |
| [Wounds](./wounds.md) | `0x0FEF5F03` | `03 5F EF 0F` | `.pww` |
| Zip index | `0x0FEF5F04` | `04 5F EF 0F` | `.pzi` |

The zip index magic is reserved, but nothing currently reads or writes that
format.

## Framing

A wharf file is a 4-byte magic number followed by a sequence of protobuf
messages:

  * The magic number is a signed 32-bit integer, little-endian.
  * Every message, starting with the header that follows the magic, is
  written as its serialized length in bytes, as an unsigned varint (the same
  base-128 encoding protobuf uses for integers), followed by the serialized
  message.

There is no type tag. The reader must know which message type comes next
from its position in the stream, as described on each format's page.
There is no end-of-file marker either: readers stop when the format says
they are done, or when they reach the end of the stream.

All messages are proto3. Fields set to their default value (`0`, `false`,
empty bytes) are not serialized, so a message whose fields are all default
encodes to zero bytes and is written as a single `0x00` length byte. This
happens in practice: a `SyncHeader` for file index 0 of type `RSYNC`,
an empty `WoundsHeader`, or a `BsdiffHeader` with `targetIndex = 0`. Readers
must accept zero-length messages.

## Compression

Patch, signature and manifest headers contain a `CompressionSettings`
message. The magic number and the header are never compressed. Everything
after the header, up to the end of the file, is a single compressed stream,
and the remaining length-prefixed messages live inside the decompressed
stream.

```protobuf
enum CompressionAlgorithm {
  NONE = 0;
  BROTLI = 1;
  GZIP = 2;
  ZSTD = 3;
}

message CompressionSettings {
  CompressionAlgorithm algorithm = 1;
  int32 quality = 2;
}
```

See the [Compression appendix](../appendix/compression.md) for what each
algorithm means and which ones are supported in practice.

Wounds files have no compression settings and are never compressed.

## Containers

Every format embeds one or two `Container` messages. `Container` is defined in
[tlc.proto][tlc] in the [lake][] repository (protobuf package `io.itch.wharf.tlc`):

```protobuf
message Container {
  repeated File files = 1;
  repeated Dir dirs = 2;
  repeated Symlink symlinks = 3;

  int64 size = 16;
}

message Dir {
  string path = 1;
  uint32 mode = 2;
}

message File {
  string path = 1;
  uint32 mode = 2;

  int64 size = 3;
  int64 offset = 4;
}

message Symlink {
  string path = 1;
  uint32 mode = 2;

  string dest = 3;
}
```

  * Paths are relative to the container root and use `/` as separator.
  Containers come from whoever made the file, so readers must check paths
  before using them. See [Path safety](./path-safety.md).
  * `mode` is a Go [`os.FileMode`][filemode] converted to `uint32`: the low
  9 bits are Unix permissions, and the high bits mark the entry type and
  special bits (`0x80000000` directory, `0x08000000` symlink, `0x00800000`
  setuid, `0x00400000` setgid). They are not Unix `st_mode` values. Older
  containers may have no type bits set.
  * `Container.size` is the sum of all file sizes.
  * `File.offset` is the sum of the sizes of all files before it in `files`.
  It is only used for progress reporting.

Everything else in a wharf file refers to files, directories and symlinks by
their index in these lists, so the order of `files` is significant.

[tlc]: https://github.com/itchio/lake/blob/master/tlc/tlc.proto
[lake]: https://github.com/itchio/lake
[filemode]: https://pkg.go.dev/io/fs#FileMode

## Naming in the reference implementation

This spec calls the two versions involved in a patch `old` and `new`. The Go
code calls them differently, which matters when reading it:

| This spec | wharf source code |
|---|---|
| `old` container | target |
| `new` container | source |

For example, `BsdiffHeader.targetIndex` is an index into the `old`
container's file list.
