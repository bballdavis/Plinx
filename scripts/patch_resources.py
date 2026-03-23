#!/usr/bin/env python3
"""
Patches the Xcode pbxproj to add a PBXResourcesBuildPhase containing
required app resources that can be dropped by generation.

Re-run safe: all inserts are idempotent.
"""
import re, os

# Get path to pbxproj relative to the script's directory (script is in scripts/patch_resources.py)
script_dir = os.path.dirname(os.path.abspath(__file__))
root_dir = os.path.dirname(script_dir)
pbxproj = os.path.join(root_dir, 'PlinxApp/Plinx.xcodeproj/project.pbxproj')

# Fixed UUIDs (deterministic, safe to re-run)
UUID_PLINX_STRINGS_REF   = 'AA10000000000001PLINXSTR'
UUID_LOCAL_STRINGS_REF   = 'AA10000000000002LOCALSTR'
UUID_PLINX_STRINGS_BUILD = 'AA10000000000003PLINXBLD'
UUID_LOCAL_STRINGS_BUILD = 'AA10000000000004LOCALBLD'
UUID_RESOURCES_PHASE     = 'AA10000000000005RESPHASE'
UUID_ASSETS_REF          = 'AA10000000000006ASSETREF'
UUID_ASSETS_BUILD        = 'AA10000000000007ASSETBLD'
UUID_LAUNCH_REF          = 'AA10000000000008LNCHREF'
UUID_LAUNCH_BUILD        = 'AA10000000000009LNCHBLD'
UUID_PRIVACY_REF         = 'AA10000000000010PRIVREF'
UUID_PRIVACY_BUILD       = 'AA10000000000011PRIVBLD'

with open(pbxproj) as f:
    content = f.read()

content = content.replace(
    '../vendor/strimr/Localizable.xcstrings',
    '../../strimr/Localizable.xcstrings',
)

def ensure_before_marker(text: str, marker: str, snippet: str, unique_token: str) -> str:
    if unique_token in text:
        return text
    return text.replace(marker, snippet + marker)

def ensure_in_resources_phase(text: str, build_uuid: str, label: str) -> str:
    if re.search(
        rf'{UUID_RESOURCES_PHASE} /\* Resources \*/ = \{{[\s\S]*?{build_uuid} /\* {re.escape(label)} \*/',
        text,
    ):
        return text
    return re.sub(
        rf'({UUID_RESOURCES_PHASE} /\* Resources \*/ = \{{[\s\S]*?files = \(\n)',
        rf'\1\t\t\t\t{build_uuid} /* {label} */,\n',
        text,
        count=1,
    )

# 1. PBXFileReference entries
content = ensure_before_marker(
    content,
    '/* End PBXFileReference section */',
    (
        f'\n\t\t{UUID_PLINX_STRINGS_REF} /* Plinx.strings */ = '
        f'{{isa = PBXFileReference; lastKnownFileType = text.plist.strings; '
        f'name = Plinx.strings; path = "Resources/en.lproj/Plinx.strings"; sourceTree = "<group>"; }};\n'
    ),
    UUID_PLINX_STRINGS_REF,
)
content = ensure_before_marker(
    content,
    '/* End PBXFileReference section */',
    (
        f'\t\t{UUID_LOCAL_STRINGS_REF} /* Localizable.xcstrings */ = '
        f'{{isa = PBXFileReference; lastKnownFileType = text.json.xcstrings; '
        f'name = Localizable.xcstrings; path = "../../strimr/Localizable.xcstrings"; sourceTree = "<group>"; }};\n'
    ),
    UUID_LOCAL_STRINGS_REF,
)
content = ensure_before_marker(
    content,
    '/* End PBXFileReference section */',
    (
        f'\t\t{UUID_ASSETS_REF} /* Assets.xcassets */ = '
        f'{{isa = PBXFileReference; lastKnownFileType = folder.assetcatalog; '
        f'name = Assets.xcassets; path = Resources/Assets.xcassets; sourceTree = "<group>"; }};\n'
    ),
    UUID_ASSETS_REF,
)
content = ensure_before_marker(
    content,
    '/* End PBXFileReference section */',
    (
        f'\t\t{UUID_LAUNCH_REF} /* LaunchScreen.storyboard */ = '
        f'{{isa = PBXFileReference; lastKnownFileType = file.storyboard; '
        f'name = LaunchScreen.storyboard; path = Resources/LaunchScreen.storyboard; sourceTree = "<group>"; }};\n'
    ),
    UUID_LAUNCH_REF,
)
content = ensure_before_marker(
    content,
    '/* End PBXFileReference section */',
    (
        f'\t\t{UUID_PRIVACY_REF} /* PrivacyInfo.xcprivacy */ = '
        f'{{isa = PBXFileReference; lastKnownFileType = text.xml; '
        f'name = PrivacyInfo.xcprivacy; path = Resources/PrivacyInfo.xcprivacy; sourceTree = "<group>"; }};\n'
    ),
    UUID_PRIVACY_REF,
)

# 2. PBXBuildFile entries
content = ensure_before_marker(
    content,
    '/* End PBXBuildFile section */',
    (
        f'\n\t\t{UUID_PLINX_STRINGS_BUILD} /* Plinx.strings in Resources */ = '
        f'{{isa = PBXBuildFile; fileRef = {UUID_PLINX_STRINGS_REF} /* Plinx.strings */; }};\n'
    ),
    UUID_PLINX_STRINGS_BUILD,
)
content = ensure_before_marker(
    content,
    '/* End PBXBuildFile section */',
    (
        f'\t\t{UUID_LOCAL_STRINGS_BUILD} /* Localizable.xcstrings in Resources */ = '
        f'{{isa = PBXBuildFile; fileRef = {UUID_LOCAL_STRINGS_REF} /* Localizable.xcstrings */; }};\n'
    ),
    UUID_LOCAL_STRINGS_BUILD,
)
content = ensure_before_marker(
    content,
    '/* End PBXBuildFile section */',
    (
        f'\t\t{UUID_ASSETS_BUILD} /* Assets.xcassets in Resources */ = '
        f'{{isa = PBXBuildFile; fileRef = {UUID_ASSETS_REF} /* Assets.xcassets */; }};\n'
    ),
    UUID_ASSETS_BUILD,
)
content = ensure_before_marker(
    content,
    '/* End PBXBuildFile section */',
    (
        f'\t\t{UUID_LAUNCH_BUILD} /* LaunchScreen.storyboard in Resources */ = '
        f'{{isa = PBXBuildFile; fileRef = {UUID_LAUNCH_REF} /* LaunchScreen.storyboard */; }};\n'
    ),
    UUID_LAUNCH_BUILD,
)
content = ensure_before_marker(
    content,
    '/* End PBXBuildFile section */',
    (
        f'\t\t{UUID_PRIVACY_BUILD} /* PrivacyInfo.xcprivacy in Resources */ = '
        f'{{isa = PBXBuildFile; fileRef = {UUID_PRIVACY_REF} /* PrivacyInfo.xcprivacy */; }};\n'
    ),
    UUID_PRIVACY_BUILD,
)

# 3. PBXResourcesBuildPhase section
if UUID_RESOURCES_PHASE not in content:
    resources_phase = (
        '/* Begin PBXResourcesBuildPhase section */\n'
        f'\t\t{UUID_RESOURCES_PHASE} /* Resources */ = {{\n'
        '\t\t\tisa = PBXResourcesBuildPhase;\n'
        '\t\t\tbuildActionMask = 2147483647;\n'
        '\t\t\tfiles = (\n'
        f'\t\t\t\t{UUID_ASSETS_BUILD} /* Assets.xcassets in Resources */,\n'
        f'\t\t\t\t{UUID_LAUNCH_BUILD} /* LaunchScreen.storyboard in Resources */,\n'
        f'\t\t\t\t{UUID_PRIVACY_BUILD} /* PrivacyInfo.xcprivacy in Resources */,\n'
        f'\t\t\t\t{UUID_PLINX_STRINGS_BUILD} /* Plinx.strings in Resources */,\n'
        f'\t\t\t\t{UUID_LOCAL_STRINGS_BUILD} /* Localizable.xcstrings in Resources */,\n'
        '\t\t\t);\n'
        '\t\t\trunOnlyForDeploymentPostprocessing = 0;\n'
        '\t\t};\n'
        '/* End PBXResourcesBuildPhase section */\n\n'
    )
    content = content.replace('/* Begin PBXSourcesBuildPhase section */',
                              resources_phase + '/* Begin PBXSourcesBuildPhase section */')
else:
    content = ensure_in_resources_phase(content, UUID_ASSETS_BUILD, 'Assets.xcassets in Resources')
    content = ensure_in_resources_phase(content, UUID_LAUNCH_BUILD, 'LaunchScreen.storyboard in Resources')
    content = ensure_in_resources_phase(content, UUID_PRIVACY_BUILD, 'PrivacyInfo.xcprivacy in Resources')
    content = ensure_in_resources_phase(content, UUID_PLINX_STRINGS_BUILD, 'Plinx.strings in Resources')
    content = ensure_in_resources_phase(content, UUID_LOCAL_STRINGS_BUILD, 'Localizable.xcstrings in Resources')

# 4. Add resource phase to target's buildPhases before Sources
if UUID_RESOURCES_PHASE not in re.search(r'buildPhases = \([\s\S]*?\);', content).group(0):
    content = re.sub(
        r'(buildPhases = \(\n\t+)(\w+ /\* Sources \*/,)',
        lambda m: m.group(1) + UUID_RESOURCES_PHASE + ' /* Resources */,\n\t\t\t\t' + m.group(2),
        content,
        count=1,
    )

with open(pbxproj, 'w') as f:
    f.write(content)

print("Patched pbxproj — ensured app resources include assets, launch storyboard, privacy manifest, and localized strings")
