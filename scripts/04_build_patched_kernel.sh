#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BUILD_DIR="$WORKSPACE_ROOT/kernel/build"
KERNEL_SRC="$WORKSPACE_ROOT/kernel/linux"
PATCH_FILE="$WORKSPACE_ROOT/patches/fix_algif_aead.patch"
JOBS=$(nproc)

cd "$KERNEL_SRC"

# A. Aplicamos el parche de separación de memoria
perl -0777 -pi -e 's/rsgl_src,\s*rsgl_src/tsgl_src, rsgl_dst/g' crypto/algif_aead.c
mkdir -p "$WORKSPACE_ROOT/patches"
git diff crypto/algif_aead.c > "$PATCH_FILE"

# B. Compilamos el kernel parcheado (¡Usando la configuración vulnerable que ya existe!)
echo -e "\033[1;36m[+] Compilando kernel parcheado...\033[0m"
make -j"$JOBS" bzImage

# C. Lo guardamos en su lugar sin sobreescribir el vulnerable
cp arch/x86/boot/bzImage "$BUILD_DIR/bzImage_patched"

echo -e "\033[1;32m✓ Kernel parcheado generado exitosamente. Ambos núcleos conviven en el sistema.\033[0m"
