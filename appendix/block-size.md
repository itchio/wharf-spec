
# Block size

The 64kb block size was chosen empirically after running a few diffs on sample
data[^1]. The algorithm would work with other block sizes, and adjusting the
block size might be required for some payloads.

In particular:

  * The larger the block size, the smaller signatures gets
  * The larger the block size, the bigger diffs get (small changes incur a full-block penalty)

[^1] ~500MB Unity 5 exports
