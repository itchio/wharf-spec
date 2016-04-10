
# Compression formats

The recommended compression algorithm for wharf is [brotli][], released originally
by Google in september 2015.

[brotli]: https://github.com/google/brotli

After empirical tests, it appears, at Q=1, to produce output smaller than
gzip in less time, and at Q=9, to be competitive with LZMA. This is why
this spec recommends brotli-q1 as a transport compression format, and
brotli-q9 as a long-term storage and optimized delivery format.
