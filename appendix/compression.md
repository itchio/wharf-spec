
# Compression formats

Patch, signature and manifest files carry a `CompressionSettings` message in
their header. Everything after the header is one stream compressed with that
algorithm (see [File formats](../file-formats/README.md)).

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

`quality` is only used when writing. Readers only need `algorithm`.

| Algorithm | Stream format | `quality` | Reference implementation |
|---|---|---|---|
| `NONE` | raw messages, no wrapping | ignored | read and write |
| `BROTLI` | a [brotli][] stream (RFC 7932) | brotli quality, 0 to 11 | read and write |
| `GZIP` | a gzip stream (RFC 1952), not raw deflate or zlib | gzip level, as accepted by Go's `gzip.NewWriterLevel` (-2 to 9) | read and write |
| `ZSTD` | a [zstd][] stream | zstd level | neither (retired) |

In the reference implementation, each algorithm other than `NONE` is a
separate package that programs opt into, so a program only supports the
algorithms it includes.

`ZSTD` support was removed from wharf in 2019. The enum value is kept so that
older files can still be identified, but current wharf and butler can't read
or write them.

[brotli]: https://github.com/google/brotli
[zstd]: https://github.com/facebook/zstd

## What butler writes

butler only includes brotli, so in practice patches and signatures in the
wild are brotli or uncompressed:

  * `butler push` writes patches and signatures with brotli at quality 1
  * `butler rediff` writes optimized patches with brotli, at the quality given
  by `--rediff-quality` (default 1).

An independent implementation that reads `NONE` and `BROTLI` can read every
file current versions of butler produce.

## Why brotli

The recommended compression algorithm for wharf is brotli, released
originally by Google in September 2015.

After empirical tests, it appears, at Q=1, to produce output smaller than
gzip in less time, and at Q=9, to be competitive with LZMA. This is why
this spec recommends brotli-q1 as a transport compression format, and
brotli-q9 as a long-term storage and optimized delivery format.
