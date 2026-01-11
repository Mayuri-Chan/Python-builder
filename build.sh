#!/bin/bash

if [[ -f config.sh ]]; then
    source config.sh
fi

function parse_parameters() {
    while (($#)); do
        case $1 in
            all | deps | write_config | download | setup_clang | configure | build | install | compress | package | release ) action=$1 ;;
            *) exit 33 ;;
        esac
        shift
    done
}

function do_deps() {
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
    else
        echo "Error: /etc/os-release not found. Cannot determine distribution."
        exit 1
    fi

    case "$ID" in
        debian)
            if [[ $(command -v apt) ]]; then
                apt update && apt upgrade -y
                apt install -y curl gh wget build-essential libreadline-dev libncursesw5-dev libssl-dev libsqlite3-dev tk-dev libgdbm-dev libc6-dev libbz2-dev libffi-dev zlib1g-dev python3 python3-dev git patchelf file libgdbm-dev liblzma-dev
            else
                echo "apt not found on Debian."
                exit 1
            fi
            ;;
        fedora)
            if [[ $(command -v dnf) ]]; then
                dnf update -y
                dnf install -y curl gh wget which gcc gcc-c++ make readline-devel ncurses-devel openssl-devel sqlite-devel tk-devel gdbm-devel bzip2-devel libffi-devel zlib-devel python3 python3-devel git patchelf file xz-devel rpm-build
            else
                echo "dnf not found on Fedora."
                exit 1
            fi
            ;;
        *)
            echo "Unsupported distribution: $ID"
            exit 1
            ;;
    esac
}

function do_write_config() {
    cd "$BASE_DIR" || exit 1
    echo "#!/bin/bash" > config.sh
    echo "export BASE_DIR=$BASE_DIR" >> config.sh
    echo 'export PATH="$BASE_DIR/clang/bin:$PATH"' >> config.sh
    python_version=$(echo "$TARBALL_URL" | grep -oP 'Python-\K[0-9]+\.[0-9]+')
    python_version_full=$(echo "$TARBALL_URL" | grep -oP 'Python-\K[0-9]+\.[0-9]+\.[0-9]+')
    echo "export PYTHON_VERSION=$python_version" >> config.sh
    echo "export PYTHON_VERSION_FULL=$python_version_full" >> config.sh
    echo "export TARBALL_URL=$TARBALL_URL" >> config.sh
    if [[ -n $INSTALL_PATH ]]; then
        echo "export INSTALL_PATH=$INSTALL_PATH" >> config.sh
    else
        echo "export INSTALL_PATH=/opt/python$python_version" >> config.sh
    fi
    if [[ -n $ENABLE_JIT ]];then
        echo "export ENABLE_JIT=$ENABLE_JIT" >> config.sh
    else
        echo "export ENABLE_JIT=0" >> config.sh
    fi
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        case "$ID" in
            debian)
                echo "export DISTRO=$ID" >> config.sh
                echo "export DISTRO_VERSION=$VERSION_CODENAME" >> config.sh
                ;;
            fedora)
                echo "export DISTRO=$ID" >> config.sh
                echo "export DISTRO_VERSION=$VERSION_ID" >> config.sh
                ;;
            *)
                echo "Unsupported distribution: $ID"
                exit 1
                ;;
        esac
    else
        echo "Error: /etc/os-release not found. Cannot determine distribution."
        exit 1
    fi
    ARCH=$(uname -m)
    case "$ARCH" in
        x86_64)
            echo "export ARCH=x86_64" >> config.sh
            ;;
        aarch64)
            echo "export ARCH=aarch64" >> config.sh
            ;;
        *)
            echo "Unsupported architecture: $ARCH"
            exit 1
            ;;
    esac
}

function do_download() {
    cd "$BASE_DIR" || exit 1
    if [[ "$TARBALL_URL" == *.tar.gz || "$TARBALL_URL" == *.tgz ]];then
        curl -L "$TARBALL_URL" | tar -xz
    elif [[ "$TARBALL_URL" == *.tar.xz ]];then
        curl -L "$TARBALL_URL" | tar -xJ
    else
        echo "Unsupported archive format. Only .tgz, .tar.gz and .tar.xz are supported."
        exit 1
    fi
}

function do_setup_clang() {
    if [[ $ARCH = "x86_64" ]]; then
        if [[ $DISTRO = "fedora" ]]; then
            clang_url="https://github.com/Moon-Playground/tc-build/releases/download/21.1.8-2078da43e/Mayuri-clang_21.1.8-fedora43-x86_64-2078da43e.tar.xz"
        elif [[ $DISTRO = "debian" ]]; then
            if [[ $DISTRO_VERSION = "bookworm" ]]; then
                clang_url="https://github.com/Moon-Playground/tc-build/releases/download/21.1.8-2078da43e/Mayuri-clang_21.1.8-bookworm-x86_64-2078da43e.tar.xz"
            elif [[ $DISTRO_VERSION = "trixie" ]]; then
                clang_url="https://github.com/Moon-Playground/tc-build/releases/download/21.1.8-2078da43e/Mayuri-clang_21.1.8-trixie-x86_64-2078da43e.tar.xz"
            else
                echo "Unsupported Debian version. Only bookworm and trixie are supported."
                exit 1
            fi
        else
            echo "Unsupported distribution for x86_64 architecture."
            exit 1
        fi
    else
        if [[ $DISTRO = "fedora" ]]; then
            clang_url="https://github.com/Moon-Playground/tc-build/releases/download/21.1.8-2078da43e/Mayuri-clang_21.1.8-fedora43-aarch64-2078da43e.tar.xz"
        elif [[ $DISTRO = "debian" ]]; then
            if [[ $DISTRO_VERSION = "bookworm" ]]; then
                clang_url="https://github.com/Moon-Playground/tc-build/releases/download/21.1.8-2078da43e/Mayuri-clang_21.1.8-bookworm-aarch64-2078da43e.tar.xz"
            elif [[ $DISTRO_VERSION = "trixie" ]]; then
                clang_url="https://github.com/Moon-Playground/tc-build/releases/download/21.1.8-2078da43e/Mayuri-clang_21.1.8-trixie-aarch64-2078da43e.tar.xz"
            else
                echo "Unsupported Debian version. Only bookworm and trixie are supported."
                exit 1
            fi
        else
            echo "Unsupported distribution for ARM64 architecture."
            exit 1
        fi
    fi
    mkdir -p "$BASE_DIR"/clang
    cd "$BASE_DIR"/clang || exit 1
    wget -q --show-progress "$clang_url"
    if [[ $clang_url == *.tar.gz ]]; then
        tar -xzf *.tar.gz
    elif [[ $clang_url == *.tar.xz ]]; then
        tar -xJf *.tar.xz
    else
        echo "Unsupported archive format."
        exit 1
    fi
    clang_name=$(basename "$clang_url")
    if [[ "$clang_name" == "LLVM-"* ]]; then
        mv "$BASE_DIR"/clang/LLVM-*/* "$BASE_DIR"/clang/
        rm -rf "$BASE_DIR"/clang/LLVM-*
    fi
}

function do_configure() {
    if [[ "$ARCH" == "x86_64" ]]; then
        TARGET=x86_64-pc-linux-gnu
        HOST=x86_64-pc-linux-gnu
        BUILD=x86_64-pc-linux-gnu
    else
        TARGET=aarch64-unknown-linux-gnu
        HOST=aarch64-unknown-linux-gnu
        BUILD=aarch64-unknown-linux-gnu
    fi
    cd "$BASE_DIR"/Python-* || exit 1
    EXTRAFLAGS=""
    if [[ "$ENABLE_JIT" == "1" ]]; then
        EXTRAFLAGS+=" --enable-experimental-jit"
    fi
    sed -i 's#gitid = "main";#gitid = "'"$VENDOR_STRING"'";#g' Modules/getbuildinfo.c
    ./configure --prefix="$INSTALL_PATH" --target=$TARGET \
      --enable-shared --build=$BUILD --host=$HOST \
      --with-computed-gotos \
      --enable-optimizations \
      --with-lto \
      --enable-ipv6 \
      --with-dbmliborder=gdbm:ndbm \
      --enable-loadable-sqlite-extensions \
      --with-tzpath=/usr/share/zoneinfo \
      CC=$(which clang) \
      CXX=$(which clang++) \
      LLVM_AR=$(which llvm-ar) \
      LLVM_RANLIB=$(which llvm-ranlib) \
      LLVM_OBJCOPY=$(which llvm-objcopy) \
      LLVM_OBJDUMP=$(which llvm-objdump) \
      LLVM_NM=$(which llvm-nm) \
      LLVM_STRIP=$(which llvm-strip) \
      LLVM_PROFDATA=$(which llvm-profdata) \
      LDFLAGS="-Wl,--rpath=$INSTALL_PATH/lib -fuse-ld=lld" \
      $EXTRAFLAGS || exit 1
}

function do_build(){
    cd "$BASE_DIR"/Python-* || exit 1
    make -j$(nproc)
}

function do_install() {
    cd "$BASE_DIR"/Python-* || exit 1
    make altinstall

    # Strip remaining binaries
    for f in $(find "$INSTALL_PATH" -type f -exec file {} \; | grep 'not stripped' | awk '{print $1}'); do
        strip -s "${f::-1}"
    done
}

function do_compress() {
    cd "$BASE_DIR"/Python-* || exit 1
    mkdir -p "$BASE_DIR"/dist
    tar -cJf "$BASE_DIR"/dist/python-$PYTHON_VERSION_FULL-$DISTRO-$DISTRO_VERSION-$ARCH.tar.xz -C "$INSTALL_PATH" .
}

function do_deb() {
    sed -i "s/<version>/$PYTHON_VERSION/g" "$BASE_DIR"/package_root/DEBIAN/control
    sed -i "s/<full_version>/$PYTHON_VERSION_FULL/g" "$BASE_DIR"/package_root/DEBIAN/control
    if [[ "$ARCH" == "aarch64" ]]; then
        sed -i "s/<arch>/arm64/g" "$BASE_DIR"/package_root/DEBIAN/control
    else
        sed -i "s/<arch>/amd64/g" "$BASE_DIR"/package_root/DEBIAN/control
    fi
    mkdir -p "$BASE_DIR"/package_root"$INSTALL_PATH"
    cp -r "$INSTALL_PATH"/* "$BASE_DIR"/package_root"$INSTALL_PATH"/
    dpkg-deb --build "$BASE_DIR"/package_root "$BASE_DIR"/dist/python-$PYTHON_VERSION_FULL-$DISTRO-$DISTRO_VERSION-$ARCH.deb
}

function do_rpm() {
    mkdir -p "$BASE_DIR"/rpmbuild/{BUILD,RPMS,SOURCES,SPECS,SRPMS,BUILDROOT}

    # RPM versions cannot contain hyphens
    RPM_VERSION=${PYTHON_VERSION_FULL//-/_}

    cat <<EOF > "$BASE_DIR"/rpmbuild/SPECS/python.spec
# Disable the build-id and debuginfo generation that is causing the crash
%define _missing_build_ids_terminate_build 0
%define debug_package %{nil}
%define _build_id_links none
%global __brp_ldconfig /usr/bin/true
%global __brp_strip /usr/bin/true
%global __brp_mangle_shebangs /usr/bin/true
%global __brp_check_rpaths /usr/bin/true
%global __brp_python_bytecompile /usr/bin/true

Name:           python${PYTHON_VERSION}-mayuri
Version:        ${RPM_VERSION}
Release:        1%{?dist}
Summary:        Custom build of Python ${PYTHON_VERSION_FULL}
License:        Python
Vendor:         Mayuri
AutoReqProv:    no

%description
Custom build of Python ${PYTHON_VERSION_FULL}
Provides latest features and optimizations.

%install
mkdir -p %{buildroot}${INSTALL_PATH}
cp -a ${INSTALL_PATH}/* %{buildroot}${INSTALL_PATH}/
find %{buildroot}${INSTALL_PATH} -type f -name "*.py" -exec sed -i '1s|^#!.*python$|#!/usr/bin/python3|' {} +

%files
${INSTALL_PATH}

%changelog
* Sun Jan 11 2026 wulan17 <wulan17@komodos.id> - ${RPM_VERSION}-1
- Initial build
EOF

    rpmbuild -bb --define "_topdir $BASE_DIR/rpmbuild" "$BASE_DIR"/rpmbuild/SPECS/python.spec

    mkdir -p "$BASE_DIR"/dist
    find "$BASE_DIR"/rpmbuild/RPMS -name "*.rpm" -exec cp {} "$BASE_DIR"/dist/ \;
}

function do_release() {
    # Upload to GitHub Releases using GitHub CLI
    # Find tarball files
    file_name=$(find "$BASE_DIR"/dist/ -maxdepth 1 -name "python-$PYTHON_VERSION_FULL-$DISTRO-$DISTRO_VERSION-$ARCH.tar.xz" -print -quit)

    if [[ -z $file_name ]]; then
        echo "No file found to upload."
        exit 1
    fi

    git_hash=$(git -C "$BASE_DIR"/Python-* rev-parse --short HEAD)
    clang_version=$(clang --version | head -n 1 | awk '{print $4}')
    lld_version=$(ld.lld --version | head -n 1 | awk '{print $3}')

    TAG="python-v$PYTHON_VERSION_FULL"
    ASSET="$file_name"
    REPO="$GITHUB_REPOSITORY"
    TITLE="Python $PYTHON_VERSION_FULL"
    NOTES="Python $PYTHON_VERSION_FULL\n\n"
    NOTES+="Build Date: $(date)\n"
    NOTES+="Install Path: $INSTALL_PATH\n"
    NOTES+="Git Hash: $git_hash\n"
    NOTES+="Clang Version: $clang_version\n"
    NOTES+="LLD Version: $lld_version\n"

    # Check if release exists
    if gh release view "$TAG" --repo "$REPO" &>/dev/null; then
        echo "Release $TAG exists, uploading asset..."
        gh release upload "$TAG" "$ASSET" --repo "$REPO" --clobber
    else
        echo "Release $TAG does not exist, creating release and uploading asset..."
        # Workaround
        # if another release is created at the same time, it will fail
        # so we try to create release first and then upload asset
        # this usually happens if the workflow is contains multiple matrix jobs
        # and they are running at the same time
        gh release create "$TAG" "$ASSET" \
            --title "$TITLE" \
            --notes "$NOTES" \
            --target "$GITHUB_REF_NAME" \
            --repo "$REPO" || gh release upload "$TAG" "$ASSET" --repo "$REPO" --clobber
    fi
    # Upload distribution packages
    if [[ "$DISTRO" == "debian" ]]; then
        for file in "$BASE_DIR"/dist/*.deb; do
            if [[ -f "$file" ]]; then
                gh release upload "$TAG" "$file" --repo "$REPO" --clobber
            fi
        done
    elif [[ "$DISTRO" == "fedora" ]]; then
        for file in "$BASE_DIR"/dist/*.rpm; do
            if [[ -f "$file" ]]; then
                gh release upload "$TAG" "$file" --repo "$REPO" --clobber
            fi
        done
    fi
    echo "Released successfully."
}

function do_package() {
    if [[ "$DISTRO" == "debian" ]]; then
        do_deb
    elif [[ "$DISTRO" == "fedora" ]]; then
        do_rpm
    fi
}

function do_all() {
    do_deps
    do_write_config
    do_setup_clang
    do_download
    do_configure
    do_build
    do_install
    do_compress
    do_package
}

parse_parameters "$@"
do_"${action:=all}"
