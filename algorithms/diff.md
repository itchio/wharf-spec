
# The diff algorithm

*The [Terminology](../terminology.md) page is a strongly-recommended reading before
attacking this page.*

The diff algorithm is a modified version of [the rsync algorithm][rsync]

It retains the following essential properties:

  * Full access[^1] to the `old` version is not required — a series of hashes is enough.
  * All files of the `new` version are scanned linearly and only once.
  * The more similar `old` is to `new`, the faster the diff runs.
  * Changes are efficiently encoded regardless of their alignment

And adds these:

  * Renames are transparent and do not increase the diff's size

[rsync]: https://www.samba.org/~tridge/phd_thesis.pdf

## Obtaining container structure and hashes from the old container

For the diff algorithm to be able to compute differences, a signature
of the old container. The signature contains container information (a list
of files, directories and symlinks, their sizes, permissions, etc.).

The signature could for example be read from a file or network connection.
Alternatively, if diffing two containers directly on-disk, the signature
may be computed by reading and hashing all files from the old container.

Hashes contained in the signature have the following structure:

  * weak (rolling) hash (4 bytes)
  * strong (MD5) hash (32 bytes)
  * file index
  * block index
  * block size

The file index is made unambiguous thanks to the container's canonical ordering
of the files.

For example, a container with the following files:

  * foo.dat - 68kb file
  * bar.dat - 12kb file

...would yield a signature with three hashes:

  * size: 64kb, fileIndex: 0, blockIndex: 0
  * size: 4kb, fileIndex: 0, blockIndex: 1
  * size: 12kb, fileIndex: 1, blockIndex: 0

Storing the file index, block index, and block size isn't necessary, since
the container's file list gives all the information needed to predict the
hash layout, as seen above. As such, the [BlockHash message][pwr.proto]
only includes the weak hash and the strong hash.

[pwr.proto]: https://github.com/itchio/wharf/blob/master/pwr/pwr.proto

## Constructing the block library

Although hashes are stored in a sequence, the diffing algorithm needs them
to be in an associative data structure, indexed by the weak hash. Note that
one weak hash may be associated to more than one block. The structure's type
is thus `Map of <Weak hash, <Array of block hashes>>`

The weak hash's output is only 32 bits, thus there is a high chance of
collision, but it still lets us avoid computing the strong hash most of the
time. Think of the weak hash as a mechanism to quickly eliminate most of the
mismatches.

## Scanning files and looking for matching blocks

This is the actual diff computation. The objective is to produce a list of
two types of operations:

  * `SyncOp{type = BLOCK_RANGE}` operations, in which existing blocks from the
  `old` container are re-used.
  * `SyncOp{type = DATA}` operations, in which fresh/original data is stored.

Picture a file as a series of bytes, and the algorithm as a scanner with a
head and a tail:

    +-----------------------------------------------------------+
    |                           file                            |
    +-----------------------------------------------------------+
    ^     ( 64kb )      ^                                       ^
    |                   |                                       |
    tail              head                                    EOF
    |                   |
    +-------------------+
    |  potential block  |
    +-------------------+
    |
    owed data tail

First, the weak hash is computed for the potential block (fast). Then if the block library does **not** contain entries for that weak hash, the tail and head both move 1 byte to the right

The weak hash is a rolling hash, which means given the hash of a block, computing
the hash of the block 1 byte to the right of it is a very simple operation. Think
of it as actually "rolling" on the file, "feeding" byte per byte.

As the head and tail move to the right, the algorithm remembers the last position it
emitted an operation. The area between the last operation's end and the tail is
hereafter referred to as "owed" data.

    +-----------------------------------------------------------+
    |                           file                            |
    +-----------------------------------------------------------+
    ^        ^     ( 64kb )      ^                              ^
    |        |                   |                              |
    |        tail              head                           EOF
    |        |
    +--------+
    |  owed  |
    |  data  |
    +--------+
    |
    owed data tail

When "scanned" data reaches the maximum size of 4MB, a `SyncOp{type = DATA}` is
emitted, to keep data operation's sizes granular enough for network transmission,
and to keep memory usage reasonable when serializing.

When the block library *does* contain entries for a given weak hash, the strong
(MD5) hash of the data between the tail and the head is computed and compared
to each entry of the block library for that weak hash.

If the block library contains a block hash with a matching strong hash and
block size, then we have found a block from one of the `old` files that we
can re-use.

*In case several strong hashes match, the preferred file index is used. See
the `preferred file index` section.*

When a match is found, any "owed data" is added to the operation list
as a `SyncOp{type = DATA}`:

    +-----------------------------------------------------------+
    |                           file                            |
    +-----------------------------------------------------------+
    ^        ^     ( 64kb )      ^                              ^
    |        |                   |                              |
    |        tail              head                           EOF
    |        |                   |
    |        +-------------------+
    |        |  potential block  |
    |        +-------------------+
    |
    owed data tail
    +--------+
    |  DATA  | ( patch file being written )
    +--------+

Then, a `SyncOp{type = BLOCK_RANGE, blockSpan = 1}` is added to the operation list

    +-----------------------------------------------------------+
    |                           file                            |
    +-----------------------------------------------------------+
    ^        ^     ( 64kb )      ^                              ^
    |        |                   |                              |
    |        tail              head                           EOF
    |        |                   |
    |        +-------------------+
    |        |  potential block  |
    |        +-------------------+
    |
    owed data tail
    +--------+-------------------+
    |  DATA  |    BLOCK_RANGE    | ( patch file being written )
    +--------+-------------------+

The head and tail both move one BlockSize to the right. The position of
the owed data tail is adjusted as well

    +-----------------------------------------------------------+
    |                           file                            |
    +-----------------------------------------------------------+
    ^                            ^     ( 64kb )      ^          ^
    |                            |                   |          |
    |                            tail              head       EOF
    |                            |                   |
    |                            +-------------------+
    |                            |  potential block  |
    |                            +-------------------+
    |                            |
    |                            owed data tail
    +--------+-------------------+
    |  DATA  |    BLOCK_RANGE    |
    +--------+-------------------+

The weak hash for the new potential block can now be computed, and scanning
can resume until we find another block hash match.

Note that the last row of the diagram represents which areas of the scanned file
are 'described' by operations, and not the actual byte size of the operations
themselves in the patch file.

## BlockRange combination

It is not uncommon to find several consecutive hash matches. Those can be combined
in a single block range by keeping an operation buffer of size 1. When a hash
match is found, if another `BLOCK_RANGE` operation is stored in the operation buffer,
then calling the stored operation `prev` and the fresh operation `next`

  * If `prev.fileIndex == next.fileIndex`
  * and `prev.blockIndex + prev.blockSpan = next.blockIndex`

    +-----------------------------------------------------------+
    |                           file                            |
    +-----------------------------------------------------------+
    ^                            ^     ( 64kb )      ^          ^
    |                            |                   |          |
    |                            tail              head       EOF
    |                            |                   |
    |                            +-------------------+
    |                            |  potential block  |
    |                            +-------------------+
    |                            |
    |                            owed data tail
    +--------+-------------------+-------------------+
    |  DATA  |    BLOCK_RANGE    |   BLOCK_RANGE     |
    +--------+-------------------+-------------------+

...then the two operations can be combined. The `next` operation is discarded,
the `prev` operation remains in the operation buffer and its `blockSpan` is incremented
by one.

    +-----------------------------------------------------------+
    |                           file                            |
    +-----------------------------------------------------------+
    ^                            ^     ( 64kb )      ^          ^
    |                            |                   |          |
    |                            tail              head       EOF
    |                            |                   |
    |                            +-------------------+
    |                            |  potential block  |
    |                            +-------------------+
    |                            |
    |                            owed data tail
    +--------+---------------------------------------+
    |  DATA  |      BLOCK_RANGE (blockSpan = 2)      |
    +--------+---------------------------------------+


## The end of the file, and shortblocks

The head can never go past the end of the file (that would involve scanning
non-existent data). When it reaches the end of the file, it is doomed to stay
there while waiting for the tail to catch up.

Some variants of the rsync algorithm simply send the remaining file data
as a `DATA` operation, like so:

    +-----------------------------------------------------------+
    |                           file                            |
    +-----------------------------------------------------------+
    ^                                                ^          ^
    |                                                |          |
    |                                              tail      head
    |                                                |        EOF
    |                                                +----------+
    |                                                |  potent. |
    |                                                +----------+
    |                                                |
    |                                                | owed data tail
    +--------+---------------------------------------+----------+
    |  DATA  |      BLOCK_RANGE (blockSpan = 2)      |   DATA   |
    +--------+---------------------------------------+----------+

However, in wharf, short blocks are hashed and stored in the block library
along with their size. Hence, our example could end up looking like this, if
it turns out that the file only had some data prepended to it:

    +-----------------------------------------------------------+
    |                           file                            |
    +-----------------------------------------------------------+
    ^                                                           ^
    |                                                           |
    |                                                        head
    |                                                         EOF
    |                                                        tail
    |                                              owed data tail
    +--------+--------------------------------------------------+
    |  DATA  |            BLOCK_RANGE (blockSpan = 3)           |
    +--------+--------------------------------------------------+

## Preferred file index

Two files in a container may share some content, in which case they'll have
equal block hashes. Due to the way hashes are stored in the block library, they
won't overwrite each other, but the generated patch might be unnecessarily complicated.

Imaginine a container containing two identical files:

  * a.dat, 128kb
  * b.dat, 128kb

Diffing it with itself should produce the following operation sequence:

  * SyncOp{type = BLOCK_SPAN, **fileIndex = 0**, blockIndex = 0, blockSpan = 2}
  * SyncOp{type = BLOCK_SPAN, **fileIndex = 1**, blockIndex = 0, blockSpan = 2}

Such a patch could easily be recognized by a compliant patcher as a no-op.

However, a naive differ would produce the following operation sequence:

  * SyncOp{type = BLOCK_SPAN, **fileIndex = 0**, blockIndex = 0, blockSpan = 2}
  * SyncOp{type = BLOCK_SPAN, **fileIndex = 0**, blockIndex = 0, blockSpan = 2}

Or something even more contrived:

  * SyncOp{type = BLOCK_SPAN, fileIndex = 1, blockIndex = 0, blockSpan = 1}
  * SyncOp{type = BLOCK_SPAN, fileIndex = 1, blockIndex = 1, blockSpan = 1}
  * SyncOp{type = BLOCK_SPAN, fileIndex = 0, blockIndex = 0, blockSpan = 1}
  * SyncOp{type = BLOCK_SPAN, fileIndex = 0, blockIndex = 1, blockSpan = 1}

To produce the ideal patch described above, all a differ has to do is

  * When starting to diff a file of the `new` container, look for a file in the
  `old` container with the same path
  * If it finds one, note its position in the old container's file list. That's
  the `preferred file index`.
  * When looking for a hash match, if it matches several strong hashes, prioritize
  the one coming from the `preferred file`. This is made possible by the block library
  storing the file index for each block hash.

## Hashing big files (near-zero copy)

The algorithm doesn't require holding an entire file in memory. The [reference
implementation][refimpl] uses a single `2 * BlockSize + MaxDataOp` buffer, where BlockSize
is 64kb, and MaxDataOp is 4MB.

[refimpl]: https://github.com/itchio/wharf

Data is read into that buffer, a blockfull at a time. When free space at the end
of the buffer is insufficient to read another block, the data from the `owed data tail`
to `head` is copied to the very beginning of the buffer, and the scanning can resume
as before.
