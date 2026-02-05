#!/usr/bin/env bash
set -euo pipefail

# (env-overridable)
KERNEL_DEFCONFIG=${KERNEL_DEFCONFIG:-gki_defconfig}
CLANG_VERSION=${CLANG_VERSION:-clang-r574158}
OUT_DIR=${OUT_DIR:-out}
CLANG_DIR=${CLANG_DIR:-"$HOME/tools/google-clang"}
CLANG_BINARY="$CLANG_DIR/bin/clang"
START_TIME=$(date +%s)
ANYKERNEL_DIR=${ANYKERNEL_DIR:-"$PWD/AnyKernel3"}
ZIP_NAME=${ZIP_NAME:-"Kernel-$(date +%Y%m%d-%H%M).zip"}


# --- pretty logs ---
GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
info(){ echo -e "${GREEN}[INFO]${NC} $*"; }
warn(){ echo -e "${YELLOW}[WARN]${NC} $*"; }
err(){  echo -e "${RED}[ERROR]${NC} $*"; exit 1; }

setup_clang() {
  info "Checking for Clang ($CLANG_VERSION)..."
  if [ ! -x "$CLANG_BINARY" ]; then
    warn "Clang not found. Fetching..."
    mkdir -p "$CLANG_DIR"
    TARBALL="$(mktemp)"

    URL_BASE="https://android.googlesource.com/platform/prebuilts/clang/host/linux-x86/+archive"
    PRIMARY_URL="$URL_BASE/refs/heads/main/${CLANG_VERSION}.tar.gz"
    ALT_URL="$URL_BASE/mirror-goog-main-llvm-toolchain-source/${CLANG_VERSION}.tar.gz"

    if command -v wget >/dev/null 2>&1; then
      DOWN_PRIMARY=(wget -q --show-progress -O "$TARBALL" "$PRIMARY_URL")
      DOWN_ALT=(wget -q --show-progress -O "$TARBALL" "$ALT_URL")
    elif command -v curl >/dev/null 2>&1; then
      DOWN_PRIMARY=(curl -L --fail -o "$TARBALL" "$PRIMARY_URL")
      DOWN_ALT=(curl -L --fail -o "$TARBALL" "$ALT_URL")
    else
      err "Need wget or curl to download the toolchain."
    fi

    if ! "${DOWN_PRIMARY[@]}"; then
      warn "Primary URL failed, trying mirror path..."
      "${DOWN_ALT[@]}" || err "Download failed from both URLs."
    fi

    info "Extracting toolchain..."
    tar -xzf "$TARBALL" -C "$CLANG_DIR"
    rm -f "$TARBALL"
  fi

  export PATH="$CLANG_DIR/bin:$PATH"
  ver="$("$CLANG_BINARY" --version | head -n1)"
  ver="$(echo "$ver" | sed -E 's/\(http[^)]*\)//g; s/[[:space:]]+/ /g; s/[[:space:]]+$//')"
  export KBUILD_COMPILER_STRING="$ver"
}

build_kernel() {
  info "Starting kernel build..."
  setup_clang
  mkdir -p "$OUT_DIR"

  make -j"$(nproc --all)" O="$OUT_DIR" ARCH=arm64 CC=clang LD=ld.lld LLVM=1 LLVM_IAS=1 \
       "$KERNEL_DEFCONFIG" || err "defconfig failed"

  make -j"$(nproc --all)" O="$OUT_DIR" ARCH=arm64 CC=clang LD=ld.lld LLVM=1 LLVM_IAS=1 \
       || err "build failed"

  total=$(( $(date +%s) - START_TIME ))
  info "Build finished in $((total/60))m $((total%60))s."
}

package_anykernel() {
  info "Packaging AnyKernel3 zip..."

  IMAGE="$OUT_DIR/arch/arm64/boot/Image.gz"
  [ -f "$IMAGE" ] || err "Image.gz not found!"

  TMP_AK="$(mktemp -d)"

  info "Preparing temp AnyKernel3 dir..."
  cp -r "$ANYKERNEL_DIR"/* "$TMP_AK"

  info "Copying Image.gz..."
  cp "$IMAGE" "$TMP_AK/"

  info "Creating zip..."
  (
    cd "$TMP_AK"
    zip -r9 "$ZIP_NAME" . >/dev/null
  )

  info "Cleaning full out/ directory..."
  rm -rf "$OUT_DIR"
  mkdir -p "$OUT_DIR"

  mv "$TMP_AK/$ZIP_NAME" "$OUT_DIR/"

  rm -rf "$TMP_AK"

  info "Flashable zip ready: $OUT_DIR/$ZIP_NAME"
}


# Always build
build_kernel
package_anykernel
