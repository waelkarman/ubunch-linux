#!/bin/bash
set -euxo pipefail 
source ../../config.sh 

DEB_NAME=$(basename "$PWD")
DEB_VER=0.1

rm -fr ./"$DEB_NAME"_"$DEB_VER"_"$ARCH".deb
rm -fr ./"$DEB_NAME"_"$DEB_VER"_"$ARCH"

# Create package folder structure
mkdir -p "$DEB_NAME"_"$DEB_VER"_"$ARCH"/DEBIAN
mkdir -p "$DEB_NAME"_"$DEB_VER"_"$ARCH"/etc/systemd/system
mkdir -p "$DEB_NAME"_"$DEB_VER"_"$ARCH"/usr/local/lib

# Create control file
cat <<EOF > "$DEB_NAME"_"$DEB_VER"_"$ARCH"/DEBIAN/control
Package: $DEB_NAME
Version: $DEB_VER
Section: base
Priority: optional
Architecture: $ARCH
Maintainer: $MAINTAINER
Depends: 
Description: usefull bash libs
EOF

# Create postinst script 
cat <<EOF > "$DEB_NAME"_"$DEB_VER"_"$ARCH"/DEBIAN/postinst
#!/bin/bash
set -e

echo "[+] Libs $DEB_NAME installed..."

exit 0
EOF

# Create postrm script 
cat <<EOF > "$DEB_NAME"_"$DEB_VER"_"$ARCH"/DEBIAN/postrm
#!/bin/bash
set -e

case "\$1" in
    remove)
        echo "[+] $DEB_NAME removed"
        ;;
    purge)
        echo "[+] $DEB_NAME purged"

        ;;
    *)
        ;;
esac

exit 0
EOF

# Set permissions
chmod 755 "$DEB_NAME"_"$DEB_VER"_"$ARCH"/DEBIAN
chmod 644 "$DEB_NAME"_"$DEB_VER"_"$ARCH"/DEBIAN/control
chmod 755 "$DEB_NAME"_"$DEB_VER"_"$ARCH"/DEBIAN/postinst
chmod 755 "$DEB_NAME"_"$DEB_VER"_"$ARCH"/DEBIAN/postrm

# Copy files directly to their final destinations in the package
cp data/"$DEB_NAME".sh "$DEB_NAME"_"$DEB_VER"_"$ARCH"/usr/local/lib/"$DEB_NAME".sh

# Set correct permissions for installed files
chmod 755 "$DEB_NAME"_"$DEB_VER"_"$ARCH"/usr/local/lib/"$DEB_NAME".sh

# Build .deb package
fakeroot dpkg-deb --build "$DEB_NAME"_"$DEB_VER"_"$ARCH"

rm -fr ./"$DEB_NAME"_"$DEB_VER"_"$ARCH"
echo "Output: "$DEB_NAME"_"$DEB_VER"_"$ARCH".deb"