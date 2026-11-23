#!/usr/bin/env bash
# Dipertahankan demi kompatibilitas: kini meneruskan ke release_macos.sh, yang
# membangun, menandatangani (ad-hoc secara bawaan), dan mengemas ke dist/.
exec "$(dirname "$0")/release_macos.sh" "$@"
