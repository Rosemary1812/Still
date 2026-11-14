#!/usr/bin/env python3
"""Generate a dependency-free Xcode project. Run after adding Swift files."""
from pathlib import Path
import hashlib
root=Path(__file__).resolve().parents[1]
def uid(s): return hashlib.sha1(s.encode()).hexdigest()[:24].upper()
def q(s): return '"'+str(s).replace('\\','\\\\').replace('"','\\"')+'"'
files=sorted((root/'Sources/ContactSheet').glob('*.swift'))
obj=[]
def add(i,body): obj.append(f'{i} = {{ {body} }};')
for f in files:
 add(uid('ref'+f.name),f'isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = {q(f.name)}; sourceTree = "<group>";')
 add(uid('build'+f.name),f'isa = PBXBuildFile; fileRef = {uid("ref"+f.name)};')
add(uid('app'),'isa = PBXFileReference; explicitFileType = wrapper.application; path = "Contact Sheet.app"; sourceTree = BUILT_PRODUCTS_DIR;')
add(uid('sources'),f'isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = ({",".join(uid("build"+f.name) for f in files)},); runOnlyForDeploymentPostprocessing = 0;')
add(uid('sourcegroup'),f'isa = PBXGroup; children = ({",".join(uid("ref"+f.name) for f in files)},); path = Sources/ContactSheet; sourceTree = "<group>";')
add(uid('productgroup'),f'isa = PBXGroup; children = ({uid("app")},); name = Products; sourceTree = "<group>";')
add(uid('rootgroup'),f'isa = PBXGroup; children = ({uid("sourcegroup")},{uid("productgroup")},); sourceTree = "<group>";')
for mode in ['Debug','Release']:
 add(uid('project'+mode),f'isa = XCBuildConfiguration; buildSettings = {{ MACOSX_DEPLOYMENT_TARGET = 14.0; SDKROOT = macosx; SWIFT_VERSION = 5.0; CLANG_ENABLE_MODULES = YES; }}; name = {mode};')
 settings={'PRODUCT_NAME':'Contact Sheet','PRODUCT_BUNDLE_IDENTIFIER':'local.contact-sheet.app','INFOPLIST_FILE':'Info.plist','CODE_SIGN_ENTITLEMENTS':'ContactSheet.entitlements','CODE_SIGN_IDENTITY':'-','CODE_SIGN_STYLE':'Manual','ENABLE_HARDENED_RUNTIME':'NO','SWIFT_OPTIMIZATION_LEVEL':'-Onone' if mode=='Debug' else '-O','SWIFT_ACTIVE_COMPILATION_CONDITIONS':'DEBUG' if mode=='Debug' else '', 'COMBINE_HIDPI_IMAGES':'YES'}
 add(uid('target'+mode),'isa = XCBuildConfiguration; buildSettings = {'+' '.join(k+' = '+q(v)+';' for k,v in settings.items())+f'}}; name = {mode};')
for owner in ['project','target']:
 add(uid(owner+'configs'),f'isa = XCConfigurationList; buildConfigurations = ({uid(owner+"Debug")},{uid(owner+"Release")},); defaultConfigurationIsVisible = 0; defaultConfigurationName = Debug;')
add(uid('target'),f'isa = PBXNativeTarget; buildConfigurationList = {uid("targetconfigs")}; buildPhases = ({uid("sources")},); buildRules = (); dependencies = (); name = ContactSheet; productName = "Contact Sheet"; productReference = {uid("app")}; productType = "com.apple.product-type.application";')
add(uid('project'),f'isa = PBXProject; attributes = {{ LastUpgradeCheck = 1600; }}; buildConfigurationList = {uid("projectconfigs")}; compatibilityVersion = "Xcode 14.0"; developmentRegion = en; hasScannedForEncodings = 0; knownRegions = (en, Base); mainGroup = {uid("rootgroup")}; productRefGroup = {uid("productgroup")}; projectDirPath = ""; projectRoot = ""; targets = ({uid("target")},);')
p=root/'ContactSheet.xcodeproj'; p.mkdir(exist_ok=True)
(p/'project.pbxproj').write_text('// !$*UTF8*$!\n{ archiveVersion = 1; classes = {}; objectVersion = 56; objects = {\n'+'\n'.join(obj)+'\n}; rootObject = '+uid('project')+'; }\n')
