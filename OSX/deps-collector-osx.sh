#!/bin/bash -e

# Check if the first and second arguments are provided
if [ -z "$1" ] || [ -z "$2" ]; then
  echo "Error: First argument (library path) and second argument (output folder) are required."
  exit 1
fi

OUTPUT_FOLDER=$2

mkdir -p "$OUTPUT_FOLDER"

# Function to recursively process dependencies
process_dependency() {
  local lib="$1"

  echo "Processing $lib"
  # Filter needed libraries and get their paths (handle both absolute paths and @rpath references)
local needed_lib=$(otool -L "$lib" | awk -v lib="$lib" 'NR>1 {if($1 != lib && (substr($1,1,1)=="/" || substr($1,1,7)=="@rpath/")) print $1}' | sort)
  
  echo "$needed_lib" | while read -r lib_path; do
    # Skip empty lines
    if [ -z "$lib_path" ]; then
      continue
    fi

    # Debug statement to print lib_path
    echo "Checking lib_path: $lib_path"

    # If dependency uses @rpath, try to resolve it relative to the current library's directory
    if [[ "$lib_path" == @rpath/* ]]; then
      lib_dir=$(dirname "$lib")
      candidate="$lib_dir/$(basename "$lib_path")"
      #print candidate
      if [ -f "$candidate" ]; then
        lib_path="$candidate"
      else
        echo "Warning: Could not resolve $lib_path relative to $lib_dir, skipping."
        continue
      fi
    fi

    # Skip if dependency points to itself
    if [ "$lib" == "$lib_path" ]; then
      continue
    fi

    # Exclude system libraries
    if [[ "$lib_path" == /usr/lib/* ]] || [[ "$lib_path" == /System/Library/* ]]; then
      continue
    fi

    echo "Found dependency: $lib_path"
    # Copy the dependency into the output folder
    cp -L "$lib_path" "$OUTPUT_FOLDER"
    # Recursively process this dependency
    process_dependency "$lib_path"
  done
}

# Process the main library provided as the first argument
process_dependency "$1"

# Copy the original file into the output folder
cp "$1" "$OUTPUT_FOLDER"

# Go into the output folder
cd "$OUTPUT_FOLDER"

# Adjust install names and re-sign each library in the output folder
for lib in *; do
  install_name_tool -id "@rpath/$lib" "$lib"
  # Update dependency paths for each library
  otool -L "$lib" | awk '{print $1}' | while read -r dep; do
    if [[ "$dep" == /usr/lib/* ]] || [[ "$dep" == /System/Library/* ]]; then
      continue
    fi
    depname=$(basename "$dep")
    newpath="@loader_path/$depname"
    echo "Changing $dep to $newpath in $lib"
    install_name_tool -change "$dep" "$newpath" "$lib"
  done

  # Re-sign the library with an ad-hoc signature
  echo "Re-signing $lib with ad-hoc signature"
  codesign --force --deep --preserve-metadata=entitlements,requirements,flags,runtime --sign - "$lib"
done
