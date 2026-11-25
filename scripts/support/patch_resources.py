#!/usr/bin/env python3
"""Add the app resources to each app target's own resource phase.

`PlinxApp/project.yml` lists the app resources under `resources:`, which
XcodeGen does not read, so this post-generation step adds them.

Each app target must end up with exactly one PBXResourcesBuildPhase and its own
PBXBuildFile objects:

- When XcodeGen already generated a resource phase for the target (it does for
  the license texts in `Core/Resources/Licenses`), the resources are added to
  that phase. A second phase makes Xcode warn that the target "has multiple
  Copy Bundle Resources build phases" and mis-route the generated asset symbol
  source into a resource phase.
- When XcodeGen generated none, a target-owned phase is created after the
  target's other build phases.

Sharing a phase or a build-file object between iOS and tvOS can cause Xcode's
build system to copy resources into only one product.

Safe to re-run: all inserted identifiers are deterministic and idempotent.
Pass a project.pbxproj path to patch a different file (used for testing).
"""

from pathlib import Path
import re
import sys


ROOT_DIR = Path(__file__).resolve().parents[2]
PBXPROJ = (
    Path(sys.argv[1])
    if len(sys.argv) > 1
    else ROOT_DIR / "PlinxApp/Plinx.xcodeproj/project.pbxproj"
)

FILE_REFS = {
    "demo_media": ("F10000000000000000000006", "DemoMedia", "folder", "Resources/DemoMedia"),
    "plinx_strings": ("F10000000000000000000001", "Plinx.strings", "text.plist.strings", "Resources/en.lproj/Plinx.strings"),
    "local_strings": ("F10000000000000000000002", "Localizable.xcstrings", "text.json.xcstrings", "Resources/Localizable.xcstrings"),
    "assets": ("F10000000000000000000003", "Assets.xcassets", "folder.assetcatalog", "Resources/Assets.xcassets"),
    "launch": ("F10000000000000000000004", "LaunchScreen.storyboard", "file.storyboard", "Resources/LaunchScreen.storyboard"),
    "privacy": ("F10000000000000000000005", "PrivacyInfo.xcprivacy", "text.xml", "Resources/PrivacyInfo.xcprivacy"),
}

IOS_BUILD_FILES = {
    "demo_media": ("F10000000000000000000016", "DemoMedia in Resources"),
    "plinx_strings": ("F10000000000000000000011", "Plinx.strings in Resources"),
    "local_strings": ("F10000000000000000000012", "Localizable.xcstrings in Resources"),
    "assets": ("F10000000000000000000013", "Assets.xcassets in Resources"),
    "launch": ("F10000000000000000000014", "LaunchScreen.storyboard in Resources"),
    "privacy": ("F10000000000000000000015", "PrivacyInfo.xcprivacy in Resources"),
}

TVOS_BUILD_FILES = {
    "demo_media": ("F10000000000000000000026", "DemoMedia in Resources"),
    "plinx_strings": ("F10000000000000000000021", "Plinx.strings in Resources"),
    "local_strings": ("F10000000000000000000022", "Localizable.xcstrings in Resources"),
    "assets": ("F10000000000000000000023", "Assets.xcassets in Resources"),
    "privacy": ("F10000000000000000000025", "PrivacyInfo.xcprivacy in Resources"),
}

# Used only when XcodeGen generated no resource phase for the target.
IOS_RESOURCES_PHASE = "F10000000000000000000031"
TVOS_RESOURCES_PHASE = "F10000000000000000000032"

RESOURCES_SECTION_BEGIN = "/* Begin PBXResourcesBuildPhase section */"
RESOURCES_SECTION_END = "/* End PBXResourcesBuildPhase section */"


def insert_before_marker(content: str, marker: str, snippet: str, unique_token: str) -> str:
    if unique_token in content:
        return content
    if marker not in content:
        raise RuntimeError(f"Could not find project marker: {marker}")
    return content.replace(marker, snippet + marker, 1)


def target_build_phases(content: str, target_name: str) -> re.Match[str]:
    target_pattern = re.compile(
        rf"(\t\t[A-F0-9]+ /\* {re.escape(target_name)} \*/ = \{{\n"
        rf"\t\t\tisa = PBXNativeTarget;[\s\S]*?"
        rf"\t\t\tbuildPhases = \(\n)"
        rf"([\s\S]*?)"
        rf"(\t\t\t\);)"
    )
    match = target_pattern.search(content)
    if match is None:
        raise RuntimeError(f"Could not find PBXNativeTarget {target_name!r}")
    return match


def resources_phase_uuids(content: str) -> set[str]:
    start = content.find(RESOURCES_SECTION_BEGIN)
    end = content.find(RESOURCES_SECTION_END)
    if start == -1 or end == -1:
        return set()
    return set(
        re.findall(
            r"^\t\t([A-F0-9]+) /\* [^*]* \*/ = \{\n\t\t\tisa = PBXResourcesBuildPhase;",
            content[start:end],
            flags=re.MULTILINE,
        )
    )


def build_file_entries(build_files: dict[str, tuple[str, str]]) -> str:
    entries: list[str] = []
    for resource_key, (build_uuid, label) in build_files.items():
        file_uuid, file_label, _, _ = FILE_REFS[resource_key]
        entries.append(
            f"\t\t{build_uuid} /* {label} */ = "
            f"{{isa = PBXBuildFile; fileRef = {file_uuid} /* {file_label} */; }};\n"
        )
    return "".join(entries)


def phase_file_entries(build_files: dict[str, tuple[str, str]]) -> list[tuple[str, str]]:
    return [
        (build_uuid, f"\t\t\t\t{build_uuid} /* {label} */,\n")
        for build_uuid, label in build_files.values()
    ]


def resources_phase(phase_uuid: str, build_files: dict[str, tuple[str, str]]) -> str:
    entries = "".join(entry for _, entry in phase_file_entries(build_files))
    return (
        f"\t\t{phase_uuid} /* Resources */ = {{\n"
        "\t\t\tisa = PBXResourcesBuildPhase;\n"
        "\t\t\tbuildActionMask = 2147483647;\n"
        "\t\t\tfiles = (\n"
        f"{entries}"
        "\t\t\t);\n"
        "\t\t\trunOnlyForDeploymentPostprocessing = 0;\n"
        "\t\t};\n"
    )


def add_files_to_phase(
    content: str, phase_uuid: str, build_files: dict[str, tuple[str, str]]
) -> str:
    phase_pattern = re.compile(
        rf"(\t\t{phase_uuid} /\* [^*]* \*/ = \{{\n"
        rf"\t\t\tisa = PBXResourcesBuildPhase;\n"
        rf"[\s\S]*?"
        rf"\t\t\tfiles = \(\n)"
        rf"([\s\S]*?)"
        rf"(\t\t\t\);)"
    )
    match = phase_pattern.search(content)
    if match is None:
        raise RuntimeError(f"Could not find PBXResourcesBuildPhase {phase_uuid}")
    existing = match.group(2)
    missing = "".join(
        entry for build_uuid, entry in phase_file_entries(build_files) if build_uuid not in existing
    )
    if not missing:
        return content
    return content[: match.end(2)] + missing + content[match.end(2) :]


def add_resources_to_target(
    content: str,
    target_name: str,
    fallback_phase_uuid: str,
    build_files: dict[str, tuple[str, str]],
) -> str:
    phase_list = target_build_phases(content, target_name).group(2)
    target_phases = re.findall(r"^\t\t\t\t([A-F0-9]+) /\*", phase_list, flags=re.MULTILINE)
    resource_phases = [uuid for uuid in target_phases if uuid in resources_phase_uuids(content)]
    if len(resource_phases) > 1:
        raise RuntimeError(
            f"{target_name} has {len(resource_phases)} resource phases; expected at most one"
        )
    if resource_phases:
        return add_files_to_phase(content, resource_phases[0], build_files)

    phase = resources_phase(fallback_phase_uuid, build_files)
    if RESOURCES_SECTION_END in content:
        content = insert_before_marker(content, RESOURCES_SECTION_END, phase, fallback_phase_uuid)
    else:
        content = insert_before_marker(
            content,
            "/* Begin PBXSourcesBuildPhase section */",
            f"{RESOURCES_SECTION_BEGIN}\n{phase}{RESOURCES_SECTION_END}\n\n",
            fallback_phase_uuid,
        )

    match = target_build_phases(content, target_name)
    insertion = f"\t\t\t\t{fallback_phase_uuid} /* Resources */,\n"
    return content[: match.end(2)] + insertion + content[match.end(2) :]


content = PBXPROJ.read_text()

file_reference_entries = "".join(
    (
        f"\t\t{file_uuid} /* {label} */ = "
        f'{{isa = PBXFileReference; lastKnownFileType = {file_type}; '
        f'name = "{label}"; path = "{path}"; sourceTree = "<group>"; }};\n'
    )
    for file_uuid, label, file_type, path in FILE_REFS.values()
)
content = insert_before_marker(
    content,
    "/* End PBXFileReference section */",
    file_reference_entries,
    FILE_REFS["plinx_strings"][0],
)

all_build_entries = build_file_entries(IOS_BUILD_FILES) + build_file_entries(TVOS_BUILD_FILES)
content = insert_before_marker(
    content,
    "/* End PBXBuildFile section */",
    all_build_entries,
    IOS_BUILD_FILES["plinx_strings"][0],
)

content = add_resources_to_target(content, "Plinx-iOS", IOS_RESOURCES_PHASE, IOS_BUILD_FILES)
content = add_resources_to_target(content, "Plinx-tvOS", TVOS_RESOURCES_PHASE, TVOS_BUILD_FILES)

PBXPROJ.write_text(content)
print("Patched pbxproj — added app resources to each target's own resource phase.")
