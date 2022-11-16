#!/bin/bash

# rebuild and encrypt tarball directory

archive='tarball'
password='tarball/tarball.password'

# check current directory
if [[ ! -x "$(pwd)/rebuild.tarball.sh" ]]; then
        echo "Please run this script from the autoconfig directory."
        exit 1
fi

# rebuild archive
tar -cvf "$archive.tar" "$archive"

# encrypt archive
gpg --symmetric --cipher-algo AES256 --batch --yes --passphrase-file "$password" --output "$archive.tar.gpg" "$archive.tar"

# success
exit 0