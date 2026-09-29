#!/bin/bash
#
# upload-appstore.sh - archive Glass Bead Game III (Graph) and upload it to App Store Connect.
#
# Archives the "Glass Bead Game III" scheme (never Seq) for iPad and/or Mac, exports each with
# App Store distribution signing, and uploads it with an App Store Connect API key. Once
# processed (usually 5-30 min), the build shows up in TestFlight, ready to test or submit.
#
# Run it from a session that can sign: Terminal.app, or an SSH/Termius session after unlocking
# the login keychain (the script offers to do that). Claude Code's own shell can't sign.
#
# ONE-TIME SETUP
#   1. App Store Connect: create the app record (both iOS and macOS platforms) with bundle ID
#      com.sohl.norm.Glass-Bead-Game-III. An upload fails without it.
#   2. App Store Connect > Users and Access > Integrations > App Store Connect API: generate a
#      Team key with the "Admin" role and download AuthKey_<KEYID>.p8 (only downloadable once).
#      Put it in ~/.appstoreconnect/private_keys/ and chmod 600 it. Admin rather than App
#      Manager because this Mac has no Apple Distribution certificate (only Apple Development),
#      so export relies on Xcode's cloud-managed distribution signing, which needs Admin.
#      Alternative: create an Apple Distribution certificate once in Xcode > Settings >
#      Accounts > Manage Certificates, and App Manager is enough. A --dry-run (no key) also
#      needs that local certificate to export.
#   3. Note the Key ID and the Issuer ID shown on that page, and export them (e.g. in ~/.zshrc):
#        export ASC_KEY_ID=XXXXXXXXXX
#        export ASC_ISSUER_ID=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
#      The key file defaults to ~/.appstoreconnect/private_keys/AuthKey_$ASC_KEY_ID.p8;
#      set ASC_KEY_PATH to override.
#
# USAGE
#   scripts/upload-appstore.sh [--platform ios|macos|both] [--build N] [--dry-run] [--no-unlock]
#
#   --platform   What to ship (default: both).
#   --build      Build number (CFBundleVersion). Default: the git commit count, so it rises with
#                every commit. Each upload needs a higher number than the last for that version;
#                pass --build to re-upload the same commit.
#   --dry-run    Archive and export the signed app/package locally, but don't upload. Useful to
#                check signing before the app record or API key exists.
#   --no-unlock  Skip the keychain unlock prompt (already unlocked in this session).
#
# Output goes to build/release/<build>/ (archives, exported .ipa/.pkg, logs).

set -euo pipefail

SCHEME="Glass Bead Game III"
PROJECT="Glass Bead Game III.xcodeproj"
BUNDLE_ID="com.sohl.norm.Glass-Bead-Game-III"

PLATFORM="both"
BUILD_NUMBER=""
DRY_RUN=0
UNLOCK=1

die() { echo "error: $*" >&2; exit 1; }

while [[ $# -gt 0 ]]; do
    case "$1" in
        --platform) PLATFORM="${2:-}"; shift 2 ;;
        --build) BUILD_NUMBER="${2:-}"; shift 2 ;;
        --dry-run) DRY_RUN=1; shift ;;
        --no-unlock) UNLOCK=0; shift ;;
        -h|--help) sed -n '2,/^set -euo/p' "$0" | sed '$d' | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) die "unknown option: $1 (see --help)" ;;
    esac
done

case "$PLATFORM" in
    ios) PLATFORMS=(ios) ;;
    macos) PLATFORMS=(macos) ;;
    both) PLATFORMS=(ios macos) ;;
    *) die "--platform must be ios, macos, or both" ;;
esac

# Always run from the repo root, wherever the script was called from.
cd "$(dirname "$0")/.."
[[ -d "$PROJECT" ]] || die "can't find $PROJECT - run from inside the repo"

# --- Preflight -------------------------------------------------------------------------------

if [[ -n "$(git status --porcelain --untracked-files=no)" ]]; then
    echo "warning: uncommitted changes to tracked files - the upload will include them," >&2
    echo "         but they won't be in git. Commit first to keep builds reproducible." >&2
    read -r -p "Continue anyway? [y/N] " answer
    [[ "$answer" == [yY]* ]] || exit 1
fi

[[ -n "$BUILD_NUMBER" ]] || BUILD_NUMBER="$(git rev-list --count HEAD)"
[[ "$BUILD_NUMBER" =~ ^[0-9]+$ ]] || die "--build must be a whole number"

AUTH_ARGS=()
if [[ $DRY_RUN -eq 0 ]]; then
    [[ -n "${ASC_KEY_ID:-}" ]] || die "ASC_KEY_ID not set (see ONE-TIME SETUP in this script)"
    [[ -n "${ASC_ISSUER_ID:-}" ]] || die "ASC_ISSUER_ID not set (see ONE-TIME SETUP in this script)"
    ASC_KEY_PATH="${ASC_KEY_PATH:-$HOME/.appstoreconnect/private_keys/AuthKey_${ASC_KEY_ID}.p8}"
    [[ -f "$ASC_KEY_PATH" ]] || die "API key not found at $ASC_KEY_PATH"
    AUTH_ARGS=(-authenticationKeyPath "$ASC_KEY_PATH"
               -authenticationKeyID "$ASC_KEY_ID"
               -authenticationKeyIssuerID "$ASC_ISSUER_ID")
fi

# Signing needs the login keychain unlocked in *this* session - over SSH it usually isn't,
# which shows up as "errSecInternalComponent" at the CodeSign step.
if [[ $UNLOCK -eq 1 ]]; then
    echo "Unlocking the login keychain for signing (your Mac login password):"
    security unlock-keychain "$HOME/Library/Keychains/login.keychain-db"
fi

OUT="build/release/$BUILD_NUMBER"
mkdir -p "$OUT"

VERSION="$(xcodebuild -project "$PROJECT" -scheme "$SCHEME" -configuration Release -showBuildSettings 2>/dev/null \
    | awk -F' = ' '/^ *MARKETING_VERSION = /{print $2; exit}')"
echo
echo "Glass Bead Game III $VERSION (build $BUILD_NUMBER) - ${PLATFORMS[*]}"
[[ $DRY_RUN -eq 1 ]] && echo "Dry run: archive and export only, no upload."
echo "Output: $OUT"
echo

# --- Archive, export, upload -----------------------------------------------------------------

# destination=upload makes -exportArchive send the build straight to App Store Connect;
# "export" just writes the signed .ipa/.pkg locally (dry run).
EXPORT_PLIST="$OUT/ExportOptions.plist"
cat > "$EXPORT_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>app-store-connect</string>
    <key>destination</key>
    <string>$([[ $DRY_RUN -eq 1 ]] && echo export || echo upload)</string>
    <key>signingStyle</key>
    <string>automatic</string>
    <key>teamID</key>
    <string>342G7AUKSH</string>
    <key>manageAppVersionAndBuildNumber</key>
    <false/>
    <key>uploadSymbols</key>
    <true/>
</dict>
</plist>
PLIST

run_logged() {
    # Runs a command with full output in a log file and only the useful lines on screen.
    local log="$1"; shift
    if "$@" > "$log" 2>&1; then
        grep -E 'SUCCEEDED|Uploaded|Exported|Progress' "$log" | tail -3 || true
    else
        grep -E 'error:|errSec|FAILED|No profiles|No signing certificate|Error Domain' "$log" | head -20 >&2 || true
        die "failed - full log: $log"
    fi
}

for platform in "${PLATFORMS[@]}"; do
    case "$platform" in
        ios)   destination="generic/platform=iOS";   label="iPad" ;;
        macos) destination="generic/platform=macOS"; label="Mac" ;;
    esac
    archive="$OUT/GlassBeadGameIII-$platform.xcarchive"

    echo "== $label: archiving"
    run_logged "$OUT/archive-$platform.log" \
        xcodebuild archive \
            -project "$PROJECT" -scheme "$SCHEME" -configuration Release \
            -destination "$destination" -archivePath "$archive" \
            -allowProvisioningUpdates ${AUTH_ARGS[@]+"${AUTH_ARGS[@]}"} \
            CURRENT_PROJECT_VERSION="$BUILD_NUMBER"

    echo "== $label: $([[ $DRY_RUN -eq 1 ]] && echo exporting || echo 'exporting and uploading')"
    run_logged "$OUT/export-$platform.log" \
        xcodebuild -exportArchive \
            -archivePath "$archive" -exportPath "$OUT/export-$platform" \
            -exportOptionsPlist "$EXPORT_PLIST" \
            -allowProvisioningUpdates ${AUTH_ARGS[@]+"${AUTH_ARGS[@]}"}
    echo
done

if [[ $DRY_RUN -eq 1 ]]; then
    echo "Done. Signed builds are in $OUT/export-*/ - nothing was uploaded."
else
    echo "Done. Build $BUILD_NUMBER is uploaded for ${PLATFORMS[*]}."
    echo "App Store Connect emails you when processing finishes; it then appears in TestFlight."
fi
