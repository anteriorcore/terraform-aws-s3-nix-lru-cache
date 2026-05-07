# s3-nix-lru-cache

Terraform Module for a Nix LRU Cache backed by S3.  Uses AWS S3 server logs to
implement LRU logs.  Uses lifecycle rules and AWS Lambda to prune the logs and
cache.

LRU (Least Recently Used) is a [cache replacement
policy](https://en.wikipedia.org/wiki/Cache_replacement_policies) where items
are garbage collected based on how recently they have been used.  In contrast,
a FIFO cache, for example, purges items based on when they were _added_.

N.B.: Common LRU cache implementations allow specifying a maximum cache size,
and pruning least-recently-used elements until the total cache size drops below
that size.  This implementation does not support such a configuration; rather,
it prunes all items which haven't been used in a (configurable) timeframe (e.g.
1 month).  This is not a fundamental limitation, it's just what we needed.

The idea is to deploy this in your own AWS account, giving you billing,
colocation, and simplicity benefits.

These are offered here Open Source, and Free for all to use (following the
LICENSE), but with zero warranty or guarantees.

If you want to use these tools we advise reading the license and forking the repo.

## Use / Explore

```command
$ nix flake show
git+file:///Users/you/path/s3-nix-lru-cache
├───checks
...
```

And take it from there

## Copyright & License

s3-nix-lru-cache is authored by [Anterior](https://anterior.com), based in NYC, USA.

**We’re hiring!** If you got this far, e-mail us at
[hiring+oss@anterior.com](mailto:hiring+oss@anterior.com) and mention Nix Cache.

The code is available under the AGPLv3 license (not later).

See the [LICENSE](LICENSE) file.
