
# The apply algorithm

*The [Terminology](../terminology.md) page is a strongly-recommended reading before
attacking this page.*

## Writing the container's shape to disk

The information contained in a patch lies not only in the operation list for each file of
the new container, but also in the container metadata for both the `old` and the `new` container.

Before applying any operation,

## Applying operations

Rebuilding a new file from the content of one or more old files is relatively trivial.
`DATA` operations contain verbatim data to be written to the file at the current offset.

As for `BLOCK_RANGE` operations, they specify:

  * which file to read from (op.fileIndex)
  * at which offset (BlockSize * op.blockIndex)
  * and for how many bytes (BlockSize * op.blockSpan)

It is suggested that implementations optimize resource usage by maintaining a pool
of open file readers, instead of closing and opening files for each `BLOCK_RANGE`
operation. Even a pool of size 1 will notably improve patching performance of a single
large file with several very localized changes.
