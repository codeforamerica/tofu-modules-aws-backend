# Recovering from a regional outage

If the primary region itself is down (not just the bucket), point OpenTofu
at the replica instead of trying to rebuild the primary.

1. Confirm it's actually the region, not just the bucket — if only the
   bucket is gone, use [rebuilding-after-state-loss.md] instead.
2. In every consumer config (not this module), update the `backend "s3"`
   block to point at the replica's `bucket`/`region`, keeping the same
   `key`. Do this everywhere before applying anything else, or a consumer
   still pointed at the dead primary will fail to lock/read state.
3. `tofu init -reconfigure` against the replica backend, then `tofu plan`
   to confirm nothing unexpected shows up.
4. Once the primary region is back, decide whether to fail back or
   promote the replica permanently. Promoting it means standing up a new
   replica in a third region to restore redundancy — bigger decision than
   this module covers on its own.
5. If the primary comes back before you've cut over, there's nothing to
   roll back — you never changed the backend block.

[rebuilding-after-state-loss.md]: rebuilding-after-state-loss.md
