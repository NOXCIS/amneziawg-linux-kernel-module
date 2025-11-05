#!/bin/bash
# PRE_BUILD script for DKMS to fix kernel 6.12+ compatibility issues
# This script runs after patches are applied but before compilation

set -e

# DKMS sets PWD to the build directory
# The generated directory is typically in the same directory
GENERATED_DIR="$(pwd)/generated"
SRC_DIR="$(pwd)"

# Try to find generated directory
if [ ! -d "$GENERATED_DIR" ]; then
    # Try alternative locations
    if [ -d "$(pwd)/src/generated" ]; then
        GENERATED_DIR="$(pwd)/src/generated"
    elif [ -d "$(dirname $(pwd))/generated" ]; then
        GENERATED_DIR="$(dirname $(pwd))/generated"
    fi
fi

if [ ! -d "$GENERATED_DIR" ]; then
    echo "Warning: Could not find generated directory, trying current directory"
    GENERATED_DIR="$(pwd)"
fi

echo "Applying kernel 6.12+ compatibility fixes in: $GENERATED_DIR"

# Fix 1: MODULE_ALIAS_GENL_FAMILY - use string literal instead of macro
if [ -f "$GENERATED_DIR/main.c" ]; then
    if grep -q 'MODULE_ALIAS_GENL_FAMILY(WG_GENL_NAME)' "$GENERATED_DIR/main.c"; then
        sed -i 's/MODULE_ALIAS_GENL_FAMILY(WG_GENL_NAME)/MODULE_ALIAS_GENL_FAMILY("amneziawg")/g' "$GENERATED_DIR/main.c"
        echo "Fixed MODULE_ALIAS_GENL_FAMILY in main.c"
    fi
fi

# Fix 2: skb_gso_segment - update to use dev->features for kernel 6.10+
if [ -f "$GENERATED_DIR/device.c" ]; then
    # Check if we need to fix the skb_gso_segment call
    if grep -q 'skb_gso_segment(skb, 0)' "$GENERATED_DIR/device.c" && ! grep -q 'LINUX_VERSION_CODE >= KERNEL_VERSION(6, 10, 0)' "$GENERATED_DIR/device.c"; then
        # Use perl for more reliable multiline replacement
        perl -i -pe 'BEGIN{undef $/;} s/struct sk_buff \*segs = skb_gso_segment\(skb, 0\);/struct sk_buff *segs;\n#if LINUX_VERSION_CODE >= KERNEL_VERSION(6, 10, 0)\n\t\tsegs = skb_gso_segment(skb, dev->features);\n#else\n\t\tsegs = skb_gso_segment(skb, 0);\n#endif/sg' "$GENERATED_DIR/device.c" 2>/dev/null || \
        sed -i 's/skb_gso_segment(skb, 0)/skb_gso_segment(skb, dev->features)/g' "$GENERATED_DIR/device.c"
        echo "Fixed skb_gso_segment call in device.c"
    fi
fi

echo "Compatibility fixes applied successfully"

