import uuid
import re

def generate_id():
    return uuid.uuid4().hex[:24].upper()

file_ref = generate_id()
build_file = generate_id()

with open('../Fleunce.xcodeproj/project.pbxproj', 'r') as f:
    content = f.read()

# Add to File References
file_ref_entry = f'\n{file_ref} = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = "App/Monetization.swift"; sourceTree = "<group>"; };'
content = content.replace('/* End PBXFileReference section */', f'{file_ref_entry}/* End PBXFileReference section */')

# Add to Build Files
build_file_entry = f'\n{build_file} = {{isa = PBXBuildFile; fileRef = {file_ref}; };'
content = content.replace('/* End PBXBuildFile section */', f'{build_file_entry}/* End PBXBuildFile section */')

# Add to PBXSourcesBuildPhase
# Find the main target's sources build phase
match = re.search(r'([A-Z0-9]{24}) = \{isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = \((.*?)\);', content, re.DOTALL)
if match:
    old_files = match.group(2)
    new_files = old_files.strip() + f', {build_file},'
    content = content.replace(old_files, new_files)

# Add to PBXGroup (App group)
# Look for App group, which contains all App files
match_group = re.search(r'B28B7AF69320201D1CF206EB = \{ isa = PBXGroup; children = \((.*?)\);', content, re.DOTALL)
if match_group:
    old_children = match_group.group(1)
    new_children = old_children.strip() + f', {file_ref},'
    content = content.replace(old_children, new_children)

with open('../Fleunce.xcodeproj/project.pbxproj', 'w') as f:
    f.write(content)
