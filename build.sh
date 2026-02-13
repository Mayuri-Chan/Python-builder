#!/bin/bash

if [[ -f config.sh ]]; then
    source config.sh
fi

function parse_parameters() {
    while (($#)); do
        case $1 in
            all | deps | write_config | setup_clang | configure | build | install | compress | package | release ) action=$1 ;;
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
                apt install -y \
                    curl gh wget build-essential gdb lcov pkg-config \
                    libreadline-dev libncursesw5-dev libssl-dev \
                    libsqlite3-dev tk-dev libgdbm-dev libgdbm-compat-dev \
                    libc6-dev libbz2-dev libffi-dev zlib1g-dev python3 \
                    python3-dev git patchelf file liblzma-dev lzma \
                    uuid-dev libzstd-dev inetutils-inetd \
                    libncurses5-dev libreadline6-dev
                if [[ $DISTRO_VERSION = "bookworm" ]]; then
                    apt install -y lzma-dev
                fi
            else
                echo "apt not found on Debian."
                exit 1
            fi
            ;;
        fedora)
            if [[ $(command -v dnf) ]]; then
                dnf update -y
                dnf install -y \
                    pkg-config dnf-plugins-core curl gh wget which \
                    gcc gcc-c++ make gdb lzma glibc-devel libstdc++-devel \
                    openssl-devel readline-devel zlib-devel libzstd-devel \
                    libffi-devel bzip2-devel xz-devel sqlite sqlite-devel \
                    sqlite-libs libuuid-devel gdbm-libs gdbm-devel perf \
                    expat expat-devel mpdecimal python3-pip python3 \
                    python3-devel git patchelf file ncurses-devel \
                    tk-devel rpm-build
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
    python_major=$(cat "$BASE_DIR/src/Include/patchlevel.h" | grep 'define PY_MAJOR_VERSION' | grep -oP '[0-9]+')
    python_minor=$(cat "$BASE_DIR/src/Include/patchlevel.h" | grep 'define PY_MINOR_VERSION' | grep -oP '[0-9]+')
    python_micro=$(cat "$BASE_DIR/src/Include/patchlevel.h" | grep 'define PY_MICRO_VERSION' | grep -oP '[0-9]+')
    python_version="$python_major.$python_minor"
    python_version_full="$python_major.$python_minor.$python_micro"
    echo "export PYTHON_VERSION=$python_version" >> config.sh
    echo "export PYTHON_VERSION_FULL=$python_version_full" >> config.sh
    if [[ -n $INSTALL_PATH ]]; then
        echo "export INSTALL_PATH=$INSTALL_PATH" >> config.sh
    else
        echo "export INSTALL_PATH=/opt/cinder$python_version" >> config.sh
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
    : "${VENDOR_STRING:=Mayuri}"
    if [[ "$ARCH" == "x86_64" ]]; then
        TARGET=x86_64-pc-linux-gnu
        HOST=x86_64-pc-linux-gnu
        BUILD=x86_64-pc-linux-gnu
    else
        TARGET=aarch64-unknown-linux-gnu
        HOST=aarch64-unknown-linux-gnu
        BUILD=aarch64-unknown-linux-gnu
    fi
    cd "$BASE_DIR"/src || exit 1
    git checkout -b "$VENDOR_STRING" || true
    sed -i "s/return GITVERSION;/return \"\";/" Modules/getbuildinfo.c
    sed -i "s/gitid = GITBRANCH;/gitid = \"$VENDOR_STRING\";/" Modules/getbuildinfo.c
    git add Modules/getbuildinfo.c
    git config --local user.name "mayuri"
    git config --local user.email "mayuri@mayuri.my.id"
    git commit -m "Set vendor string to $VENDOR_STRING"
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
      LDFLAGS="-Wl,--rpath=$INSTALL_PATH/lib -fuse-ld=lld" || exit 1
}

function do_build(){
    cd "$BASE_DIR"/src || exit 1
    make -j$(nproc)
}

function do_install() {
    cd "$BASE_DIR"/src || exit 1
    make altinstall

    # Strip remaining binaries
    for f in $(find "$INSTALL_PATH" -type f -exec file {} \; | grep 'not stripped' | awk '{print $1}'); do
        strip -s "${f::-1}"
    done
}

function do_compress() {
    mkdir -p "$BASE_DIR"/dist
    tar -cJf "$BASE_DIR"/dist/cinder-$PYTHON_VERSION_FULL-$DISTRO-$DISTRO_VERSION-$ARCH.tar.xz -C "$INSTALL_PATH" .
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
    dpkg-deb --build "$BASE_DIR"/package_root "$BASE_DIR"/dist/cinder-$PYTHON_VERSION_FULL-$DISTRO-$DISTRO_VERSION-$ARCH.deb
}

function do_rpm() {
    mkdir -p "$BASE_DIR"/rpmbuild/{BUILD,RPMS,SOURCES,SPECS,SRPMS,BUILDROOT}

    # RPM versions cannot contain hyphens
    RPM_VERSION=${PYTHON_VERSION_FULL//-/_}

    cat <<EOF > "$BASE_DIR"/rpmbuild/SPECS/cinder.spec
# Disable the build-id and debuginfo generation that is causing the crash
%define _missing_build_ids_terminate_build 0
%define debug_package %{nil}
%define _build_id_links none
%global __brp_ldconfig /usr/bin/true
%global __brp_strip /usr/bin/true
%global __brp_mangle_shebangs /usr/bin/true
%global __brp_check_rpaths /usr/bin/true
%global __brp_python_bytecompile /usr/bin/true

Name:           cinder${PYTHON_VERSION}-mayuri
Version:        ${RPM_VERSION}
Release:        1%{?dist}
Summary:        Custom build of Cinder Python ${PYTHON_VERSION_FULL}
License:        Python
Vendor:         Mayuri
AutoReqProv:    no

%description
Custom build of Cinder Python ${PYTHON_VERSION_FULL}
Provides latest features and optimizations.

%install
mkdir -p %{buildroot}${INSTALL_PATH}
cp -a ${INSTALL_PATH}/* %{buildroot}${INSTALL_PATH}/
find %{buildroot}${INSTALL_PATH} -type f -name "*.py" -exec sed -i '1s|^#!.*python$|#!/usr/bin/python3|' {} +

%files
${INSTALL_PATH}

%changelog
* $(date "+%a %b %d %Y") Mayuri <contact@mayuri.io> - ${RPM_VERSION}-1
- Initial build
EOF

    rpmbuild -bb --define "_topdir $BASE_DIR/rpmbuild" "$BASE_DIR"/rpmbuild/SPECS/cinder.spec

    mkdir -p "$BASE_DIR"/dist
    find "$BASE_DIR"/rpmbuild/RPMS -name "*.rpm" -exec cp {} "$BASE_DIR"/dist/ \;
}

function do_release() {
    # Upload to GitHub Releases using GitHub CLI
    # Find tarball files
    file_name=$(find "$BASE_DIR"/dist/ -maxdepth 1 -name "cinder-$PYTHON_VERSION_FULL-$DISTRO-$DISTRO_VERSION-$ARCH.tar.xz" -print -quit)

    if [[ -z $file_name ]]; then
        echo "No file found to upload."
        exit 1
    fi

    clang_version=$("${BASE_DIR}/clang/bin/clang" --version | head -n 1 | awk '{print $4}')
    lld_version=$("${BASE_DIR}/clang/bin/ld.lld" --version | head -n 1 | awk '{print $3}')

    # OS Information
    if [[ -f /etc/os-release ]]; then
        source /etc/os-release
        os_info="$PRETTY_NAME"
    else
        os_info="Unknown Linux"
    fi

    GIT_HASH=$(git -C "$BASE_DIR/src" rev-parse HEAD)
    TAG="cinder-v$PYTHON_VERSION_FULL-${GIT_HASH:0:7}"
    ASSET="$file_name"
    REPO="$GITHUB_REPOSITORY"
    TITLE="Python (cinder) $PYTHON_VERSION_FULL"
    
    # Format release notes as a markdown table
    NOTES="### 🐍 Python $PYTHON_VERSION_FULL Build Information

| Information | Value |
| :--- | :--- |
| **Build Date** | \`$(date)\` |
| **Commit** | [${GIT_HASH:0:7}](https://github.com/facebookincubator/cinder/tree/$GIT_HASH) |
| **Install Path** | \`$INSTALL_PATH\` |
| **Clang Version** | \`$clang_version\` |
| **LLD Version** | \`$lld_version\` |"

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
    do_configure
    do_build
    do_install
    do_compress
    do_package
}

parse_parameters "$@"
do_"${action:=all}"
