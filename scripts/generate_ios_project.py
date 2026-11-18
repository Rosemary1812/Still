#!/usr/bin/env python3
"""Generate the iPhone project, sharing the Mac library model and photo repository."""
from pathlib import Path
import hashlib
import plistlib

root = Path(__file__).resolve().parents[1]
project = root / 'Still-iOS.xcodeproj'
project.mkdir(exist_ok=True)
objects = []


def uid(value):
    return hashlib.sha1(('ios-' + value).encode()).hexdigest()[:24].upper()


def quote(value):
    return '"' + str(value).replace('\\', '\\\\').replace('"', '\\"') + '"'


def add(key, body):
    objects.append(f'{uid(key)} = {{ {body} }};')


def refs(keys):
    return '(' + ','.join(uid(key) for key in keys) + ',)'


def file_ref(path, kind):
    key = str(path)
    add(key, f'isa = PBXFileReference; lastKnownFileType = {kind}; path = {quote(path)}; sourceTree = SOURCE_ROOT;')
    add('build-' + key, f'isa = PBXBuildFile; fileRef = {uid(key)};')
    return key


shared = [Path('Sources/ContactSheet/Models.swift'), Path('Sources/ContactSheet/PhotoRepository.swift')]
sources = [file_ref(path, 'sourcecode.swift') for path in shared + sorted(p.relative_to(root) for p in (root / 'Sources/StillIOS').glob('*.swift'))]
tests = [file_ref(p.relative_to(root), 'sourcecode.swift') for p in sorted((root / 'Tests/StillIOSUITests').glob('*.swift'))]
resources = [file_ref(Path('Resources/iOS/Assets.xcassets'), 'folder.assetcatalog')]
for number in [0, 1, 3, 6, 7, 8]:
    resources.append(file_ref(Path(f'previews/photo-albums/assets/photo-{number}.jpg'), 'image.jpeg'))
resources.append(file_ref(Path('previews/photo-albums/photo-sources.json'), 'text.json'))

for key, files, phase in [('sources', sources, 'PBXSourcesBuildPhase'), ('resources', resources, 'PBXResourcesBuildPhase'), ('testsources', tests, 'PBXSourcesBuildPhase')]:
    add(key, f'isa = {phase}; buildActionMask = 2147483647; files = {refs(["build-" + f for f in files])}; runOnlyForDeploymentPostprocessing = 0;')
add('app', 'isa = PBXFileReference; explicitFileType = wrapper.application; path = Still.app; sourceTree = BUILT_PRODUCTS_DIR;')
add('testproduct', 'isa = PBXFileReference; explicitFileType = wrapper.cfbundle; path = StillIOSUITests.xctest; sourceTree = BUILT_PRODUCTS_DIR;')
add('products', f'isa = PBXGroup; name = Products; children = {refs(["app", "testproduct"])}; sourceTree = "<group>";')
add('root', f'isa = PBXGroup; children = {refs(sources + tests + resources + ["products"])}; sourceTree = "<group>";')

for mode in ['Debug', 'Release']:
    common = {'SDKROOT': 'iphoneos', 'IPHONEOS_DEPLOYMENT_TARGET': '17.0', 'SWIFT_VERSION': '5.0',
              'CLANG_ENABLE_MODULES': 'YES', 'SWIFT_OPTIMIZATION_LEVEL': '-Onone' if mode == 'Debug' else '-O',
              'SWIFT_ACTIVE_COMPILATION_CONDITIONS': 'DEBUG' if mode == 'Debug' else '',
              'DEBUG_INFORMATION_FORMAT': 'dwarf', 'ENABLE_TESTABILITY': 'YES' if mode == 'Debug' else 'NO'}
    app = {'PRODUCT_NAME': 'Still', 'PRODUCT_MODULE_NAME': 'StillIOS', 'PRODUCT_BUNDLE_IDENTIFIER': 'local.still.ios',
           'INFOPLIST_FILE': 'Resources/iOS/Info.plist', 'TARGETED_DEVICE_FAMILY': '1',
           'SUPPORTED_PLATFORMS': 'iphoneos iphonesimulator', 'CODE_SIGN_STYLE': 'Automatic',
           'ASSETCATALOG_COMPILER_APPICON_NAME': 'AppIcon', 'SUPPORTS_MACCATALYST': 'NO',
           'LD_RUNPATH_SEARCH_PATHS': '$(inherited) @executable_path/Frameworks'}
    ui = {'PRODUCT_NAME': 'StillIOSUITests', 'PRODUCT_BUNDLE_IDENTIFIER': 'local.still.ios.uitests',
          'GENERATE_INFOPLIST_FILE': 'YES', 'TARGETED_DEVICE_FAMILY': '1', 'CODE_SIGN_STYLE': 'Automatic',
          'TEST_TARGET_NAME': 'StillIOS', 'SUPPORTED_PLATFORMS': 'iphoneos iphonesimulator'}
    for owner, settings in [('project', common), ('target', app), ('uitests', ui)]:
        body = ' '.join(k + ' = ' + quote(v) + ';' for k, v in settings.items())
        add(owner + mode, f'isa = XCBuildConfiguration; buildSettings = {{ {body} }}; name = {mode};')
for owner in ['project', 'target', 'uitests']:
    add(owner + 'configs', f'isa = XCConfigurationList; buildConfigurations = {refs([owner + "Debug", owner + "Release"])}; defaultConfigurationIsVisible = 0; defaultConfigurationName = Debug;')
add('target', f'isa = PBXNativeTarget; buildConfigurationList = {uid("targetconfigs")}; buildPhases = {refs(["sources", "resources"])}; buildRules = (); dependencies = (); name = StillIOS; productName = Still; productReference = {uid("app")}; productType = "com.apple.product-type.application";')
add('proxy', f'isa = PBXContainerItemProxy; containerPortal = {uid("project")}; proxyType = 1; remoteGlobalIDString = {uid("target")}; remoteInfo = StillIOS;')
add('dependency', f'isa = PBXTargetDependency; target = {uid("target")}; targetProxy = {uid("proxy")};')
add('uitests', f'isa = PBXNativeTarget; buildConfigurationList = {uid("uitestsconfigs")}; buildPhases = {refs(["testsources"])}; buildRules = (); dependencies = {refs(["dependency"])}; name = StillIOSUITests; productReference = {uid("testproduct")}; productType = "com.apple.product-type.bundle.ui-testing";')
add('project', f'isa = PBXProject; attributes = {{ LastUpgradeCheck = 1600; }}; buildConfigurationList = {uid("projectconfigs")}; compatibilityVersion = "Xcode 14.0"; developmentRegion = zh-Hans; knownRegions = ("zh-Hans", en, Base); mainGroup = {uid("root")}; productRefGroup = {uid("products")}; projectDirPath = ""; projectRoot = ""; targets = {refs(["target", "uitests"])};')
(project / 'project.pbxproj').write_text('// !$*UTF8*$!\n{ archiveVersion = 1; classes = {}; objectVersion = 56; objects = {\n' + '\n'.join(objects) + '\n}; rootObject = ' + uid('project') + '; }\n')

info = {'CFBundleDisplayName': 'Still', 'CFBundleExecutable': '$(EXECUTABLE_NAME)',
        'CFBundleIdentifier': '$(PRODUCT_BUNDLE_IDENTIFIER)', 'CFBundleName': 'Still', 'CFBundlePackageType': 'APPL',
        'CFBundleShortVersionString': '0.4.0', 'CFBundleVersion': '4', 'LSRequiresIPhoneOS': True,
        'UILaunchScreen': {}, 'UISupportedInterfaceOrientations': ['UIInterfaceOrientationPortrait', 'UIInterfaceOrientationLandscapeLeft', 'UIInterfaceOrientationLandscapeRight'],
        'NSPhotoLibraryUsageDescription': '选择照片，保存到你的 Still 相册。Still 不会修改或删除系统照片。'}
with (root / 'Resources/iOS/Info.plist').open('wb') as output:
    plistlib.dump(info, output)


def buildable(key, name, product):
    return f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{uid(key)}" BuildableName="{product}" BlueprintName="{name}" ReferencedContainer="container:Still-iOS.xcodeproj"/>'


scheme = project / 'xcshareddata/xcschemes'
scheme.mkdir(parents=True, exist_ok=True)
app_ref = buildable('target', 'StillIOS', 'Still.app')
test_ref = buildable('uitests', 'StillIOSUITests', 'StillIOSUITests.xctest')
(scheme / 'StillIOS.xcscheme').write_text(f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="1600" version="1.3">
  <BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries>
    <BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">{app_ref}</BuildActionEntry>
  </BuildActionEntries></BuildAction>
  <TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv="YES"><Testables><TestableReference skipped="NO">{test_ref}</TestableReference></Testables></TestAction>
  <LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0">{app_ref}</BuildableProductRunnable></LaunchAction>
  <ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"><BuildableProductRunnable runnableDebuggingMode="0">{app_ref}</BuildableProductRunnable></ProfileAction>
  <AnalyzeAction buildConfiguration="Debug"/><ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>
''')
