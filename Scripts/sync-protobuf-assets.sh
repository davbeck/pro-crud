#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
source_root="$repo_root/Vendor/ProPresenter7Proto/proto"
core_destination_root="$repo_root/Sources/ProCRUDCore/Resources/Protobuf"
cli_destination_root="$repo_root/Sources/ProCRUDCLI/Resources/Protobuf"

case "${1:-}" in
  "")
    core_output_root="$core_destination_root"
    cli_output_root="$cli_destination_root"
    ;;
  --check)
    temporary_root="$(mktemp -d)"
    trap 'rm -rf "$temporary_root"' EXIT
    core_output_root="$temporary_root/CoreProtobuf"
    cli_output_root="$temporary_root/CLIProtobuf"
    ;;
  *)
    echo "Usage: Scripts/sync-protobuf-assets.sh [--check]" >&2
    exit 64
    ;;
esac

rm -rf "$core_output_root" "$cli_output_root"
mkdir -p "$core_output_root" "$cli_output_root/proto/google/protobuf"
cp "$source_root"/*.proto "$cli_output_root/proto/"
cp "$source_root/google/protobuf/wrappers.proto" "$cli_output_root/proto/google/protobuf/"
cp "$repo_root/Vendor/ProPresenter7Proto/LICENSE" "$cli_output_root/LICENSE"
cp "$repo_root/Vendor/ProPresenter7Proto/README.md" "$cli_output_root/README.md"

protos=()
while IFS= read -r proto; do
  protos+=("$proto")
done < <(find "$source_root" -maxdepth 1 -name '*.proto' -print | sort)
protoc --include_imports --include_source_info --descriptor_set_out="$core_output_root/schema.pb" -I"$source_root" "${protos[@]}"
git -C "$repo_root" log -1 --format=%H -- "Vendor/ProPresenter7Proto/proto" > "$cli_output_root/revision.txt"
(
  cd "$cli_output_root/proto"
  find . -type f -print0 | sort -z | xargs -0 shasum -a 256
) | shasum -a 256 | awk '{print $1}' > "$cli_output_root/content-sha256.txt"

if [[ "${1:-}" == "--check" ]]; then
  diff -ru "$core_destination_root" "$core_output_root"
  diff -ru "$cli_destination_root" "$cli_output_root"
fi
