
# The apply algorithm

*The [Terminology](../terminology.md) page is a strongly-recommended reading before
attacking this page.*

## Writing the container's shape to disk

The information contained in a patch lies not only in the operation list for each file of
the new container, but also in the container metadata for both the `old` and the `new` container.

Before applying any operation, the `new` container should be walked and the
following **pre-processing steps** should be taken:

  * Missing directories should be created
  * Missing files should be created

After applying all file operations, the following **post-processing steps** should be taken:

  * Symlinks should be created
    * If there is an existing file where the symlink was, it should be deleted
    and the symlink should be created in its place
  * Files or symlinks listed in `new` but not in `old` should be deleted
  * Directories listed in `new` but not in `old` and that are now empty
  should be deleted

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

## In-place, atomic upgrades

Conceptually, the wharf apply algorithm always operates from an `old`
to a `new` directory, which are stored in different locations. However,
if the `old` and the `new` container are one and the same on-disk,
writing to the new container may modify the contents of the old container
and corrupt the patch (if portions of the overwritten file were reused
to rebuild other files).

Additionally, applying a patch should be atomic: if it can't be applied
cleanly (the reconstructed files do not match their signature), then
no changes must be committed to the original directory on disk.

For that reason, it is useful for patches to:

  * Identify no-op block ranges and not touch these files at all[^1]
  * Reconstruct changed or fresh file in a staging folder

Once the signatures of all the files in a staging folder have been
compared with the reference signatures in the [signature file](../file-formats/signatures.md):

  * The pre-processing steps can be applied (see above)
  * The staging folder's contents can be merged with the folder being patched
  * The post-processing steps can be applied

If there is a hash mismatch, the staging folder can simply be erased.

[^1]: This is especially crucial to mod support. As long as files aren't
modified by the developers of a particular software, their modded versions
shouldn't block upgrades.
