#!/bin/bash -e

# Install extra dependencies that were provided for the build (if any)
#   Note: dpkg can fail due to dependencies, ignore errors, and use
#   apt-get to install those afterwards
[[ -d /dependencies ]] && dpkg -i /dependencies/*.deb || apt-get -f install -y --no-install-recommends

# Make read-write copy of source code
mkdir -p /build
cp -a /source-ro /build/source
cd /build/source

# Install build dependencies
mk-build-deps -ir -t "apt-get -o Debug::pkgProblemResolver=yes -y --no-install-recommends"

# Build packages
#1. build deb package
debuild -b -uc -us

# Copy packages to output dir with user's permissions
chown -R $USER:$GROUP /build
cp -a /build/*.deb /output/

#2. convert to rpm
alien -r -c -v /build/*.deb 
cp -a *.rpm /output/
