# We've pinned Haskell LTS 12.12 commit of nixpkgs for reproducible builds.

import (builtins.fetchTarball {
  # Descriptive name to make the store path easier to identify
  name = "nixos-unstable-2017-09-12";
  # Commit hash for nixos-unstable as of 2019-09-12
  url = https://github.com/nixos/nixpkgs/archive/6ec4ebf6f87fdfc221103f41a0353aa7c0a21684.tar.gz;
  # Hash obtained using `nix-prefetch-url --unpack <url>`
  sha256 = "1wa54b3qnm2dcphy1qyqv68fckcbrjsaxd9dp69ilhmrjnpydrn8";
}) {}
