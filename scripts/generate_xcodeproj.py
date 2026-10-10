#!/usr/bin/env python3
"""Generate SoundGuard.xcodeproj/project.pbxproj for Xcode 15."""

from __future__ import annotations

import hashlib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
APP_DIR = ROOT / "SoundGuard"
TEST_DIR = ROOT / "SoundGuardTests"
PROJ = ROOT / "SoundGuard.xcodeproj"
SCHEME_DIR = PROJ / "xcshareddata" / "xcschemes"


def xid(name: str) -> str:
    return hashlib.md5(name.encode()).hexdigest()[:24].upper()


def rel(path: Path) -> str:
    return path.relative_to(ROOT).as_posix()


def collect(dir_path: Path, suffix: str) -> list[Path]:
    return sorted(p for p in dir_path.rglob(f"*{suffix}") if p.is_file())


app_sources = collect(APP_DIR, ".swift")
test_sources = collect(TEST_DIR, ".swift")
resources = [
    APP_DIR / "Assets.xcassets",
    APP_DIR / "PrivacyInfo.xcprivacy",
    APP_DIR / "Resources" / "alarm_loop.wav",
]

ids = {
    "project": xid("project"),
    "app_target": xid("app_target"),
    "test_target": xid("test_target"),
    "app_sources_phase": xid("app_sources_phase"),
    "test_sources_phase": xid("test_sources_phase"),
    "app_resources_phase": xid("app_resources_phase"),
    "test_resources_phase": xid("test_resources_phase"),
    "app_frameworks": xid("app_frameworks"),
    "test_frameworks": xid("test_frameworks"),
    "app_config_list": xid("app_config_list"),
    "test_config_list": xid("test_config_list"),
    "project_config_list": xid("project_config_list"),
    "app_debug": xid("app_debug"),
    "app_release": xid("app_release"),
    "test_debug": xid("test_debug"),
    "test_release": xid("test_release"),
    "proj_debug": xid("proj_debug"),
    "proj_release": xid("proj_release"),
    "root_group": xid("root_group"),
    "app_group": xid("app_group"),
    "test_group": xid("test_group"),
    "products_group": xid("products_group"),
    "app_product": xid("app_product"),
    "test_product": xid("test_product"),
    "container_proxy": xid("container_proxy"),
    "target_dep": xid("target_dep"),
}

file_refs: dict[Path, str] = {}
build_files: dict[Path, str] = {}

for path in app_sources + test_sources + resources:
    file_refs[path] = xid(f"ref:{rel(path)}")
    build_files[path] = xid(f"build:{rel(path)}")


def file_ref_entry(path: Path) -> str:
    name = path.name
    extra = ""
    if path.suffix == ".swift":
        extra = " lastKnownFileType = sourcecode.swift;"
    elif path.suffix == ".wav":
        extra = " lastKnownFileType = audio.wav;"
    elif path.suffix == ".xcprivacy":
        extra = " lastKnownFileType = text.xml;"
    elif path.suffix == ".xcassets":
        extra = " lastKnownFileType = folder.assetcatalog;"
    source_tree = "        "
    return (
        f"\t\t{file_refs[path]} /* {name} */ = {{isa = PBXFileReference;{extra} path = {name}; sourceTree = \"<group>\"; }};"
    )


def group_children(paths: list[Path]) -> str:
    lines = []
    for path in paths:
        lines.append(f"\t\t\t\t{file_refs[path]} /* {path.name} */,")
    return "\n".join(lines)


# Nested groups by folder for the app target, flattened is easier and valid.
app_group_children = "\n".join(
    f"\t\t\t\t{file_refs[p]} /* {p.name} */," for p in app_sources + resources
)
# Info.plist is referenced via INFOPLIST_FILE; add a file ref so Xcode shows it.
info_plist = APP_DIR / "Info.plist"
info_id = xid("ref:SoundGuard/Info.plist")

test_group_children = "\n".join(
    f"\t\t\t\t{file_refs[p]} /* {p.name} */," for p in test_sources
)

app_build_sources = "\n".join(
    f"\t\t\t\t{build_files[p]} /* {p.name} in Sources */," for p in app_sources
)
test_build_sources = "\n".join(
    f"\t\t\t\t{build_files[p]} /* {p.name} in Sources */," for p in test_sources
)
app_build_resources = "\n".join(
    f"\t\t\t\t{build_files[p]} /* {p.name} in Resources */," for p in resources
)

pbx_build_file = []
for path in app_sources:
    pbx_build_file.append(
        f"\t\t{build_files[path]} /* {path.name} in Sources */ = {{isa = PBXBuildFile; fileRef = {file_refs[path]} /* {path.name} */; }};"
    )
for path in test_sources:
    pbx_build_file.append(
        f"\t\t{build_files[path]} /* {path.name} in Sources */ = {{isa = PBXBuildFile; fileRef = {file_refs[path]} /* {path.name} */; }};"
    )
for path in resources:
    pbx_build_file.append(
        f"\t\t{build_files[path]} /* {path.name} in Resources */ = {{isa = PBXBuildFile; fileRef = {file_refs[path]} /* {path.name} */; }};"
    )

pbx_file_ref = [file_ref_entry(p) for p in app_sources + test_sources + resources]
pbx_file_ref.append(
    f"\t\t{ids['app_product']} /* SoundGuard.app */ = {{isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = SoundGuard.app; sourceTree = BUILT_PRODUCTS_DIR; }};"
)
pbx_file_ref.append(
    f"\t\t{ids['test_product']} /* SoundGuardTests.xctest */ = {{isa = PBXFileReference; explicitFileType = wrapper.cfbundle; includeInIndex = 0; path = SoundGuardTests.xctest; sourceTree = BUILT_PRODUCTS_DIR; }};"
)
pbx_file_ref.append(
    f"\t\t{info_id} /* Info.plist */ = {{isa = PBXFileReference; lastKnownFileType = text.plist.xml; path = Info.plist; sourceTree = \"<group>\"; }};"
)

# Nested groups so files keep their folder paths.
# Using names-only in a flat group would break because several folders are dropped.
# Instead create groups matching the directory tree.


def build_tree(base: Path, files: list[Path], group_id: str, extra_refs: list[str] | None = None) -> tuple[str, list[str]]:
    """Return (group_id usage already known) and extra group object strings."""
    objects: list[str] = []

    def group_for(dir_path: Path) -> str:
        if dir_path == base:
            return group_id
        return xid(f"group:{rel(dir_path)}")

    dirs = {base}
    for f in files:
        for parent in f.relative_to(base).parents:
            dirs.add(base / parent)

    for directory in sorted(dirs, key=lambda p: rel(p)):
        gid = group_for(directory)
        child_dirs = sorted(
            [d for d in dirs if d.parent == directory and d != directory],
            key=lambda p: p.name,
        )
        child_files = sorted([f for f in files if f.parent == directory], key=lambda p: p.name)
        children = []
        if extra_refs and directory == base:
            children.extend(extra_refs)
        for d in child_dirs:
            children.append(f"\t\t\t\t{group_for(d)} /* {d.name} */,")
        for f in child_files:
            children.append(f"\t\t\t\t{file_refs[f]} /* {f.name} */,")
        name = directory.name
        objects.append(
            "\n".join(
                [
                    f"\t\t{gid} /* {name} */ = {{",
                    "\t\t\tisa = PBXGroup;",
                    "\t\t\tchildren = (",
                    "\n".join(children),
                    "\t\t\t);",
                    f"\t\t\tpath = {name};",
                    '\t\t\tsourceTree = "<group>";',
                    "\t\t};",
                ]
            )
        )
    return group_id, objects


app_extra = [
    f"\t\t\t\t{info_id} /* Info.plist */,",
]
_, app_groups = build_tree(APP_DIR, app_sources + resources, ids["app_group"], app_extra)
_, test_groups = build_tree(TEST_DIR, test_sources, ids["test_group"])

# File refs must use path relative to their group, which is the filename. Good.

COMMON_PROJECT = r"""
CLANG_ANALYZER_NONNULL = YES;
				CLANG_ANALYZER_NUMBER_OBJECT_CONVERSION = YES_AGGRESSIVE;
				CLANG_CXX_LANGUAGE_STANDARD = "gnu++20";
				CLANG_ENABLE_MODULES = YES;
				CLANG_ENABLE_OBJC_ARC = YES;
				CLANG_ENABLE_OBJC_WEAK = YES;
				COPY_PHASE_STRIP = NO;
				DEBUG_INFORMATION_FORMAT = dwarf;
				ENABLE_STRICT_OBJC_MSGSEND = YES;
				ENABLE_TESTABILITY = YES;
				GCC_C_LANGUAGE_STANDARD = gnu17;
				GCC_DYNAMIC_NO_PIC = NO;
				GCC_NO_COMMON_BLOCKS = YES;
				GCC_OPTIMIZATION_LEVEL = 0;
				GCC_PREPROCESSOR_DEFINITIONS = (
					"DEBUG=1",
					"$(inherited)",
				);
				GCC_WARN_64_TO_32_BIT_CONVERSION = YES;
				GCC_WARN_ABOUT_RETURN_TYPE = YES_ERROR;
				GCC_WARN_UNDECLARED_SELECTOR = YES;
				GCC_WARN_UNINITIALIZED_AUTOS = YES_AGGRESSIVE;
				GCC_WARN_UNUSED_FUNCTION = YES;
				GCC_WARN_UNUSED_VARIABLE = YES;
				IPHONEOS_DEPLOYMENT_TARGET = 17.0;
				MTL_ENABLE_DEBUG_INFO = INCLUDE_SOURCE;
				ONLY_ACTIVE_ARCH = YES;
				SDKROOT = iphoneos;
				SWIFT_ACTIVE_COMPILATION_CONDITIONS = "DEBUG $(inherited)";
				SWIFT_OPTIMIZATION_LEVEL = "-Onone";
				SWIFT_VERSION = 5.0;
"""

COMMON_RELEASE = r"""
CLANG_ANALYZER_NONNULL = YES;
				CLANG_ANALYZER_NUMBER_OBJECT_CONVERSION = YES_AGGRESSIVE;
				CLANG_CXX_LANGUAGE_STANDARD = "gnu++20";
				CLANG_ENABLE_MODULES = YES;
				CLANG_ENABLE_OBJC_ARC = YES;
				CLANG_ENABLE_OBJC_WEAK = YES;
				COPY_PHASE_STRIP = NO;
				DEBUG_INFORMATION_FORMAT = "dwarf-with-dsym";
				ENABLE_NS_ASSERTIONS = NO;
				ENABLE_STRICT_OBJC_MSGSEND = YES;
				GCC_C_LANGUAGE_STANDARD = gnu17;
				GCC_NO_COMMON_BLOCKS = YES;
				GCC_WARN_64_TO_32_BIT_CONVERSION = YES;
				GCC_WARN_ABOUT_RETURN_TYPE = YES_ERROR;
				GCC_WARN_UNDECLARED_SELECTOR = YES;
				GCC_WARN_UNINITIALIZED_AUTOS = YES_AGGRESSIVE;
				GCC_WARN_UNUSED_FUNCTION = YES;
				GCC_WARN_UNUSED_VARIABLE = YES;
				IPHONEOS_DEPLOYMENT_TARGET = 17.0;
				MTL_ENABLE_DEBUG_INFO = NO;
				SDKROOT = iphoneos;
				SWIFT_COMPILATION_MODE = wholemodule;
				SWIFT_VERSION = 5.0;
				VALIDATE_PRODUCT = YES;
"""

APP_SETTINGS = """
ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;
				ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME = AccentColor;
				CODE_SIGN_STYLE = Automatic;
				CURRENT_PROJECT_VERSION = 1;
				DEVELOPMENT_ASSET_PATHS = "";
				ENABLE_PREVIEWS = YES;
				GENERATE_INFOPLIST_FILE = YES;
				INFOPLIST_FILE = SoundGuard/Info.plist;
				INFOPLIST_KEY_CFBundleDisplayName = SoundGuard;
				INFOPLIST_KEY_LSApplicationCategoryType = "public.app-category.utilities";
				INFOPLIST_KEY_UIApplicationSceneManifest_Generation = YES;
				INFOPLIST_KEY_UIApplicationSupportsIndirectInputEvents = YES;
				INFOPLIST_KEY_UIStatusBarStyle = UIStatusBarStyleLightContent;
				INFOPLIST_KEY_UISupportedInterfaceOrientations = UIInterfaceOrientationPortrait;
				LD_RUNPATH_SEARCH_PATHS = (
					"$(inherited)",
					"@executable_path/Frameworks",
				);
				MARKETING_VERSION = 1.0;
				PRODUCT_BUNDLE_IDENTIFIER = com.dropthemasquerade.SoundGuard;
				PRODUCT_NAME = "$(TARGET_NAME)";
				SUPPORTED_PLATFORMS = "iphoneos iphonesimulator";
				SUPPORTS_MACCATALYST = NO;
				SWIFT_EMIT_LOC_STRINGS = YES;
				SWIFT_STRICT_CONCURRENCY = targeted;
				SWIFT_VERSION = 5.0;
				TARGETED_DEVICE_FAMILY = 1;
"""

TEST_SETTINGS = """
BUNDLE_LOADER = "$(TEST_HOST)";
				CODE_SIGN_STYLE = Automatic;
				CURRENT_PROJECT_VERSION = 1;
				GENERATE_INFOPLIST_FILE = YES;
				IPHONEOS_DEPLOYMENT_TARGET = 17.0;
				MARKETING_VERSION = 1.0;
				PRODUCT_BUNDLE_IDENTIFIER = com.dropthemasquerade.SoundGuardTests;
				PRODUCT_NAME = "$(TARGET_NAME)";
				SUPPORTED_PLATFORMS = "iphoneos iphonesimulator";
				SWIFT_STRICT_CONCURRENCY = targeted;
				SWIFT_VERSION = 5.0;
				TARGETED_DEVICE_FAMILY = 1;
				TEST_HOST = "$(BUILT_PRODUCTS_DIR)/SoundGuard.app/$(BUNDLE_EXECUTABLE_FOLDER_PATH)/SoundGuard";
"""

pbxproj = f"""// !$*UTF8*$!
{{
	archiveVersion = 1;
	classes = {{
	}};
	objectVersion = 56;
	objects = {{

/* Begin PBXBuildFile section */
{chr(10).join(pbx_build_file)}
/* End PBXBuildFile section */

/* Begin PBXContainerItemProxy section */
		{ids['container_proxy']} /* PBXContainerItemProxy */ = {{
			isa = PBXContainerItemProxy;
			containerPortal = {ids['project']} /* Project object */;
			proxyType = 1;
			remoteGlobalIDString = {ids['app_target']};
			remoteInfo = SoundGuard;
		}};
/* End PBXContainerItemProxy section */

/* Begin PBXFileReference section */
{chr(10).join(pbx_file_ref)}
/* End PBXFileReference section */

/* Begin PBXFrameworksBuildPhase section */
		{ids['app_frameworks']} /* Frameworks */ = {{
			isa = PBXFrameworksBuildPhase;
			buildActionMask = 2147483647;
			files = (
			);
			runOnlyForDeploymentPostprocessing = 0;
		}};
		{ids['test_frameworks']} /* Frameworks */ = {{
			isa = PBXFrameworksBuildPhase;
			buildActionMask = 2147483647;
			files = (
			);
			runOnlyForDeploymentPostprocessing = 0;
		}};
/* End PBXFrameworksBuildPhase section */

/* Begin PBXGroup section */
		{ids['root_group']} = {{
			isa = PBXGroup;
			children = (
				{ids['app_group']} /* SoundGuard */,
				{ids['test_group']} /* SoundGuardTests */,
				{ids['products_group']} /* Products */,
			);
			sourceTree = "<group>";
		}};
		{ids['products_group']} /* Products */ = {{
			isa = PBXGroup;
			children = (
				{ids['app_product']} /* SoundGuard.app */,
				{ids['test_product']} /* SoundGuardTests.xctest */,
			);
			name = Products;
			sourceTree = "<group>";
		}};
{chr(10).join(app_groups)}
{chr(10).join(test_groups)}
/* End PBXGroup section */

/* Begin PBXNativeTarget section */
		{ids['app_target']} /* SoundGuard */ = {{
			isa = PBXNativeTarget;
			buildConfigurationList = {ids['app_config_list']} /* Build configuration list for PBXNativeTarget "SoundGuard" */;
			buildPhases = (
				{ids['app_sources_phase']} /* Sources */,
				{ids['app_frameworks']} /* Frameworks */,
				{ids['app_resources_phase']} /* Resources */,
			);
			buildRules = (
			);
			dependencies = (
			);
			name = SoundGuard;
			productName = SoundGuard;
			productReference = {ids['app_product']} /* SoundGuard.app */;
			productType = "com.apple.product-type.application";
		}};
		{ids['test_target']} /* SoundGuardTests */ = {{
			isa = PBXNativeTarget;
			buildConfigurationList = {ids['test_config_list']} /* Build configuration list for PBXNativeTarget "SoundGuardTests" */;
			buildPhases = (
				{ids['test_sources_phase']} /* Sources */,
				{ids['test_frameworks']} /* Frameworks */,
				{ids['test_resources_phase']} /* Resources */,
			);
			buildRules = (
			);
			dependencies = (
				{ids['target_dep']} /* PBXTargetDependency */,
			);
			name = SoundGuardTests;
			productName = SoundGuardTests;
			productReference = {ids['test_product']} /* SoundGuardTests.xctest */;
			productType = "com.apple.product-type.bundle.unit-test";
		}};
/* End PBXNativeTarget section */

/* Begin PBXProject section */
		{ids['project']} /* Project object */ = {{
			isa = PBXProject;
			attributes = {{
				BuildIndependentTargetsInParallel = 1;
				LastSwiftUpdateCheck = 1520;
				LastUpgradeCheck = 1520;
				TargetAttributes = {{
					{ids['app_target']} = {{
						CreatedOnToolsVersion = 15.2;
					}};
					{ids['test_target']} = {{
						CreatedOnToolsVersion = 15.2;
						TestTargetID = {ids['app_target']};
					}};
				}};
			}};
			buildConfigurationList = {ids['project_config_list']} /* Build configuration list for PBXProject "SoundGuard" */;
			compatibilityVersion = "Xcode 14.0";
			developmentRegion = en;
			hasScannedForEncodings = 0;
			knownRegions = (
				en,
				Base,
			);
			mainGroup = {ids['root_group']};
			productRefGroup = {ids['products_group']} /* Products */;
			projectDirPath = "";
			projectRoot = "";
			targets = (
				{ids['app_target']} /* SoundGuard */,
				{ids['test_target']} /* SoundGuardTests */,
			);
		}};
/* End PBXProject section */

/* Begin PBXResourcesBuildPhase section */
		{ids['app_resources_phase']} /* Resources */ = {{
			isa = PBXResourcesBuildPhase;
			buildActionMask = 2147483647;
			files = (
{app_build_resources}
			);
			runOnlyForDeploymentPostprocessing = 0;
		}};
		{ids['test_resources_phase']} /* Resources */ = {{
			isa = PBXResourcesBuildPhase;
			buildActionMask = 2147483647;
			files = (
			);
			runOnlyForDeploymentPostprocessing = 0;
		}};
/* End PBXResourcesBuildPhase section */

/* Begin PBXSourcesBuildPhase section */
		{ids['app_sources_phase']} /* Sources */ = {{
			isa = PBXSourcesBuildPhase;
			buildActionMask = 2147483647;
			files = (
{app_build_sources}
			);
			runOnlyForDeploymentPostprocessing = 0;
		}};
		{ids['test_sources_phase']} /* Sources */ = {{
			isa = PBXSourcesBuildPhase;
			buildActionMask = 2147483647;
			files = (
{test_build_sources}
			);
			runOnlyForDeploymentPostprocessing = 0;
		}};
/* End PBXSourcesBuildPhase section */

/* Begin PBXTargetDependency section */
		{ids['target_dep']} /* PBXTargetDependency */ = {{
			isa = PBXTargetDependency;
			target = {ids['app_target']} /* SoundGuard */;
			targetProxy = {ids['container_proxy']} /* PBXContainerItemProxy */;
		}};
/* End PBXTargetDependency section */

/* Begin XCBuildConfiguration section */
		{ids['proj_debug']} /* Debug */ = {{
			isa = XCBuildConfiguration;
			buildSettings = {{
				ALWAYS_SEARCH_USER_PATHS = NO;
				{COMMON_PROJECT.strip()}
			}};
			name = Debug;
		}};
		{ids['proj_release']} /* Release */ = {{
			isa = XCBuildConfiguration;
			buildSettings = {{
				ALWAYS_SEARCH_USER_PATHS = NO;
				{COMMON_RELEASE.strip()}
			}};
			name = Release;
		}};
		{ids['app_debug']} /* Debug */ = {{
			isa = XCBuildConfiguration;
			buildSettings = {{
				{APP_SETTINGS.strip()}
			}};
			name = Debug;
		}};
		{ids['app_release']} /* Release */ = {{
			isa = XCBuildConfiguration;
			buildSettings = {{
				{APP_SETTINGS.strip()}
			}};
			name = Release;
		}};
		{ids['test_debug']} /* Debug */ = {{
			isa = XCBuildConfiguration;
			buildSettings = {{
				{TEST_SETTINGS.strip()}
			}};
			name = Debug;
		}};
		{ids['test_release']} /* Release */ = {{
			isa = XCBuildConfiguration;
			buildSettings = {{
				{TEST_SETTINGS.strip()}
			}};
			name = Release;
		}};
/* End XCBuildConfiguration section */

/* Begin XCConfigurationList section */
		{ids['project_config_list']} /* Build configuration list for PBXProject "SoundGuard" */ = {{
			isa = XCConfigurationList;
			buildConfigurations = (
				{ids['proj_debug']} /* Debug */,
				{ids['proj_release']} /* Release */,
			);
			defaultConfigurationIsVisible = 0;
			defaultConfigurationName = Release;
		}};
		{ids['app_config_list']} /* Build configuration list for PBXNativeTarget "SoundGuard" */ = {{
			isa = XCConfigurationList;
			buildConfigurations = (
				{ids['app_debug']} /* Debug */,
				{ids['app_release']} /* Release */,
			);
 mar			defaultConfigurationIsVisible = 0;
			defaultConfigurationName = Release;
		}};
		{ids['test_config_list']} /* Build configuration list for PBXNativeTarget "SoundGuardTests" */ = {{
			isa = XCConfigurationList;
			buildConfigurations = (
				{ids['test_debug']} /* Debug */,
				{ids['test_release']} /* Release */,
			);
			defaultConfigurationIsVisible = 0;
			defaultConfigurationName = Release;
		}};
/* End XCConfigurationList section */
	}};
	rootObject = {ids['project']} /* Project object */;
}}
"""

# Fix accidental typo
pbxproj = pbxproj.replace(" mar\t\t\tdefaultConfigurationIsVisible", "\t\t\tdefaultConfigurationIsVisible")

PROJ.mkdir(parents=True, exist_ok=True)
(PROJ / "project.pbxproj").write_text(pbxproj)
print("wrote", PROJ / "project.pbxproj")
print("app sources", len(app_sources))
print("test sources", len(test_sources))

SCHEME_DIR.mkdir(parents=True, exist_ok=True)
scheme = f"""<?xml version="1.0" encoding="UTF-8"?>
<Scheme
   LastUpgradeVersion = "1520"
   version = "1.7">
   <BuildAction
      parallelizeBuildables = "YES"
      buildImplicitDependencies = "YES">
      <BuildActionEntries>
         <BuildActionEntry
            buildForTesting = "YES"
            buildForRunning = "YES"
            buildForProfiling = "YES"
            buildForArchiving = "YES"
            buildForAnalyzing = "YES">
            <BuildableReference
               BuildableIdentifier = "primary"
               BlueprintIdentifier = "{ids['app_target']}"
               BuildableName = "SoundGuard.app"
               BlueprintName = "SoundGuard"
               ReferencedContainer = "container:SoundGuard.xcodeproj">
            </BuildableReference>
         </BuildActionEntry>
      </BuildActionEntries>
   </BuildAction>
   <TestAction
      buildConfiguration = "Debug"
      selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB"
      selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB"
      shouldUseLaunchSchemeArgsEnv = "YES"
      shouldAutocreateTestPlan = "YES">
      <Testables>
         <TestableReference
            skipped = "NO"
            parallelizable = "YES">
            <BuildableReference
               BuildableIdentifier = "primary"
               BlueprintIdentifier = "{ids['test_target']}"
               BuildableName = "SoundGuardTests.xctest"
               BlueprintName = "SoundGuardTests"
               ReferencedContainer = "container:SoundGuard.xcodeproj">
            </BuildableReference>
         </TestableReference>
      </Testables>
   </TestAction>
   <LaunchAction
      buildConfiguration = "Debug"
      selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB"
      selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB"
      launchStyle = "0"
      useCustomWorkingDirectory = "NO"
      ignoresPersistentStateOnLaunch = "NO"
      debugDocumentVersioning = "YES"
      debugServiceExtension = "internal"
      allowLocationSimulation = "YES">
      <BuildableProductRunnable
         runnableDebuggingMode = "0">
         <BuildableReference
            BuildableIdentifier = "primary"
            BlueprintIdentifier = "{ids['app_target']}"
            BuildableName = "SoundGuard.app"
            BlueprintName = "SoundGuard"
            ReferencedContainer = "container:SoundGuard.xcodeproj">
         </BuildableReference>
      </BuildableProductRunnable>
   </LaunchAction>
   <ProfileAction
      buildConfiguration = "Release"
      shouldUseLaunchSchemeArgsEnv = "YES"
      savedToolIdentifier = ""
      useCustomWorkingDirectory = "NO"
      debugDocumentVersioning = "YES">
      <BuildableProductRunnable
         runnableDebuggingMode = "0">
         <BuildableReference
            BuildableIdentifier = "primary"
            BlueprintIdentifier = "{ids['app_target']}"
            BuildableName = "SoundGuard.app"
            BlueprintName = "SoundGuard"
            ReferencedContainer = "container:SoundGuard.xcodeproj">
         </BuildableReference>
      </BuildableProductRunnable>
   </ProfileAction>
   <AnalyzeAction
      buildConfiguration = "Debug">
   </AnalyzeAction>
   <ArchiveAction
      buildConfiguration = "Release"
      revealArchiveInOrganizer = "YES">
   </ArchiveAction>
</Scheme>
"""
(SCHEME_DIR / "SoundGuard.xcscheme").write_text(scheme)
print("wrote scheme")
