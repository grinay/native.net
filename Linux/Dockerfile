# Use Amazon Linux 2 ARM64 Version as the base image  
FROM arm64v8/amazonlinux:2  
  
# Install build dependencies  
RUN yum update -y && \
    yum install -y git wget tar gzip patchelf gcc-c++ cmake3 zlib-devel libjpeg-turbo-devel perl && \
    yum install -y gnutls-devel && \
    yum groupinstall -y "Development Tools"  
  
# Compile and install a compatible version of OpenSSL  
WORKDIR /tmp  
RUN wget https://www.openssl.org/source/openssl-1.1.1l.tar.gz && \
    tar -zxvf openssl-1.1.1l.tar.gz && \
    cd openssl-1.1.1l && \
    ./config && \
    make && \
    make install  
  
# Set up environment variables to use the newly installed OpenSSL  
ENV LD_LIBRARY_PATH=/usr/local/lib:/usr/local/lib64  
ENV PATH=/usr/local/bin:$PATH  
  
# Amazon Linux 2 workaround for cmake version naming  
RUN alternatives --install /usr/local/bin/cmake cmake /usr/bin/cmake3 20 \
    --slave /usr/local/bin/ctest ctest /usr/bin/ctest3 \
    --slave /usr/local/bin/cpack cpack /usr/bin/cpack3 \
    --slave /usr/local/bin/ccmake ccmake /usr/bin/ccmake3  
  
# Set work directory for QPDF  
WORKDIR /tmp  
  
# Download and extract the latest QPDF source code  
ARG QPDF_VERSION=11.9.0  
RUN wget https://github.com/qpdf/qpdf/releases/download/v${QPDF_VERSION}/qpdf-${QPDF_VERSION}.tar.gz &&  \
    tar xvf qpdf-${QPDF_VERSION}.tar.gz &&  \
    rm qpdf-${QPDF_VERSION}.tar.gz   
  
# Build QPDF from source  
RUN mv qpdf-${QPDF_VERSION} qpdfsource  
WORKDIR /tmp/qpdfsource  
RUN cmake -S . -B build  
RUN cmake --build build  