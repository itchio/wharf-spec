
# The diff algorithm

*The [Terminology](../terminology.md) page is a strongly-recommended reading before
attacking this page.*

The diff algorithm is a modified version of [the rsync algorithm][rsync]

It retains the following essential properties:

  1. Full access[^1] to the `old` version is not required — a series of hashes is enough.
  2. All files of the `new` version are scanned linearly and only once.
  3. The more similar `old` is to `new`, the faster the diff runs.
  4. Changes are efficiently encoded regardless of their alignment

And adds these:

  5. Renames are transparent and do not increase the diff's size

[rsync]: https://www.samba.org/~tridge/phd_thesis.pdf
