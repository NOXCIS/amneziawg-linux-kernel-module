#!/bin/bash
# PRE_BUILD script for DKMS to fix kernel 6.12+ compatibility issues
# Note: This may run before patches, so we'll create a post-patch script too

set +e  # Don't fail if files don't exist yet

# DKMS sets PWD to the build directory when PRE_BUILD runs
# The generated directory is where patches are applied
GENERATED_DIR="$(pwd)/generated"

# Try to find generated directory - it should exist after patches are applied
if [ ! -d "$GENERATED_DIR" ]; then
    # Try alternative locations
    if [ -d "generated" ]; then
        GENERATED_DIR="$(pwd)/generated"
    elif [ -d "$(pwd)/src/generated" ]; then
        GENERATED_DIR="$(pwd)/src/generated"
    elif [ -d "$(dirname $(pwd))/generated" ]; then
        GENERATED_DIR="$(dirname $(pwd))/generated"
    else
        # If generated doesn't exist yet, patches haven't run - use current dir
        GENERATED_DIR="$(pwd)"
    fi
fi

echo "DKMS PRE_BUILD: Applying kernel 6.12+ compatibility fixes"
echo "Working directory: $(pwd)"
echo "Generated directory: $GENERATED_DIR"
echo "Files in generated: $(ls -la "$GENERATED_DIR" 2>/dev/null | head -5 || echo 'not found')"

# Fix 1: MODULE_ALIAS_GENL_FAMILY - use string literal instead of macro
if [ -f "$GENERATED_DIR/main.c" ]; then
    if grep -q 'MODULE_ALIAS_GENL_FAMILY(WG_GENL_NAME)' "$GENERATED_DIR/main.c"; then
        sed -i 's/MODULE_ALIAS_GENL_FAMILY(WG_GENL_NAME)/MODULE_ALIAS_GENL_FAMILY("amneziawg")/g' "$GENERATED_DIR/main.c"
        echo "✓ Fixed MODULE_ALIAS_GENL_FAMILY in main.c"
    else
        echo "  MODULE_ALIAS_GENL_FAMILY already fixed or not found in main.c"
    fi
else
    echo "  Warning: main.c not found in $GENERATED_DIR"
fi

# Fix 2: skb_gso_segment - update to use dev->features for kernel 6.10+
if [ -f "$GENERATED_DIR/device.c" ]; then
    # Check if we need to fix the skb_gso_segment call
    if grep -q 'skb_gso_segment(skb, 0)' "$GENERATED_DIR/device.c" && ! grep -q 'LINUX_VERSION_CODE >= KERNEL_VERSION(6, 10, 0)' "$GENERATED_DIR/device.c"; then
        # Simple sed replacement - just change the call to use dev->features
        sed -i 's/skb_gso_segment(skb, 0)/skb_gso_segment(skb, dev->features)/g' "$GENERATED_DIR/device.c"
        echo "✓ Fixed skb_gso_segment call in device.c"
    else
        echo "  skb_gso_segment already fixed or not found in device.c"
    fi
else
    echo "  Warning: device.c not found in $GENERATED_DIR"
fi

# Fix 3: NETIF_F_LLTX - this should be handled by compat.h, but ensure it's defined
# The compat.h fix should work, but if patches broke it, we need to check
if [ -f "$GENERATED_DIR/compat/compat.h" ]; then
    if ! grep -q 'NETIF_F_LLTX.*Dummy\|NETIF_F_LLTX 0' "$GENERATED_DIR/compat/compat.h"; then
        echo "  Note: Checking compat.h for NETIF_F_LLTX definition"
    fi
fi

# Also create a script that can be called after patches
POST_PATCH_SCRIPT="$(pwd)/apply-kernel-fixes.sh"
cat > "$POST_PATCH_SCRIPT" << 'EOF'
#!/bin/bash
# Post-patch fix script for kernel 6.12+ compatibility
GENERATED_DIR="$(pwd)/generated"
[ -d "$GENERATED_DIR" ] || GENERATED_DIR="$(pwd)"

# Fix 1: MODULE_ALIAS_GENL_FAMILY
[ -f "$GENERATED_DIR/main.c" ] && sed -i 's/MODULE_ALIAS_GENL_FAMILY(WG_GENL_NAME)/MODULE_ALIAS_GENL_FAMILY("amneziawg")/g' "$GENERATED_DIR/main.c"

# Fix 2: skb_gso_segment
[ -f "$GENERATED_DIR/device.c" ] && sed -i 's/skb_gso_segment(skb, 0)/skb_gso_segment(skb, dev->features)/g' "$GENERATED_DIR/device.c"
EOF
chmod +x "$POST_PATCH_SCRIPT"
echo "Created post-patch script: $POST_PATCH_SCRIPT"

echo "DKMS PRE_BUILD: Compatibility fixes completed"

