cd packages

# loop for every package in pacman, and build with chroot
for pkg in $(cat $1); do
    if [ -d "$pkg" ]; then continue; fi
    echo "Cloning and building: $pkg"
    pkgctl repo clone "$pkg" && cd "$pkg" || continue

    if [ "$pkg" = "texinfo" ]; then # patch for texinfo package
      sed -i -e 's|./configure --prefix=/usr|./configure --prefix=/usr -C CFLAGS="-march=skylake -mtune=skylake" PERL_EXT_CFLAGS="-march=skylake -mtune=skylake"|g' PKGBUILD
    fi

    makechrootpkg -c -r ~/archbuild -- --skipinteg --noconfirm --nocheck --clean --cleanbuild
    cd ..
done