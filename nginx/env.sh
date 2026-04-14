#!/bin/sh
# ============================================================
# Runtime Environment Variable Injection
# Runs at container startup (before Nginx starts)
#
# HOW IT WORKS:
#   1. At build time, env vars are baked into the JS bundle
#   2. At runtime, this script injects a window.__ENV__ object
#      into index.html so runtime vars override build-time vars
#
# USAGE in React code:
#   const apiUrl = window.__ENV__?.REACT_APP_API_URL
#                  || process.env.REACT_APP_API_URL;
# ============================================================

set -e

TARGET="/usr/share/nginx/html/index.html"
RUNTIME_ENV_JS="/usr/share/nginx/html/runtime-env.js"

# Escape values for safe JS string insertion.
escape_js() {
    printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

API_URL_ESCAPED=$(escape_js "${REACT_APP_API_URL:-}")
VERSION_ESCAPED=$(escape_js "${REACT_APP_VERSION:-unknown}")
ENV_ESCAPED=$(escape_js "${NODE_ENV:-production}")

# Write runtime env into a dedicated JS file.
cat > "$RUNTIME_ENV_JS" <<EOF
window.__ENV__ = {
  REACT_APP_API_URL: "$API_URL_ESCAPED",
  REACT_APP_VERSION: "$VERSION_ESCAPED",
  REACT_APP_ENV: "$ENV_ESCAPED"
};
EOF

# Ensure index.html loads runtime-env.js before app scripts.
if ! grep -q '/runtime-env.js' "$TARGET"; then
    awk '
      /<\/head>/ && !done {
        print "    <script src=\"/runtime-env.js\"></script>"
        done=1
      }
      { print }
    ' "$TARGET" > "${TARGET}.tmp"
    mv "${TARGET}.tmp" "$TARGET"
fi

echo "Environment variables injected into index.html"
