
# The diff algorithm

*The [Terminology](../terminology.md) page is a strongly-recommended reading before
attacking this page.*

The diff algorithm is a modified version of [the rsync algorithm][rsync], and has
the following properties:

  * Full access[^1] to the `old` version is not required — a series of hashes is enough.
  * All files of the `new` version are scanned linearly and only once.
  * The more similar `old` is to `new`, the faster the diff runs.
  * Changes are efficiently encoded regardless of their alignment
  * Renames are detected and handled properly (instead of counting as a deletion + insertion)

[^1]: By "full access" we mean being able to read the files' content. A typical scenario where one does not have "full access" is uploading a new version of some software, to a storage server that holds older versions of it. The storage server only has to send a series of hashes, which is much smaller than the files themselves.

For the purpose of the diff algorithm, every file is split into blocks of 64kb.
Files from the `new` version are then scanned, looking for blocks with the same contents
as those from any files of the `old` version.

When similar blocks are found, we store positional information (file index within
the container, and block offset within the file) that allows copying the block(s)
from the old file to the new file (ie. `BLOCK_RANGE` operations).

Similar blocks are found one at a time, but `BLOCK_RANGE` operations on consecutive
blocks are combined to produce even smaller patches.

When no similar blocks can be found, data from the new files (called `fresh data`)
is directly written to the patch, in chunks of at most 4MB (ie. `DATA` operations).

[rsync]: https://www.samba.org/~tridge/phd_thesis.pdf

## The signature of the `old` container

For the diff algorithm to run, a [signature](../file-formats/signatures.md) of
the old container must be obtained. It contains:

  * The old container's layout:
    * A list of directory names and their permissions
    * A list of symbolic links, their targets and permissions
    * A list of files, their permissions, and size
  * A list of block hashes corresponding to 64kb blocks (or less) of
  all the container's files.

Directories and symlinks have no contents, so they don't have block hashes.
Order in the files list matters, as block hashes and operations refer to files
by their index in the container's file list, rather than using their path.

The signature could for example be read from a file or network connection.
Alternatively, if we have full access to the old container, the signature
may be computed by reading and hashing all files from the old container.

### Reading an existing signature

Hashes stored a [signature file](../file-formats/signatures.md) have two fields:

  * Weak hash (4 bytes)
  * Strong hash (32 bytes)

When reading hashes sequentially from a signature file, one must keep track
of where in a file and which file of the container the current hash corresponds to.
This process is called **anchoring hashes**.

For example, a container with the following files:

  * foo.dat - 130kb file
  * bar.dat - 12kb file

...would yield a signature with four hashes:

  * size: 64kb, fileIndex: 0, blockIndex: 0
  * size: 64kb, fileIndex: 0, blockIndex: 1
  * size:  2kb, fileIndex: 0, blockIndex: 2
  * size: 12kb, fileIndex: 1, blockIndex: 0

Storing the file index, block index, and block size in signature files isn't
necessary, since the container's file list gives all the information needed to
predict the hash layout. That's the reason the protobuf [BlockHash message][pwr.proto]
only includes the weak hash and the strong hash.

[pwr.proto]: https://github.com/itchio/wharf/blob/master/pwr/pwr.proto

### Anchoring block hashes

Here's a pseudo-code algorithm showing how to deduce the file index, block index,
and block size, given a container.

```lua
full_block_size = 64 * 1024

file_index = 0
block_index = 0
block_size = full_block_size
byte_offset = 0

while (hash = read a BlockHash message from the signature file)
  size_diff = (size of file at file_index) - byte_offset
  short_size = 0

  if (size_diff < 0)
    -- moved past the end of the file
    byte_offset = 0
    block_index = 0
    file_index = file_index + 1
    size_diff = (size of file at file_index) - byte_offset

  if (size_diff < full_block_size)
    -- last block of the file
    short_size = size_diff
  else
    short_size = 0

  add AnchoredBlockHash(
    file_index,
    block_index,
    short_size,
    hash.weak_hash,
    hash.strong_hash) to block library

  byte_offset = byte_offset + block_size
  block_index = block_index + 1
```

*Note: blocks that are exactly 64kb large have a short_size of 0, since
it is a very common case, and 0 is the default value of an integer in protobuf,
and default values don't take up any space in protobuf encoding.*

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

First, the weak hash is computed for the potential block (fast).

Then, if the block library does **not** contain entries for that weak hash,
the tail and head both move 1 byte to the right.

The weak hash is a rolling hash, which means given the hash of a block, computing
the hash of the block 1 byte to the right of it is a very cheap. Think
of it as actually "rolling" on the file, "feeding" byte per byte.

Here's how the `next` rolling hash is computed:

```
αPush = uint32(buffer[head - 1])
β1 = (β1 - αPop + αPush) % _M
β2 = (β2 - uint32(head - tail) * αPop + β1) % _M
β = β1 + _M*β2
```

in which

  * `αPop` is the byte 'escaping' to the left of the tail (initially 0)
  * `αPush` is the byte fed to the head, from the right
  * `β1` and `β2` are internal state that must be maintained from one rolling
  computation to the other.
  * `_M` is a constant equal to `1 << 16`
  * `β` is the result

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

When "owed" data reaches the maximum size of 4MB, a `DATA` operation is
emitted, to keep operation messages' sizes reasonable[^2].

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

*Note that the last row of the diagram represents which areas of the scanned file
are 'described' by operations, and not the actual byte size of the operations
themselves in the patch file.*

The weak hash for the new potential block should now be computed. Since we moved
more than one byte to the right, we can't use the rolling version of the weak hash,
and have to use the following algorithm to recompute the weak hash of the entire
new potential block:

```
var a, b uint32

for each byte val at index i of potential block {
	a += uint32(val)
	b += (uint32((length of the block)-1) - uint32(i) + 1) * uint32(val)
}

β = (a % _M) + (_M * (b % _M))
β1 = a % _M
β2 = b % _M
```

The result of this computation is not just `β`, but `β1, β2` too, which will be
used the next time the head and tail move one byte to the right.

[^2]: By *reasonable* we mean two things: that serializing and deserializing them
to/from [protobuf format](../file-formats/patches.md) won't require a significant
amount of memory, and that receiving operations through a non-random-access channel
such as a network connection will allow us to start patching files without obtaining
the *entire* patch.

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

Imagine a container with two identical files:

  * a.dat, 128kb
  * b.dat, 128kb

Diffing that container with itself should produce the following operation sequence:

  * BLOCK_RANGE with **fileIndex = 0**, blockIndex = 0, blockSpan = 2
  * BLOCK_RANGE with **fileIndex = 1**, blockIndex = 0, blockSpan = 2


                      new a.dat             new b.dat
                +----------+----------+          +          +    
     old a.dat  |||||||||||||||||||||||                          
                +----------+----------+----------+----------+   
     old b.dat                        |||||||||||||||||||||||    
                +          +          +----------+----------+    

Such a patch could easily be recognized by a compliant patcher as a no-op.

However, a naive differ could pick only from the first file (ie. the first
strong hash that matches)

  * BLOCK_RANGE with **fileIndex = 0**, blockIndex = 0, blockSpan = 2
  * BLOCK_RANGE with **fileIndex = 0**, blockIndex = 0, blockSpan = 2


                      new a.dat             new b.dat
                +----------+----------+----------+----------+    
     old a.dat  |||||||||||||||||||||||||||||||||||||||||||||
                +----------+----------+----------+----------+   
     old b.dat                                                   
                +          +          +          +          +    


Or could even produce even noisier patterns (if strong hashes were stored
in different orders for the first and the second block):

  * operations for a.dat
    * BLOCK_RANGE with fileIndex = 1, blockIndex = 0, blockSpan = 1
    * BLOCK_RANGE with fileIndex = 0, blockIndex = 1, blockSpan = 1
  * operations for b.dat
    * BLOCK_RANGE with fileIndex = 1, blockIndex = 0, blockSpan = 1
    * BLOCK_RANGE with fileIndex = 0, blockIndex = 1, blockSpan = 1


                      new a.dat             new b.dat
                +----------+          +----------+          +    
     old a.dat  ||||||||||||          ||||||||||||           
                +----------+----------+----------+----------+   
     old b.dat             ||||||||||||          ||||||||||||    
                +          +----------+          +----------+    


To produce the ideal patch described above, all a differ has to do is:

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
