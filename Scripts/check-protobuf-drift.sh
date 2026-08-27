#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
temporary_root="$(mktemp -d)"
trap 'rm -rf "$temporary_root"' EXIT
proto_root="$repo_root/Vendor/ProPresenter7Proto/proto"

command -v protoc >/dev/null
command -v protoc-gen-swift >/dev/null
protos=()
while IFS= read -r proto; do
  protos+=("$proto")
done < <(find "$proto_root" -maxdepth 1 -name '*.proto' -print | sort)
protoc --swift_out="$temporary_root" --swift_opt=Visibility=Public -I"$proto_root" "${protos[@]}"
diff -ru "$repo_root/Sources/ProPresenterProto/Generated" "$temporary_root"
"$repo_root/Scripts/sync-protobuf-assets.sh" --check
