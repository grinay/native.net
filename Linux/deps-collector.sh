#!/bin/bash -e

# Check if the first argument is provided
if [ -z "$1" ]; then
  echo "Error: First argument (library path) is required."
  exit 1
fi

mkdir -p ./lib/

# Function to recursively process dependencies
process_dependency() {
  local lib="$1"
  # Filter needed libraries and get their paths
  local needed_lib=$(join \
    <(ldd "$lib" | awk '{if(substr($3,0,1)=="/") print $1,$3}' | sort) \
    <(patchelf --print-needed "$lib" | sort) | cut -d\  -f2)
  echo "$needed_lib" | while read -r lib_path; do
    # Filter empty lines
    if [ -z "$lib_path" ]; then
      continue
    fi
    # Copy the library and update processed list
    cp --copy-contents "$lib_path" ./lib/
    # Recursively process the needed library
    process_dependency "$lib_path"
  done
}

# Process the first argument (required library path)
process_dependency "$1"

# Copy the original file into the lib folder
cp --copy-contents "$1" ./lib/

# Go into the lib folder
cd ./lib/

# Loop over all files and set rpath
for file in *; do
  patchelf --set-rpath "\$ORIGIN" "$file"
done