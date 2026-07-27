#!/usr/bin/env python3
"""Add deterministic, target-owned resource phases to the generated project.

XcodeGen currently omits these resources for Plinx's sibling-source layout.
Each app target must own a distinct PBXResourcesBuildPhase and distinct
PBXBuildFile objects. Sharing either object between iOS and tvOS can cause
Xcode's build system to copy resources into only one product.

Safe to re-run: all inserted identifiers are deterministic and idempotent.
"""

from pathlib import Path
import re


ROOT_DIR = Path(__file__).resolve().parent.parent
PBXPROJ = ROOT_DIR / "PlinxApp/Plinx.xcodeproj/project.pbxproj"

FILE_REFS = {
    "plinx_strings": ("F10000000000000000000001", "Plinx.strings", "text.plist.strings", "Resources/en.lproj/Plinx.strings"),
    "local_strings": ("F10000000000000000000002", "Localizable.xcstrings", "text.json.xcstrings", "../../strimr/Localizable.xcstrings"),
    "assets": ("F10000000000000000000003", "Assets.xcassets", "folder.assetcatalog", "Resources/Assets.xcassets"),
    "launch": ("F10000000000000000000004", "LaunchScreen.storyboard", "file.storyboard", "Resources/LaunchScreen.storyboard"),
    "privacy": ("F10000000000000000000005", "PrivacyInfo.xcprivacy", "text.xml", "Resources/PrivacyInfo.xcprivacy"),
}

IOS_BUILD_FILES = {
    "plinx_strings": ("F10000000000000000000011", "Plinx.strings in Resources"),
    "local_strings": ("F10000000000000000000012", "Localizable.xcstrings in Resources"),
    "assets": ("F10000000000000000000013", "Assets.xcassets in Resources"),
    "launch": ("F10000000000000000000014", "LaunchScreen.storyboard in Resources"),
    "privacy": ("F10000000000000000000015", "PrivacyInfo.xcprivacy in Resources"),
}

TVOS_BUILD_FILES = {
    "plinx_strings": ("F10000000000000000000021", "Plinx.strings in Resources"),
    "local_strings": ("F10000000000000000000022", "Localizable.xcstrings in Resources"),
    "assets": ("F10000000000000000000023", "Assets.xcassets in Resources"),
    "privacy": ("F10000000000000000000025", "PrivacyInfo.xcprivacy in Resources"),
}

IOS_RESOURCES_PHASE = "F10000000000000000000031"
TVOS_RESOURCES_PHASE = "F10000000000000000000032"


def insert_before_marker(content: str, marker: str, snippet: str, unique_token: str) -> str:
    if unique_token in content:
        return content
    if marker not in content:
        raise RuntimeError(f"Could not find project marker: {marker}")
    return content.replace(marker, snippet + marker, 1)


def add_phase_to_target(content: str, target_name: str, phase_uuid: str) -> str:
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
    if phase_uuid in match.group(2):
        return content

    insertion = f"\t\t\t\t{phase_uuid} /* Resources */,\n"
    return content[: match.start(2)] + insertion + match.group(2) + content[match.end(2) :]


def build_file_entries(build_files: dict[str, tuple[str, str]]) -> str:
    entries: list[str] = []
    for resource_key, (build_uuid, label) in build_files.items():
        file_uuid, file_label, _, _ = FILE_REFS[resource_key]
        entries.append(
            f"\t\t{build_uuid} /* {label} */ = "
            f"{{isa = PBXBuildFile; fileRef = {file_uuid} /* {file_label} */; }};\n"
        )
    return "".join(entries)


def resources_phase(phase_uuid: str, build_files: dict[str, tuple[str, str]]) -> str:
    entries = "".join(
        f"\t\t\t\t{build_uuid} /* {label} */,\n"
        for build_uuid, label in build_files.values()
    )
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

phase_entries = resources_phase(IOS_RESOURCES_PHASE, IOS_BUILD_FILES) + resources_phase(
    TVOS_RESOURCES_PHASE, TVOS_BUILD_FILES
)
content = insert_before_marker(
    content,
    "/* End PBXResourcesBuildPhase section */",
    phase_entries,
    IOS_RESOURCES_PHASE,
)

content = add_phase_to_target(content, "Plinx-iOS", IOS_RESOURCES_PHASE)
content = add_phase_to_target(content, "Plinx-tvOS", TVOS_RESOURCES_PHASE)

PBXPROJ.write_text(content)
print("Patched pbxproj — added distinct iOS/tvOS resource phases.")
