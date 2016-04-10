
# The wharf patch format (.pwr)

TODO — in a nutshell:

  * Header w/compression settings
  * Compressed sub-stream with:
    * Container message for `old`
    * Container message for `new`
    * SyncOp messages until SyncOp{Type = HEY_YOU_DID_IT}
