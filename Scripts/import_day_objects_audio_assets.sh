#!/bin/bash

set -euo pipefail
IFS=$'\n\t'
export LC_ALL=C
export GIT_TERMINAL_PROMPT=0

readonly SYNTH_URL="https://github.com/AudioKit/AudioKitSynthOne.git"
readonly SYNTH_REVISION="6466a3715c96b7ecf1dd255a218cbd571408a314"
readonly COOKBOOK_URL="https://github.com/AudioKit/Cookbook.git"
readonly COOKBOOK_REVISION="c37d41daedf161b47315b7ae24b07f41213b73be"
readonly OSIRIS_URL="https://github.com/sfzinstruments/Osiris_Piano.git"
readonly OSIRIS_REVISION="18c6afccb60cff458edbf7c394571783e074e1e9"
readonly PIANO_FIXED_GAIN_DB="-6.0"

readonly script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
readonly repo_root="$(cd "${script_dir}/.." && pwd -P)"
readonly resource_root="${repo_root}/StepsTrader/Experiments/DayObjects/Sound/Resources"
readonly license_root="${resource_root}/AudioLicenses"
readonly synth_destination="${resource_root}/SynthOnePresets"
readonly drum_destination="${resource_root}/Drums"
readonly piano_destination="${resource_root}/FeltPiano"
readonly manifest_destination="${resource_root}/audio-assets-manifest.json"

fail() {
    printf 'error: %s\n' "$*" >&2
    exit 1
}

for command_name in git jq shasum cmp mktemp afconvert afinfo swift; do
    command -v "${command_name}" >/dev/null 2>&1 || fail "required tool is unavailable: ${command_name}"
done
[[ "$(afconvert -h 2>&1)" == *"Version: 2.0"* ]] || fail "unsupported afconvert version"

[[ -f "${repo_root}/Steps4.xcodeproj/project.pbxproj" ]] || fail "run this importer from the Steps project checkout"
[[ -f "${license_root}/SOURCES.json" ]] || fail "missing pinned source manifest"

readonly temp_root="$(mktemp -d /tmp/day-objects-audio-import.XXXXXX)"
cleanup() {
    if [[ -d "${temp_root}" ]]; then
        find "${temp_root}" -depth -delete
    fi
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

readonly staging_root="${temp_root}/staging"
readonly staged_synth="${staging_root}/SynthOnePresets"
readonly staged_drums="${staging_root}/Drums"
readonly staged_piano="${staging_root}/FeltPiano"
readonly staged_manifest="${staging_root}/audio-assets-manifest.json"
mkdir -p "${staged_synth}" "${staged_drums}" "${staged_piano}"

sha256_file() {
    shasum -a 256 "$1" | awk '{print $1}'
}

verify_hash() {
    local file_path="$1"
    local expected_hash="$2"
    local actual_hash
    [[ -f "${file_path}" ]] || fail "missing pinned input: ${file_path}"
    actual_hash="$(sha256_file "${file_path}")"
    [[ "${actual_hash}" == "${expected_hash}" ]] || fail "SHA-256 mismatch for ${file_path}: expected ${expected_hash}, got ${actual_hash}"
}

clone_pinned_sparse() {
    local name="$1"
    local url="$2"
    local revision="$3"
    local sparse_list="$4"
    local clone_path="${temp_root}/${name}"
    local checked_out_revision

    git clone --quiet --filter=blob:none --no-checkout "${url}" "${clone_path}"
    git -C "${clone_path}" sparse-checkout init --no-cone
    cp "${sparse_list}" "${clone_path}/.git/info/sparse-checkout"
    git -C "${clone_path}" fetch --quiet --depth 1 origin "${revision}"
    git -C "${clone_path}" checkout --quiet --detach FETCH_HEAD
    checked_out_revision="$(git -C "${clone_path}" rev-parse HEAD)"
    [[ "${checked_out_revision}" == "${revision}" ]] || fail "revision mismatch for ${name}: expected ${revision}, got ${checked_out_revision}"
}

verify_license() {
    local upstream_license="$1"
    local bundled_license="$2"
    [[ -f "${upstream_license}" ]] || fail "missing upstream license: ${upstream_license}"
    [[ -f "${bundled_license}" ]] || fail "missing bundled license: ${bundled_license}"
    cmp -s "${upstream_license}" "${bundled_license}" || fail "bundled license differs from pinned upstream: ${bundled_license}"
}

readonly SYNTH_BANK_PATHS=(
    "AudioKitSynthOne/Presets/Data/Bonus.json"
    "AudioKitSynthOne/Presets/Data/Brice Beasley.json"
    "AudioKitSynthOne/Presets/Data/Electronisounds.json"
    "AudioKitSynthOne/Presets/Data/JEC.json"
    "AudioKitSynthOne/Presets/Data/Red Sky Lullaby.json"
    "AudioKitSynthOne/Presets/Data/Spidericemidas.json"
)
readonly SYNTH_BANK_SHA256=(
    "e189a9782469bd851d97a2bd157cfdd43692621287de68eb2909e8aabbd4b996"
    "a42a515cc66fc392f8831efa4865145dc9e2c8a8d9bc2554d1fd8a1aed242d45"
    "94447bcafd93b8e534b99347ef1a2ab7f96006364c36e85c88825e2480a026e7"
    "9af56a4f52d050c98da8bfc6bc355ac872772cdd419def188bb644b0c9dff0c0"
    "db813fe373ebd0c2434c8c0af376b245c331c35080b396bce83bc4d9f2fb0aac"
    "1cb034e91677be3b7bc0cddca64d821ddbfc132d79f98e4211053867f76eec35"
)
readonly SELECTED_UIDS=(
    "39529417-FBC1-41D5-B1D1-0DED9E38F164"
    "96F9F71C-1D6C-41FC-8192-E4B550562357"
    "9BF89CC8-5AD5-46D8-9640-C3FE335C65D9"
    "E9AFAF33-21A5-4A1B-80BF-74BFB333E86D"
    "88335303-C675-4D14-907E-2D80823C2BCA"
    "8FC6202C-DAE8-4651-98DE-F3BEBB07E6BF"
    "C2958050-CDCA-4C64-AF92-3217539CE60A"
    "4131C811-FBB8-4E15-B238-8986645A62D3"
    "FA16AF16-3033-485F-A183-4DAAB7025B52"
    "9BDE3DCB-219D-4D70-A067-C1057B557F19"
    "2B6BCC6D-8526-4CAD-8230-EF3C84A26E9F"
    "BB74B6AD-9076-464C-B373-F2E968BBD2BE"
    "AA903CDB-938B-4FC7-8E01-050DB95EFDE7"
    "6A4C11CA-2CF9-4153-B5D3-A67F28E465A1"
    "9F2D32B0-ED71-4127-A4C5-F51209656AF7"
)
readonly SELECTED_PRESETS_OUTPUT_SHA256="e1eea582d634425605954cf20c201ec34045f0a1f3f48b652b6c2a81442fd063"

readonly DRUM_SOURCE_PATHS=(
    "Cookbook/CookbookCommon/Sources/CookbookCommon/Samples/bass_drum_C1.wav"
    "Cookbook/CookbookCommon/Sources/CookbookCommon/Samples/closed_hi_hat_F#1.wav"
    "Cookbook/CookbookCommon/Sources/CookbookCommon/Samples/open_hi_hat_A#1.wav"
    "Cookbook/CookbookCommon/Sources/CookbookCommon/Samples/clap_D#1.wav"
    "Cookbook/CookbookCommon/Sources/CookbookCommon/Samples/snare_D1.wav"
    "Cookbook/Sounds/cheeb-stick.wav"
    "Cookbook/Sounds/cheeb-hat.wav"
    "Cookbook/Sounds/cheeb-ch.wav"
)
readonly DRUM_OUTPUT_NAMES=(
    "bass_drum_C1.wav"
    "closed_hi_hat_F#1.wav"
    "open_hi_hat_A#1.wav"
    "clap_D#1.wav"
    "snare_D1.wav"
    "cheeb-stick.wav"
    "cheeb-hat.wav"
    "cheeb-ch.wav"
)
readonly DRUM_SOURCE_SHA256=(
    "f682067cb3e717374d27e2c8cdabaa3ea16eb8afe36776f163b46ebed64de5c9"
    "c9f30ff2b4d73b03f41960e504e03c54e9a59697af666fe4d155bab9cd1ccae6"
    "cde0aec2ca84358067859f52bac7d55b875f30d2baea700923e25e21307803e9"
    "376429bb81cb48d1f392a11cd066c32ffb7883d445b2488704ea52e46bb08286"
    "d7fa75dff476baaef99de0b251d86c39aa0e0f36a06043db9a97417350fe4439"
    "2af90d5f8192a71c3caf2746322dee5a593c27256837b0ef7c66e57ec90aa634"
    "33b9b334fb30d3a467f1c5ff28eb6299f08049cd94627c4cd41aafc8e466ab0d"
    "6e18c1bd394fe97bea79f0106aa30285d56c16b78fb7ac9311c85fb502bbc106"
)

readonly PIANO_ROOTS=(C2 E2 G2 C3 E3 G3 C4 E4 G4 C5 E5 G5)
readonly PIANO_ROOT_MIDI=(36 40 43 48 52 55 60 64 67 72 76 79)
readonly PIANO_SOURCE_SHA256=(
    "cce3112e179b2bf20c4b18de67345a4cee8e2f981cdbf58d95e1758d14cc0ef1"
    "d52280ab1804cf9ecd1dd93d8fc245a17b801ffdebe0ff47b07d965fb4f5bf45"
    "af26a649cf2d3de12cf75ff8d403ede451f5c0c81e4cb0500adabb966b44da28"
    "4e509d501311b1fc7e6691cff1127f5a068a2292ec4501f94e68a36183a05e68"
    "58c4188910fd6feb1b31561936f146f89f376dfa9d29acfa7e0c574334a97869"
    "47a25644da5e4b770fd35ba29e53acded50a267985dad2f0d5e8f5a2698fe6ce"
    "f9e1ecef1ae24470796591f09d2d0aed4b320b5a376df8b7abf30c7880628545"
    "592a756ccad9242f461a4af0542bc6bfdcbcfb3624e638baa2a0ac15eef773be"
    "f66433c9210a9a30544dd9b74c7a6688afc168a6476988b33b6745a21429f7af"
    "b402a966e7a9fd5f165d07b92c53d90f06fca9430036c377432d4071de5ae4d5"
    "d3f7e471c4b7ad9f45a6aa4451189423eba33d6d849f1a6603a357fa6f201f00"
    "f7b14111af1078676f761d6e1ff22ef368baf6b895acbe5cfd1555f74cc84ac2"
)
readonly PIANO_OUTPUT_SHA256=(
    "033f516d8e0057b3a757e975996dc0d2134c0ad18878a9b097b626fac55af1c7"
    "52fc1f374b127ae0c0a5ca7574ca26edd121ad570b0be03827b9b5e723ffa96d"
    "b1f50a4cf006d120d1da6f7127e3324b355e12a157a0de99e907cbe9279dd842"
    "a00fd0a10d95de071b37d43684750df700f1ec3a5a36f6ace3401c9cbbb36f93"
    "03d091b7977d949587d06641fe775e648a85fa3f7d1d4a4a19823f707e11e203"
    "d7029053ac37c674351053ccee763cf4090bc0d6fc156b3c1f2d59b5155d997c"
    "07eb5a0d8abbdf039967b59cce5a75d4bb3d0dab2d2018e3dd57122d27dc1127"
    "74c0748b394ce3b02d175938dd537ffcc0f51a9f54758ba855c5708a01f9b563"
    "6f8d9825f3c77fa2fbce627d610fe2c99ca4f32febb9208af966c08713e3f674"
    "a44461ea38774dcf0bbd9a2a406df418c6d63832b61790b56486edf58eacb99e"
    "12b7182462c11c72e6bb7f3deac9c1a55b196cb510e7f6bbf74380c6ccfcdcf6"
    "d900e6d295f3cdd7e142c88564282ee58de3095fa9f715474a09e458f7e58b98"
)

synth_paths_json="$(jq -cn --args '$ARGS.positional' "${SYNTH_BANK_PATHS[@]}")"
drum_paths_json="$(jq -cn --args '$ARGS.positional' "${DRUM_SOURCE_PATHS[@]}")"
piano_source_paths=()
for root_note in "${PIANO_ROOTS[@]}"; do
    piano_source_paths+=("UC-Sus-noisy/A/Piano_UC-Sus_MicA_${root_note}_vl1.flac")
done
piano_paths_json="$(jq -cn --args '$ARGS.positional' "${piano_source_paths[@]}")"
jq -e \
    --argjson synthPaths "${synth_paths_json}" \
    --argjson drumPaths "${drum_paths_json}" \
    --argjson pianoPaths "${piano_paths_json}" \
    '. == [
      {
        project: "AudioKitSynthOne", sourceURL: "https://github.com/AudioKit/AudioKitSynthOne",
        revision: "6466a3715c96b7ecf1dd255a218cbd571408a314",
        licenseFilename: "AudioKitSynthOne-MIT.txt", selectedPaths: $synthPaths
      },
      {
        project: "AudioKit/Cookbook", sourceURL: "https://github.com/AudioKit/Cookbook",
        revision: "c37d41daedf161b47315b7ae24b07f41213b73be",
        licenseFilename: "AudioKitCookbook-MIT.txt", selectedPaths: $drumPaths
      },
      {
        project: "sfzinstruments/Osiris_Piano", sourceURL: "https://github.com/sfzinstruments/Osiris_Piano",
        revision: "18c6afccb60cff458edbf7c394571783e074e1e9",
        licenseFilename: "OsirisPiano-CC0-1.0.txt", selectedPaths: $pianoPaths
      }
    ]' "${license_root}/SOURCES.json" >/dev/null || fail "SOURCES.json differs from the pinned import contract"

readonly synth_sparse_list="${temp_root}/synth-sparse.txt"
printf '/LICENSE\n' > "${synth_sparse_list}"
for source_path in "${SYNTH_BANK_PATHS[@]}"; do
    printf '/%s\n' "${source_path}" >> "${synth_sparse_list}"
done
clone_pinned_sparse "AudioKitSynthOne" "${SYNTH_URL}" "${SYNTH_REVISION}" "${synth_sparse_list}"
readonly synth_clone="${temp_root}/AudioKitSynthOne"
verify_license "${synth_clone}/LICENSE" "${license_root}/AudioKitSynthOne-MIT.txt"

synth_bank_files=()
for index in "${!SYNTH_BANK_PATHS[@]}"; do
    source_file="${synth_clone}/${SYNTH_BANK_PATHS[$index]}"
    verify_hash "${source_file}" "${SYNTH_BANK_SHA256[$index]}"
    synth_bank_files+=("${source_file}")
done

selected_uids_json="$(jq -cn --args '$ARGS.positional' "${SELECTED_UIDS[@]}")"
jq -S -s --argjson selected "${selected_uids_json}" \
    '[.[][] | select((.uid // "") as $uid | $selected | index($uid))] | sort_by(.uid)' \
    "${synth_bank_files[@]}" > "${staged_synth}/selected-presets.json"
chmod 0644 "${staged_synth}/selected-presets.json"
jq -e --argjson selected "${selected_uids_json}" \
    'length == ($selected | length)
     and (([.[].uid] | sort) == ($selected | sort))
     and (group_by(.uid) | map(length == 1) | all)' \
    "${staged_synth}/selected-presets.json" >/dev/null || fail "selected Synth One UIDs were not found exactly once"

readonly cookbook_sparse_list="${temp_root}/cookbook-sparse.txt"
printf '/LICENSE\n' > "${cookbook_sparse_list}"
for source_path in "${DRUM_SOURCE_PATHS[@]}"; do
    printf '/%s\n' "${source_path}" >> "${cookbook_sparse_list}"
done
clone_pinned_sparse "Cookbook" "${COOKBOOK_URL}" "${COOKBOOK_REVISION}" "${cookbook_sparse_list}"
readonly cookbook_clone="${temp_root}/Cookbook"
verify_license "${cookbook_clone}/LICENSE" "${license_root}/AudioKitCookbook-MIT.txt"

for index in "${!DRUM_SOURCE_PATHS[@]}"; do
    source_file="${cookbook_clone}/${DRUM_SOURCE_PATHS[$index]}"
    output_file="${staged_drums}/${DRUM_OUTPUT_NAMES[$index]}"
    verify_hash "${source_file}" "${DRUM_SOURCE_SHA256[$index]}"
    cp "${source_file}" "${output_file}"
    chmod 0644 "${output_file}"
    verify_hash "${output_file}" "${DRUM_SOURCE_SHA256[$index]}"
done

readonly osiris_sparse_list="${temp_root}/osiris-sparse.txt"
printf '/LICENSE\n' > "${osiris_sparse_list}"
for root_note in "${PIANO_ROOTS[@]}"; do
    printf '/UC-Sus-noisy/A/Piano_UC-Sus_MicA_%s_vl1.flac\n' "${root_note}" >> "${osiris_sparse_list}"
done
clone_pinned_sparse "Osiris_Piano" "${OSIRIS_URL}" "${OSIRIS_REVISION}" "${osiris_sparse_list}"
readonly osiris_clone="${temp_root}/Osiris_Piano"
verify_license "${osiris_clone}/LICENSE" "${license_root}/OsirisPiano-CC0-1.0.txt"

apply_fixed_gain() {
    local input_file="$1"
    local output_file="$2"
    local gain_db="$3"
    swift - "${input_file}" "${output_file}" "${gain_db}" <<'SWIFT'
import AVFoundation
import Foundation

guard CommandLine.arguments.count == 4,
      let gainDB = Double(CommandLine.arguments[3]) else {
    throw NSError(domain: "DayObjectsAudioImport", code: 1)
}

let inputURL = URL(fileURLWithPath: CommandLine.arguments[1])
let outputURL = URL(fileURLWithPath: CommandLine.arguments[2])
let input = try AVAudioFile(forReading: inputURL)
guard input.processingFormat.channelCount == 1,
      input.processingFormat.sampleRate == 44_100,
      input.processingFormat.commonFormat == .pcmFormatFloat32 else {
    throw NSError(domain: "DayObjectsAudioImport", code: 2)
}

let output = try AVAudioFile(
    forWriting: outputURL,
    settings: input.processingFormat.settings,
    commonFormat: .pcmFormatFloat32,
    interleaved: input.processingFormat.isInterleaved
)
let capacity: AVAudioFrameCount = 16_384
guard let buffer = AVAudioPCMBuffer(pcmFormat: input.processingFormat, frameCapacity: capacity) else {
    throw NSError(domain: "DayObjectsAudioImport", code: 3)
}
let linearGain = Float(pow(10.0, gainDB / 20.0))

while input.framePosition < input.length {
    let remaining = input.length - input.framePosition
    let frames = AVAudioFrameCount(min(Int64(capacity), remaining))
    try input.read(into: buffer, frameCount: frames)
    guard let channels = buffer.floatChannelData else {
        throw NSError(domain: "DayObjectsAudioImport", code: 4)
    }
    for channel in 0..<Int(buffer.format.channelCount) {
        for frame in 0..<Int(buffer.frameLength) {
            channels[channel][frame] *= linearGain
        }
    }
    try output.write(from: buffer)
}
SWIFT
}

for index in "${!PIANO_ROOTS[@]}"; do
    root_note="${PIANO_ROOTS[$index]}"
    source_path="UC-Sus-noisy/A/Piano_UC-Sus_MicA_${root_note}_vl1.flac"
    source_file="${osiris_clone}/${source_path}"
    intermediate_file="${temp_root}/felt_${root_note}-mono-float.caf"
    gained_file="${temp_root}/felt_${root_note}-gained-float.caf"
    output_file="${staged_piano}/felt_${root_note}.caf"

    verify_hash "${source_file}" "${PIANO_SOURCE_SHA256[$index]}"
    afconvert "${source_file}" "${intermediate_file}" -f caff -d LEF32@44100 -c 1 --mix
    apply_fixed_gain "${intermediate_file}" "${gained_file}" "${PIANO_FIXED_GAIN_DB}"
    afconvert "${gained_file}" "${output_file}" -f caff -d LEI24@44100 -c 1
    chmod 0644 "${output_file}"

    format_info="$(afinfo -b "${output_file}")"
    [[ "${format_info}" == *"1 ch,"* ]] || fail "converted piano sample is not mono: ${output_file}"
    [[ "${format_info}" == *"44100 Hz"* ]] || fail "converted piano sample is not 44.1 kHz: ${output_file}"
    [[ "${format_info}" == *"24-bit"* ]] || fail "converted piano sample is not 24-bit: ${output_file}"
done

output_mismatch=0
check_output_hash() {
    local output_file="$1"
    local expected_hash="$2"
    local actual_hash
    actual_hash="$(sha256_file "${output_file}")"
    if [[ "${actual_hash}" != "${expected_hash}" ]]; then
        printf 'output SHA-256 mismatch for %s: expected %s, got %s\n' "${output_file##*/}" "${expected_hash}" "${actual_hash}" >&2
        output_mismatch=1
    fi
}

check_output_hash "${staged_synth}/selected-presets.json" "${SELECTED_PRESETS_OUTPUT_SHA256}"
for index in "${!PIANO_ROOTS[@]}"; do
    check_output_hash "${staged_piano}/felt_${PIANO_ROOTS[$index]}.caf" "${PIANO_OUTPUT_SHA256[$index]}"
done
[[ "${output_mismatch}" -eq 0 ]] || fail "generated outputs do not match the pinned inventory"

readonly asset_rows="${temp_root}/asset-rows.jsonl"
readonly synth_source_rows="${temp_root}/synth-source-rows.jsonl"
for index in "${!SYNTH_BANK_PATHS[@]}"; do
    jq -cn \
        --arg path "${SYNTH_BANK_PATHS[$index]}" \
        --arg sha256 "${SYNTH_BANK_SHA256[$index]}" \
        '{path: $path, sha256: $sha256}' >> "${synth_source_rows}"
done
synth_source_files="$(jq -s '.' "${synth_source_rows}")"
jq -cn \
    --arg path "SynthOnePresets/selected-presets.json" \
    --arg sha256 "$(sha256_file "${staged_synth}/selected-presets.json")" \
    --arg sourceKey "AudioKitSynthOne" \
    --arg licenseFilename "AudioKitSynthOne-MIT.txt" \
    --argjson sourceFiles "${synth_source_files}" \
    --argjson presetUIDs "${selected_uids_json}" \
    '{path: $path, sha256: $sha256, sourceKey: $sourceKey, licenseFilename: $licenseFilename,
      sourceFiles: $sourceFiles, presetUIDs: $presetUIDs}' >> "${asset_rows}"

for index in "${!DRUM_SOURCE_PATHS[@]}"; do
    jq -cn \
        --arg path "Drums/${DRUM_OUTPUT_NAMES[$index]}" \
        --arg sha256 "${DRUM_SOURCE_SHA256[$index]}" \
        --arg sourceKey "AudioKit/Cookbook" \
        --arg licenseFilename "AudioKitCookbook-MIT.txt" \
        --arg sourcePath "${DRUM_SOURCE_PATHS[$index]}" \
        --arg sourceSHA256 "${DRUM_SOURCE_SHA256[$index]}" \
        '{path: $path, sha256: $sha256, sourceKey: $sourceKey, licenseFilename: $licenseFilename,
          sourceFiles: [{path: $sourcePath, sha256: $sourceSHA256}]}' >> "${asset_rows}"
done

for index in "${!PIANO_ROOTS[@]}"; do
    root_note="${PIANO_ROOTS[$index]}"
    output_path="${staged_piano}/felt_${root_note}.caf"
    source_path="UC-Sus-noisy/A/Piano_UC-Sus_MicA_${root_note}_vl1.flac"
    jq -cn \
        --arg path "FeltPiano/felt_${root_note}.caf" \
        --arg sha256 "$(sha256_file "${output_path}")" \
        --arg sourceKey "sfzinstruments/Osiris_Piano" \
        --arg licenseFilename "OsirisPiano-CC0-1.0.txt" \
        --arg sourcePath "${source_path}" \
        --arg sourceSHA256 "${PIANO_SOURCE_SHA256[$index]}" \
        --arg rootNote "${root_note}" \
        --argjson rootMIDINote "${PIANO_ROOT_MIDI[$index]}" \
        --argjson normalizationGainDB "${PIANO_FIXED_GAIN_DB}" \
        '{path: $path, sha256: $sha256, sourceKey: $sourceKey, licenseFilename: $licenseFilename,
          sourceFiles: [{path: $sourcePath, sha256: $sourceSHA256}], rootNote: $rootNote,
          rootMIDINote: $rootMIDINote, velocityLayer: 1, normalizationGainDB: $normalizationGainDB,
          conversion: {tool: "afconvert", channels: 1, sampleRateHz: 44100, bitDepth: 24}}' >> "${asset_rows}"
done

assets_json="$(jq -s '.' "${asset_rows}")"
jq -S -n \
    --argjson assets "${assets_json}" \
    --arg synthURL "${SYNTH_URL%.git}" \
    --arg synthRevision "${SYNTH_REVISION}" \
    --arg cookbookURL "${COOKBOOK_URL%.git}" \
    --arg cookbookRevision "${COOKBOOK_REVISION}" \
    --arg osirisURL "${OSIRIS_URL%.git}" \
    --arg osirisRevision "${OSIRIS_REVISION}" \
    '{
      schemaVersion: 1,
      sources: {
        "AudioKitSynthOne": {
          creator: "AudioKit contributors", sourceURL: $synthURL, revision: $synthRevision,
          licenseIdentifier: "MIT", licenseFilename: "AudioKitSynthOne-MIT.txt"
        },
        "AudioKit/Cookbook": {
          creator: "AudioKit contributors", sourceURL: $cookbookURL, revision: $cookbookRevision,
          licenseIdentifier: "MIT", licenseFilename: "AudioKitCookbook-MIT.txt"
        },
        "sfzinstruments/Osiris_Piano": {
          creator: "Karoryfer Samples / sfzinstruments contributors", sourceURL: $osirisURL,
          revision: $osirisRevision, licenseIdentifier: "CC0-1.0",
          licenseFilename: "OsirisPiano-CC0-1.0.txt",
          redistributionAndModificationRights: "CC0 1.0 public-domain dedication permits copying, modification, and redistribution, including commercial use."
        }
      },
      assets: $assets
    }' > "${staged_manifest}"
chmod 0644 "${staged_manifest}"
jq -e '.schemaVersion == 1 and (.assets | length == 21)' "${staged_manifest}" >/dev/null || fail "generated asset manifest is incomplete"

validate_destination() {
    local destination="$1"
    shift
    local existing_path
    local existing_name
    local allowed_name
    local is_allowed
    [[ -d "${destination}" ]] || return 0
    while IFS= read -r existing_path; do
        existing_name="${existing_path##*/}"
        is_allowed=0
        for allowed_name in "$@"; do
            if [[ "${existing_name}" == "${allowed_name}" ]]; then
                is_allowed=1
                break
            fi
        done
        [[ "${is_allowed}" -eq 1 ]] || fail "refusing to replace unrelated destination entry: ${existing_path}"
    done < <(find "${destination}" -mindepth 1 -maxdepth 1 -print)
}

validate_destination "${synth_destination}" "selected-presets.json"
validate_destination "${drum_destination}" "${DRUM_OUTPUT_NAMES[@]}"
piano_output_names=()
for root_note in "${PIANO_ROOTS[@]}"; do
    piano_output_names+=("felt_${root_note}.caf")
done
validate_destination "${piano_destination}" "${piano_output_names[@]}"
if [[ -e "${manifest_destination}" && ! -f "${manifest_destination}" ]]; then
    fail "refusing to replace non-file manifest destination: ${manifest_destination}"
fi

mkdir -p "${synth_destination}" "${drum_destination}" "${piano_destination}"
cp "${staged_synth}/selected-presets.json" "${synth_destination}/selected-presets.json"
chmod 0644 "${synth_destination}/selected-presets.json"
for output_name in "${DRUM_OUTPUT_NAMES[@]}"; do
    cp "${staged_drums}/${output_name}" "${drum_destination}/${output_name}"
    chmod 0644 "${drum_destination}/${output_name}"
done
for output_name in "${piano_output_names[@]}"; do
    cp "${staged_piano}/${output_name}" "${piano_destination}/${output_name}"
    chmod 0644 "${piano_destination}/${output_name}"
done
cp "${staged_manifest}" "${manifest_destination}"
chmod 0644 "${manifest_destination}"

printf 'Imported 15 Synth One presets, 8 drum samples, and 12 felt-piano samples.\n'
