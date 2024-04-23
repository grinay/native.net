#!/bin/bash -e

QPDF_VERSION=11.9.0

# Check if the qpdfsource directory exists
if [ ! -d "qpdfsource" ]; then
  # If not, download and extract the QPDF source code
  wget https://github.com/qpdf/qpdf/releases/download/v${QPDF_VERSION}/qpdf-${QPDF_VERSION}.tar.gz &&
    tar xvf qpdf-${QPDF_VERSION}.tar.gz &&
    rm qpdf-${QPDF_VERSION}.tar.gz

  mv qpdf-${QPDF_VERSION} qpdfsource
fi

# Continue with the rest of the script
cd qpdfsource
cmake -S . -B build
cmake --build build