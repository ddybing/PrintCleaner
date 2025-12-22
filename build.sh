#!/bin/bash

# 1. Read and Increment Version
if [ ! -f VERSION ]; then
    echo "1.0.0" > VERSION
fi

current_ver=$(cat VERSION)
IFS='.' read -r -a parts <<< "$current_ver"
major="${parts[0]}"
minor="${parts[1]}"
patch="${parts[2]}"

# Increment patch level
new_patch=$((patch + 1))
new_ver="$major.$minor.$new_patch"

# Save new version
echo "$new_ver" > VERSION
echo "Build Version: $new_ver"

# 2. Update Manifest Version (Format: 1.0.0.0)
sed -i "s/version=\"[0-9]*\.[0-9]*\.[0-9]*\.[0-9]*\"/version=\"$new_ver.0\"/" PrintCleaner.manifest

# 3. Inject Version into Script (Temporary)
cp PrintCleaner.ps1 PrintCleaner.ps1.bak
sed -i "s/\$AppVersion = \"0.0.0\"/\$AppVersion = \"$new_ver\"/" PrintCleaner.ps1

# 4. Rebuild Resources (Manifest + Icon)
# This ensures the exe has the admin rights request and the correct icon
go run github.com/akavel/rsrc -manifest PrintCleaner.manifest -ico icon.ico -arch amd64 -o rsrc.syso

# 5. Build Executable
output_name="PrintCleaner_v$new_ver.exe"
GOOS=windows GOARCH=amd64 go build -o "$output_name" main.go

# 6. Restore Original Script
mv PrintCleaner.ps1.bak PrintCleaner.ps1

echo "---------------------------------------"
echo "Successfully built: $output_name"
echo "---------------------------------------"

# 7. Git Release Integration
echo "Release Management"
echo "------------------"
read -p "Do you want to commit this version and trigger a GitHub Release for v$new_ver? (y/N) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo "Committing version bump..."
    git add VERSION PrintCleaner.manifest
    git commit -m "chore: release v$new_ver"
    
    echo "Tagging v$new_ver..."
    git tag "v$new_ver"
    
    echo "Pushing changes and tag..."
    git push origin main
    git push origin "v$new_ver"
    
    echo "---------------------------------------"
    echo "GitHub Action triggered for v$new_ver!"
    echo "Check status at: https://github.com/$(git config --get remote.origin.url | sed 's/.*github.com[:\/]\(.*\).git/\1/')/actions"
fi
