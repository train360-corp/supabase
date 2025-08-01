#!/bin/bash
set -euo pipefail

ARCH=$1
VERSION=$2
OUTDIR=$3

PKGNAME="supabase"
BUILDROOT="${OUTDIR}/${PKGNAME}_${VERSION}_${ARCH}"

# Copy template
cp -r supabase "$BUILDROOT"

# Inject version + arch into control file
sed -i "s/__VERSION__/$VERSION/" "$BUILDROOT/DEBIAN/control"
sed -i "s/__ARCH__/$ARCH/" "$BUILDROOT/DEBIAN/control"

# Build the .deb
dpkg-deb --build "$BUILDROOT"
