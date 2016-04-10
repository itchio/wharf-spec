
# Hashes

wharf uses two hashing algorithms:

  * The weak hashing algorithm used in the original RSync paper
  * MD5 as the "strong" hashing algorithm

MD5 isn't cryptographically strong in any way, but that's besides the point.
It is a fast hash, of which many optimized implementations exist, and that
allows detecting differences between files efficiently.

If the block size were to be increased, swapping MD5 out for a longer and
stronger hash would be advantageous (with the caveats indicated in the
[Block size](./block-size.md) appendix).
