#!/bin/bash -e

# Check if the first and second arguments are provided
if [ -z "$1" ] || [ -z "$2" ]; then
  echo "Error: First argument (library path) and second argument (output folder) are required."
  exit 1
fi

OUTPUT_FOLDER=$2

mkdir -p $OUTPUT_FOLDER

# Function to recursively process dependencies
process_dependency() {
  local lib="$1"

  echo "Processing $lib"
  # Filter needed libraries and get their paths
  local needed_lib=$(otool -L "$lib" | awk -v lib="$lib:" '{if($1 != lib && substr($1,0,1)=="/") print $1}' | sort)
  echo "$needed_lib" | while read -r lib_path; do
    # Filter empty lines or if lib points to itself
    if [ -z "$lib_path" ]; then
      continue
    fi
    if [ "$lib" == "$lib_path" ]; then
      continue
    fi
    # Exclude system libraries
    if [[ "$lib_path" == /usr/lib/* ]] || [[ "$lib_path" == /System/Library/* ]]; then
      continue
    fi

    echo $lib_path
    # Copy the library and update processed list
    cp -L "$lib_path" $OUTPUT_FOLDER
    # Recursively process the needed library
    process_dependency "$lib_path"
  done
}

# Process the first argument (required library path)
process_dependency "$1"

# Copy the original file into the output folder
cp "$1" $OUTPUT_FOLDER

# Go into the output folder
cd $OUTPUT_FOLDER

for lib in *; do
  install_name_tool -id "@rpath/$lib" "$lib"
  # Update rpath for each dependency
  otool -L "$lib" | awk '{print $1}' | while read -r dep; do
    if [[ "$dep" == /usr/lib/* ]] || [[ "$dep" == /System/Library/* ]]; then
      continue
    fi
    depname=$(basename "$dep")
    newpath="@loader_path/$depname"
    echo "Changing $dep to $newpath in $lib"
    install_name_tool -change "$dep" "$newpath" "$lib"
  done

  # Re-sign the dylib with an ad-hoc signature
  echo "Re-signing $lib with ad-hoc signature"
  codesign --force --deep --preserve-metadata=entitlements,requirements,flags,runtime --sign - "$lib"
done