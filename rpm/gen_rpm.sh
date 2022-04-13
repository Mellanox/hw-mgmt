#!/bin/bash


# Find the list of files

# Find version
RPM_VERSION=`grep "hw-management" ../debian/changelog | cut -d "(" -f2 | cut -d ")" -f1`

# Build RPM
rpmbuild -ba --define="version ${RPM_VERSION}" hw-management.spec
