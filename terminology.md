
# Terminology

These words are used throughout the spec. Here's their canonical definition:

A `container` is a generic word for a set of files, folders, and symlinks. It is
also a protobuf message that encodes information about a set of files, folders and
symlinks such as their path (relative to the container's root), permissions and sizes,
but not their contents.

A `diff` is the result of a comparison between two containers, `old` and `new`.
It contains a list of operations required to build `new`'s files from `old`'s files,
re-using data when possible.

A `patch` contains all the information needed to apply an upgrade: both the `old`
and `new` container, and their diff. Patches are stored in a [standard file format](./file-formats/patches.md).

A `signature` contains one container and a series of hashes corresponding to fixed-size blocks
of the container's files. Signatures are stored in a [standard file format](./file-formats/signatures.md).

`/dev/null` is the empty container: it contains no files, folders or symlinks.
A diff against `/dev/null` is a suitable way to store the initial version of
a container.

An `archive` is a compressed container stored in a single file (e.g. `build.zip`,
`build.7z`, etc.). They're the preferred way of storing a particular version of
a container, and are suitable for diffing, although at the cost of on-the-fly
decompression.

A `block` is a fixed-size series of bytes that belong to a file. Folders and symlinks
do not have blocks. Files usually end with `short blocks`, which are smaller than
regular blocks, except if their size is a multiple of the block size.
