
# The wharf manifest format (.pwm)

*Status: legacy. The messages are still defined in [pwr.proto][pwr.proto],
and butler's `ls` and `file` commands can identify manifest files and print
their container, but nothing writes manifests or reads their hashes anymore.
The code that did was removed from wharf in 2019. This page describes the
format it implemented.*

A manifest describes a container and lists a hash for each "big block" of
each file. It was used by blockpool, an experiment in storing builds as
content-addressed 4 MiB blocks.

*Read the [framing rules](./README.md) first.*

[pwr.proto]: https://github.com/itchio/wharf/blob/master/pwr/pwr.proto

## Layout

```
magic              int32 LE = 0x0FEF5F02
ManifestHeader     (uncompressed)
--- compressed stream, as specified by ManifestHeader.compression ---
Container
for each file in Container.files, in order:
  SyncHeader                       fileIndex = index of the file, type unset
  ManifestBlockHash * numBlocks
```

```protobuf
message ManifestHeader {
  CompressionSettings compression = 1;
  HashAlgorithm algorithm = 2;
}

enum HashAlgorithm {
  SHAKE128_32 = 0;
  CRC32C = 1;
}

message ManifestBlockHash {
  bytes hash = 1;
}
```

The `SyncHeader` message is the one from the [patch format](./patches.md),
reused as a per-file separator. Readers checked that its `fileIndex` matched
the expected index.

## Blocks

Unlike patches and signatures, manifests use 4 MiB blocks (4194304 bytes).
A file of size `s` has `ceil(s / 4194304)` hashes. An empty file has no hashes (unlike [signatures](./signatures.md),
there is no zero-length block).

## Hash algorithms

  * `SHAKE128_32`: the first 32 bytes of SHAKE128 output for the block. This
  is the only algorithm blockpool wrote or accepted.
  * `CRC32C`: defined in the enum, never used by any implementation.
