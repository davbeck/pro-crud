#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
bin_path="${PRO_CRUD_BIN_PATH:-$(cd "$repo_root" && swift build --show-bin-path)/pro-crud}"
bin_directory="$(CDPATH= cd -- "$(dirname -- "$bin_path")" && pwd)"
workspace="$(mktemp -d "${TMPDIR:-/tmp}/pro-crud-cli.XXXXXX")"
fixture_media="$repo_root/Fixtures/ProPresenter/Media/frame-test-30fps-480p.mp4"

run() {
  "$bin_path" "$@" >/dev/null
}

expect_failure() {
  if "$bin_path" "$@" >/dev/null 2>&1; then
    echo "Expected command to fail: pro-crud $*" >&2
    exit 1
  fi
}

presentation="$workspace/Acceptance.pro"
presentation_copy="$workspace/Acceptance Copy.pro"
theme_dir="$workspace/Theme"
playlist_dir="$workspace/Playlist"
design_theme="$repo_root/skills/pro-crud/assets/themes/ProCRUD Design System.proTheme"

run create presentation --output "$presentation" --name Acceptance
expect_failure create presentation --output "$presentation" --name Duplicate
run create presentation --output "$presentation" --name Acceptance --replace
run dump "$presentation"
run dump "$presentation" --format protobuf-json
run dump "$presentation" --path '/cues[index=0]/actions[index=0]'
run dump "$presentation" --format protobuf-json --path '/cues[index=0]/actions[index=0]'
expect_failure dump "$presentation" --path '/cues'
expect_failure dump "$presentation" --path '/cues[name=Missing]'

run edit patch "$presentation" --path / --json '{"name":"Patched"}' --output "$presentation_copy"
expect_failure edit patch "$presentation" --path / --json '{"name":"Patched"}' --output "$presentation_copy"
run edit patch "$presentation" --path / --json '{"name":"Patched"}' --output "$presentation_copy" --replace
printf '%s\n' '{"notes":"Patched from a JSON file"}' > "$workspace/patch.json"
run edit patch "$presentation" --path / --json-file "$workspace/patch.json"
expect_failure edit patch "$presentation" --path / --json '{"name":"Wrong Output"}' --output "$workspace/WrongOutput"
run edit add-slide "$presentation" --group '/cue_groups[index=0]'
run edit add-slide "$presentation" --group '/cue_groups[index=0]' --duplicate '/cues[index=0]'
run edit add-slide "$presentation" --group '/cue_groups[index=0]' --duplicate '/cues[index=0]/actions[index=0]/slide/presentation/base_slide'
run edit rename "$presentation" --path '/cues[index=1]' --name Renamed
run edit duplicate "$presentation" --path '/cues[name=Renamed]'
run edit move "$presentation" --path '/cues[name="Renamed Copy"]' --after '/cues[index=0]'
run edit remove "$presentation" --path '/cues[name="Renamed Copy"]'
run edit add-element "$presentation" --path '/cues[index=0]/actions[index=0]/slide/presentation/base_slide' --name Accent --bounds 20,20,300,200 --color '#E85D4A'
run edit set-background "$presentation" --path '/cues[index=0]/actions[index=0]/slide/presentation/base_slide' --color '#123456'
run edit set-media "$presentation" --path '/cues[index=0]/actions[index=0]/slide/presentation/base_slide/elements[index=0]/element' --source "$fixture_media"
run edit add-action "$presentation" --path '/cues[index=0]' --type timer --name Timer
run edit remove-action "$presentation" --path '/cues[index=0]/actions[name=Timer]'

printf '%s\n' '[
  {"command":"patch","path":"/","json":"{\"name\":\"Batch Acceptance\"}"},
  {"command":"add-slide","group":"/cue_groups[index=0]"},
  {"command":"rename","path":"/cues[index=1]","name":"Batched Slide"}
]' > "$workspace/batch.json"
run edit apply "$presentation" --file "$workspace/batch.json"
batch_summary="$("$bin_path" dump "$presentation")"
[[ "$batch_summary" == *"Batch Acceptance"* ]]
[[ "$batch_summary" == *"Batched Slide"* ]]

before_failed_batch="$("$bin_path" dump "$presentation" --format protobuf-json)"
printf '%s\n' '[
  {"command":"rename","path":"/cues[index=0]","name":"Must Not Persist"},
  {"command":"remove","path":"/cues[name=Missing]"}
]' > "$workspace/failing-batch.json"
expect_failure edit apply "$presentation" --file "$workspace/failing-batch.json"
after_failed_batch="$("$bin_path" dump "$presentation" --format protobuf-json)"
[[ "$before_failed_batch" == "$after_failed_batch" ]]

styled_presentation="$workspace/Styled.pro"
run create presentation --output "$styled_presentation" --name Styled --theme "$design_theme" --template 'ProCRUD - Streaming/Theme#0'
run edit set-text "$styled_presentation" --path '/cues[index=0]/actions[index=0]/slide/presentation/base_slide/elements[index=0]/element/text' --text 'Acceptance text'
styled_summary="$("$bin_path" dump "$styled_presentation" --path '/cues[index=0]/actions[index=0]/slide/presentation/base_slide/elements[index=0]/element')"
[[ "$styled_summary" == *"Acceptance text"* ]]
inline_rtf='{\rtf1\ansi Inline \b bold\b0}'
run edit set-text "$styled_presentation" --path '/cues[index=0]/actions[index=0]/slide/presentation/base_slide/elements[index=0]/element/text' --rtf "$inline_rtf"
inline_summary="$("$bin_path" dump "$styled_presentation" --path '/cues[index=0]/actions[index=0]/slide/presentation/base_slide/elements[index=0]/element')"
[[ "$inline_summary" == *"Inline bold"* ]]
printf '%s\n' '{\rtf1\ansi File \i italic\i0}' > "$workspace/content.rtf"
run edit set-text "$styled_presentation" --path '/cues[index=0]/actions[index=0]/slide/presentation/base_slide/elements[index=0]/element/text' --rtf-file "$workspace/content.rtf"
file_summary="$("$bin_path" dump "$styled_presentation" --path '/cues[index=0]/actions[index=0]/slide/presentation/base_slide/elements[index=0]/element')"
[[ "$file_summary" == *"File italic"* ]]
expect_failure edit set-text "$styled_presentation" --path '/cues[index=0]/actions[index=0]/slide/presentation/base_slide/elements[index=0]/element/text'
expect_failure edit set-text "$styled_presentation" --path '/cues[index=0]/actions[index=0]/slide/presentation/base_slide/elements[index=0]/element/text' --text Plain --rtf "$inline_rtf"
run render "$styled_presentation" --format json --output "$workspace/Styled.json"
test -s "$workspace/Styled.json"
grep -q '"layerOrder" : "back-to-front"' "$workspace/Styled.json"
grep -q '"effectiveRTF"' "$workspace/Styled.json"

run create theme --output "$theme_dir/Theme" --name Acceptance
run edit add-template "$theme_dir/Theme" --name Template
run edit patch "$theme_dir/Theme" --path '/slides[index=0]' --json '{"name":"Patched Template"}'
run edit rename "$theme_dir/Theme" --path '/slides[index=0]' --name Template
run edit duplicate "$theme_dir/Theme" --path '/slides[name=Template]'
run edit move "$theme_dir/Theme" --path '/slides[name="Template Copy"]' --after '/slides[name=Template]'
run edit remove "$theme_dir/Theme" --path '/slides[name="Template Copy"]'
run create presentation --output "$workspace/Component Theme.pro" --name "Component Theme" --theme "$theme_dir" --template '/slides[index=0]'
expect_failure edit patch "$theme_dir/Theme" --path / --json '{"slides":[]}' --output "$workspace/WrongTheme.pro"
run bundle "$theme_dir" --output "$workspace/Acceptance.proTheme"
run edit add-template "$workspace/Acceptance.proTheme" --name 'Bundled Template'
bundled_theme_summary="$("$bin_path" dump "$workspace/Acceptance.proTheme" --path '/slides[name="Bundled Template"]')"
[[ "$bundled_theme_summary" == *"Bundled Template"* ]]
run expand "$workspace/Acceptance.proTheme" --output "$workspace/Expanded Theme"
run render "$workspace/Acceptance.proTheme" --format png --output "$workspace/Theme Renders"
test -s "$workspace/Theme Renders/1.png"
run dump "$design_theme"
run dump "$design_theme" --format protobuf-json

cp "$theme_dir/Theme" "$workspace/Disguised.pro"
expect_failure dump "$workspace/Disguised.pro"
expect_failure bundle "$workspace/Disguised.pro" --output "$workspace/Disguised.probundle"

run create playlist --output "$playlist_dir/data" --name Acceptance
run create presentation --output "$playlist_dir/Presentation.pro" --name "Playlist Presentation"
run edit add-playlist-item "$playlist_dir/data" --type header --name Header
run edit add-playlist-item "$playlist_dir/data" --type presentation --name Presentation --document "$playlist_dir/Presentation.pro"
playlist_items_path='/root_node/playlists/playlists[index=0]/items/items'
run edit rename "$playlist_dir/data" --path "${playlist_items_path}[name=Header]" --name Intro
run edit duplicate "$playlist_dir/data" --path "${playlist_items_path}[name=Intro]"
run edit move "$playlist_dir/data" --path "${playlist_items_path}[name=\"Intro Copy\"]" --after "${playlist_items_path}[name=Presentation]"
run edit remove "$playlist_dir/data" --path "${playlist_items_path}[name=\"Intro Copy\"]"
run dump "$playlist_dir/data" --path "${playlist_items_path}[name=Intro]"
run edit patch "$playlist_dir/data" --path /root_node --json '{"name":"Patched Playlist"}'
expect_failure edit patch "$playlist_dir/data" --path /root_node --json '{"name":"Wrong Output"}' --output "$workspace/WrongPlaylist.pro"
run bundle "$playlist_dir" --output "$workspace/Acceptance.proPlaylist"
run edit patch "$workspace/Acceptance.proPlaylist" --path /root_node --json '{"name":"Bundled Playlist"}'
bundled_playlist_summary="$("$bin_path" dump "$workspace/Acceptance.proPlaylist" --path /root_node)"
[[ "$bundled_playlist_summary" == *"Bundled Playlist"* ]]
run expand "$workspace/Acceptance.proPlaylist" --output "$workspace/Expanded Playlist"
run render "$workspace/Acceptance.proPlaylist" --format jpg --output "$workspace/Playlist Renders"
test -s "$workspace/Playlist Renders/Presentation/1.jpg"

ordered_playlist_dir="$workspace/Ordered Playlist"
run create playlist --output "$ordered_playlist_dir/data" --name Ordered
run create presentation --output "$ordered_playlist_dir/First.pro" --name First
run create presentation --output "$ordered_playlist_dir/Second.pro" --name Second
run create presentation --output "$ordered_playlist_dir/Unreferenced.pro" --name Unreferenced
run edit add-playlist-item "$ordered_playlist_dir/data" --type presentation --name Second --document "$ordered_playlist_dir/Second.pro"
run edit add-playlist-item "$ordered_playlist_dir/data" --type presentation --name First --document "$ordered_playlist_dir/First.pro"
playlist_json="$("$bin_path" dump "$ordered_playlist_dir/data" --format protobuf-json)"
[[ "$playlist_json" == *'"name" : "Second"'*'"name" : "First"'* ]]
run bundle "$ordered_playlist_dir" --output "$workspace/Ordered.proPlaylist"
run render "$workspace/Ordered.proPlaylist" --format png --output "$workspace/Ordered Renders"
test -s "$workspace/Ordered Renders/Second/1.png"
test -s "$workspace/Ordered Renders/First/1.png"
test ! -e "$workspace/Ordered Renders/Unreferenced"
run render "$workspace/Ordered.proPlaylist" --format pdf --output "$workspace/Ordered.pdf"

run bundle "$presentation" --output "$workspace/Acceptance.probundle"
printf '%s\n' '[
  {"command":"patch","path":"/","json":"{\"name\":\"Bundled Presentation\"}"},
  {"command":"set-media","path":"/cues[index=0]/actions[index=0]/slide/presentation/base_slide/elements[index=0]/element","source":"'"$repo_root"'/Fixtures/ProPresenter/Media/ImageSample.png"}
]' > "$workspace/bundle-batch.json"
run edit apply "$workspace/Acceptance.probundle" --file "$workspace/bundle-batch.json"
bundle_summary="$("$bin_path" dump "$workspace/Acceptance.probundle")"
[[ "$bundle_summary" == *"Bundled Presentation"* ]]
bundle_entries="$(unzip -Z1 "$workspace/Acceptance.probundle")"
[[ "$bundle_entries" == *'ImageSample.png'* ]]
[[ "$bundle_entries" == *'frame-test-30fps-480p.mp4'* ]]
run expand "$workspace/Acceptance.probundle" --output "$workspace/Expanded Presentation"
run render "$presentation" --format png --output "$workspace/PNG"
run render "$presentation" --format jpg --output "$workspace/JPG"
run render "$presentation" --format heic --output "$workspace/HEIC"
run render "$presentation" --format pdf --output "$workspace/Acceptance.pdf"
run render "$presentation" --format pdf,png,json --slide 2 --slide 4 --output "$workspace/Preview"
test -s "$workspace/Preview/Acceptance.pdf"
test -s "$workspace/Preview/Acceptance.json"
test -s "$workspace/Preview/2.png"
test -s "$workspace/Preview/4.png"
test ! -e "$workspace/Preview/1.png"
grep -q '"index" : 1' "$workspace/Preview/Acceptance.json"
grep -q '"index" : 3' "$workspace/Preview/Acceptance.json"
expect_failure render "$presentation" --format png --slide 0 --output "$workspace/Invalid Slide"
expect_failure render "$presentation" --format png --slide 999 --output "$workspace/Missing Slide"
mkdir -p "$workspace/Merge"
run render "$presentation" --format png --output "$workspace/Merge" --merge
expect_failure render "$presentation" --format png --output "$workspace/Merge" --merge
run render "$presentation" --format png --output "$workspace/Merge" --replace

run docs format --format markdown --output "$workspace/format.md"
expect_failure docs format --format markdown --output "$workspace/format.md"
run docs format --format markdown --output "$workspace/format.md" --replace
run docs format --format json --output "$workspace/format.json"
run docs protobuf --format markdown --output "$workspace/protobuf.md"
run docs protobuf --format json --output "$workspace/protobuf.json"
protobuf_export_log="$("$bin_path" docs protobuf export --format json --output "$workspace/protobuf-export.json")"
run docs protobuf export --format descriptor-set --output "$workspace/schema.pb"
expect_failure docs protobuf export --format descriptor-set --output "$workspace/schema.pb"
run docs protobuf export --format descriptor-set --output "$workspace/schema.pb" --replace
run docs protobuf export --format proto --output "$workspace/proto"
test -s "$workspace/proto/LICENSE"
test -s "$workspace/proto/README.md"
expect_failure docs protobuf export --format proto --output "$workspace/proto"
run docs protobuf export --format proto --output "$workspace/proto" --replace

skill_config="$workspace/Claude Config"
CLAUDE_CONFIG_DIR="$skill_config" "$bin_path" skill install --agent claude >/dev/null
installed_skill="$skill_config/skills/pro-crud"
test -L "$installed_skill"
test "$(readlink "$installed_skill")" = \
  "$bin_directory/ProCRUD_ProCRUDCLI.bundle/skills/pro-crud"
cmp -s \
  "$repo_root/skills/pro-crud/assets/themes/ProCRUD Design System.proTheme" \
  "$installed_skill/assets/themes/ProCRUD Design System.proTheme"
cmp -s \
  "$repo_root/skills/pro-crud/references/background-sourcing.md" \
  "$installed_skill/references/background-sourcing.md"
run dump "$installed_skill/assets/themes/ProCRUD Design System.proTheme"

test -s "$workspace/PNG/1.png"
test -s "$workspace/JPG/1.jpg"
test -s "$workspace/HEIC/1.heic"
test -s "$workspace/Acceptance.pdf"
test -s "$workspace/Ordered.pdf"
test -s "$workspace/format.md"
test -s "$workspace/protobuf.json"
test -s "$workspace/protobuf-export.json"
test -s "$workspace/schema.pb"
test -f "$workspace/proto/presentation.proto"
cmp -s "$workspace/protobuf.json" "$workspace/protobuf-export.json"
schema_revision="$(sed -n 's/.*"revision" : "\([^"]*\)".*/\1/p' "$workspace/protobuf.json" | tail -1)"
schema_hash="$(sed -n 's/.*"contentHash" : "\([^"]*\)".*/\1/p' "$workspace/protobuf.json" | tail -1)"
grep -Fq "Schema revision: \`$schema_revision\`" "$workspace/protobuf.md"
grep -Fq "Schema content hash: \`$schema_hash\`" "$workspace/protobuf.md"
[[ "$protobuf_export_log" == *"Schema revision: $schema_revision"* ]]
[[ "$protobuf_export_log" == *"Schema content hash: $schema_hash"* ]]

echo "CLI acceptance passed: $workspace"
