
# The wharf specification

Wharf is a protocol that enables incremental uploads and downloads to
keep software up-to-date. It includes:

  * A diffing and patching algorithm, based on rsync
  * An open file format specification for patches and signature files, based on protobuf
  * A [reference implementation][wharf.go] in Go
  * A [command-line tool][butler] with several commands

[wharf.go]: https://github.com/itchio/wharf
[butler]: https://github.com/itchio/butler

## Foreword

Good specifications are easy to read, practical guidelines that make it easier
for software to be interoperable. This book aims to be a good specification.

Its intended audience includes:

  * People who want to understand the tenets of [itch.io][]'s software delivery system,
  to judge its worth / audit it.
  * People who want to write their own, spec-compatible implementation of the protocol
  * People who want to use itch.io's implementation of wharf, but with their own backend.

No spec is perfect, but it is the author's hope that, together with the community,
a solid spec can be achieved and yield numerous highly-compatible implementations.

[itch.io]: https://itch.io

## Links

The latest version of this book is available at:

  * https://docs.itch.ovh/wharf/master/index.html

Contributions can be made to it by submitting pull requests or issues on its GitHub repository:

  * https://github.com/itchio/wharf-spec

## Authors

Except when otherwise noted, this specification has been written by [Amos Wenger][amos]

[amos]: https://github.com/fasterthanlime
