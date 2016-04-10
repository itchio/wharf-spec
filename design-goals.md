
# Design goals

*Note: this section is more of an informal and opinionated discussion than the rest of the spec. It is
the author's hope that it will later be useful as a reference point when someone inevitably wonders "What
 in the world were they thinking?"*

The wharf protocol is designed with these goals in mind:

  * Minimize network bandwidth usage
  * Assume as little as possible about the payload
  * Don't require smart servers
  * File formats should be open and highly compatible

The rsync algorithm[^1] is the most notable piece of prior art wharf is based on,
and has been widely used by both prominent open-source projects (Debian, Gentoo, etc.)
and companies alike (cf. [Dropbox's librsync fork][dropbox-librsync]).

In fact, it's safe to say that many proprietary patching solutions are based
on the same principles, but end up riddled with bugs and inefficiencies, due
to the closed-source and non-essential nature of these operations to businesses[^4].

As co-operator of a large game hosting platform, the author felt it was important
to provide the community with a solid open specification, suited for their needs
and that can hopefully be adopted rapidly by different actors of the game development
community.

## Adequacy versus optimality

It is important to note that, for certain payloads, other algorithms may
yield significantly better results. The author's goal is not to top any
benchmark, but to provide a practical solution that performs well under
a variety of conditions.

For example, [bsdiff][] or [courgette][] may provide a much smaller diff
between two versions of an executable. Part of the reason is that they
disassemble certain files, then compare the assembly code. Applying the
patch implies disassembling the old version, applying the patch to the
assembly code, then reassembling, and then applying a few byte-level corrections

As a result, binary diffing tools like those mentioned above:

  * Perform significantly better on binaries, but not necessarily on other types of files
  * Require a significant amount of memory to run.[^2]
  * Contain a non-trivial amount of code, making auditing or alternative implementations impractical

[dropbox-librsync]: https://github.com/dropbox/librsync
[bsdiff]: http://www.daemonology.net/bsdiff/
[courgette]: https://www.chromium.org/developers/design-documents/software-updates-courgette

In other words, it makes perfect sense for a Linux distribution project to use
bsdiff to compute patches for packages which contain files of at most a hundred
megabytes, or for a company like Google to roll out their own highly-specific
algorithm to deploy silent upgrades to their browser several times per day to
[a billion daily users][billion].

[billion]: http://venturebeat.com/2015/05/28/google-chrome-now-has-over-1-billion-users/

However, limiting ourselves to a simpler algorithm allows us to generate
patches on the client side, rather than uploading the entire thing and letting
the diff computation up to some powerful server. This enables incremental uploads
as well as a lower maintenance cost for the backend.

## In defense of dumb servers

Similarly, a "smart server" approach to software updates could enable faster
delivery to the end-user. With a smart server, a user N versions behind the latest
one could receive a single, custom-made patch, rather than having to download N
separate patches and apply them.

On the other hand, maintaining a fleet of smart servers, properly balancing the
load between them, making informed choices about the maximum duration of sessions
and keeping the attackers at bay requires a lot more resources and knowledge
than hosting static files on one of the many affordable cloud offerings.

Therefore, this specification places itself continuously on the side of smaller
entities, either individuals or collectives, with limited resources, and tries
to provide them with a specification that, while useful in its basic state,
enables adaptative improvement — such as processing patch files to further
reduce their size and increase bandwidth savings.

## File formats and lessons from history

According to the skeptics, there are two kinds of file formats:

 * Impenetrable ones (binary formats)
 * Inefficient ones (text formats)

However, over the years, several standardized binary data interchange formats
have surfaced, including Google's [protobuf][]. At the time of this writing,
official protobuf implementations exist for nine programming languages (C++,
Java, Python, Objective-C, C#, JavaNano, JavaScript, Ruby and Go), and have
the following properties:

[protobuf]: https://github.com/google/protobuf

  * Automatically-generated parser/generator/data structures
  * ... from a single, language-agnostic and human-readable spec (`*.proto` files)
  * ... that is expressive enough for streaming file formats
  * ... and allows adding fields while maintaining backwards compatibility

This was all the author needed to be convinced. It was also, at the time the decision
was made, one of the fastest formats to deserialize/serialize to.

### Footnotes

[^1]: described in Andrew Tridgell's 1999 PHD thesis, [Efficient Algorithms for Sorting and Synchronization](https://www.samba.org/~tridge/phd_thesis.pdf)

[^2]: bsdiff is quite memory-hungry. It requires max(17*n,9*n+m)+O(1) bytes of memory, where n is the size of the old file and m is the size of the new file. bspatch requires n+m+O(1) bytes. [(source)](http://www.daemonology.net/bsdiff/)

[^3]: The author would like to insist on the fact that *nothing* in the wharf specification precludes a solution where multiple-version-hops patches are made available. A backend could definitely combine smaller patches together into larger patches, getting rid of obsolete data along the way. See [backend notes](./appendix/backend-notes.md) for a more in-depth write-up on the matter.

[^4]: Dropbox being a notable exception, of course, but it still isn't in their interest for their userbase to fully understand, implement, and deploy their file synchronization system. Whereas this spec comes from a company that would still be sustainable even if every one of its users rolled their own wharf implementation, and can afford to offer the rest of them a high-quality implementation-as-a-service of it.
