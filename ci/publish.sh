#!/usr/bin/env bash
# Publishes the tagged version: the tag to github.com/auvious/auvious-sdk-ios (the podspec's
# source), then the podspec to the spec repo github.com/auvious/CocoaPodSpecs, committed as
# `pod repo push` would. Not with `pod repo push` itself: its lint builds the pod without the
# Example Podfile's post_install, and Xcode 27 refuses the dependencies' iOS 11-13 targets
# (Sentry, SwiftyJSON, the _IOS13 pods), with no option to raise them. The build and tests of
# this commit are build-example and test-sdk, which the job needs; here the lint is --quick.
# Needs GITHUB_TOKEN with Contents write access to both repos.
# Safe to retry: the same tag on GitHub and the same podspec in the spec repo count as done.
set -euo pipefail

: "${GITHUB_TOKEN:?set GITHUB_TOKEN (write access to auvious/auvious-sdk-ios and auvious/CocoaPodSpecs)}"
: "${CI_COMMIT_TAG:?run on a tag}"
SDK_URL="${SDK_REPO_URL:-https://github.com/auvious/auvious-sdk-ios.git}"
SPECS_URL="${SPECS_REPO_URL:-https://github.com/auvious/CocoaPodSpecs.git}"
VERSION="$CI_COMMIT_TAG"
SPEC="$PWD/AuviousSDK.podspec"
export PATH="/opt/homebrew/bin:$PATH" LANG=en_US.UTF-8
grep -qE "s\.version *= '$VERSION'" "$SPEC" ||
  { echo "AuviousSDK.podspec's s.version is not $VERSION: tag the commit that sets it" >&2; exit 1; }

# A CocoaPods home of its own: a fresh clone of the spec repo, nothing left on the Mac.
CP_HOME_DIR=$(mktemp -d) && export CP_HOME_DIR
trap 'rm -rf "$CP_HOME_DIR"' EXIT
# The token reaches git through the environment only: not in a URL, a file or
# a command line (printf is a builtin). No credential helpers or prompts: if the
# token is refused, the push fails rather than using a login saved on the Mac.
GIT_CONFIG_VALUE_0="Authorization: Basic $(printf 'x-access-token:%s' "$GITHUB_TOKEN" | base64 | tr -d '\n')"
export GIT_CONFIG_COUNT=2 GIT_CONFIG_KEY_0=http.https://github.com/.extraheader GIT_CONFIG_VALUE_0 \
  GIT_CONFIG_KEY_1=credential.helper GIT_CONFIG_VALUE_1= GIT_TERMINAL_PROMPT=0
# Commits as whoever started the pipeline.
if [ -n "${GITLAB_USER_EMAIL:-}" ]; then
  export GIT_AUTHOR_NAME="$GITLAB_USER_NAME" GIT_AUTHOR_EMAIL="$GITLAB_USER_EMAIL"
  export GIT_COMMITTER_NAME="$GITLAB_USER_NAME" GIT_COMMITTER_EMAIL="$GITLAB_USER_EMAIL"
fi

pod repo add auvious "$SPECS_URL" ||
  { echo "cannot clone $SPECS_URL (GITHUB_TOKEN expired or without access?)" >&2; exit 1; }
EXISTING="$CP_HOME_DIR/repos/auvious/AuviousSDK/$VERSION/AuviousSDK.podspec"
if [ -e "$EXISTING" ] && ! cmp -s "$EXISTING" "$SPEC"; then
  echo "AuviousSDK $VERSION is already in the spec repo with other content; tag a new version" >&2
  exit 1
fi

# Its dependencies come from the spec repo (AuviousGoogleWebRTC, the _IOS13 pods) and trunk.
pod spec lint "$SPEC" --quick --allow-warnings --sources="$SPECS_URL,https://cdn.cocoapods.org/"

# Write access to both repos before anything is pushed: a dry-run push asks GitHub for
# git-receive-pack, which it only grants with write access, and sends nothing.
git push --dry-run --quiet "$SDK_URL" "$CI_COMMIT_SHA:refs/tags/$VERSION" ||
  { echo "GITHUB_TOKEN cannot push to $SDK_URL (or tag $VERSION is there on another commit)" >&2; exit 1; }
git -C "$CP_HOME_DIR/repos/auvious" push --dry-run --quiet origin HEAD ||
  { echo "GITHUB_TOKEN cannot push to $SPECS_URL" >&2; exit 1; }

# GitHub may lack this tag's history, which a shallow clone can't send.
if [ "$(git rev-parse --is-shallow-repository)" = true ]; then git fetch --quiet --unshallow origin; fi
# Not forced: a tag already on GitHub on another commit is refused.
git push "$SDK_URL" "$CI_COMMIT_SHA:refs/tags/$VERSION"

if [ -e "$EXISTING" ]; then
  echo "AuviousSDK $VERSION is already in the spec repo with this content"; exit 0
fi
REPO="$CP_HOME_DIR/repos/auvious"
mkdir -p "$REPO/AuviousSDK/$VERSION"
cp "$SPEC" "$EXISTING"
git -C "$REPO" add "AuviousSDK/$VERSION/AuviousSDK.podspec"
git -C "$REPO" commit --quiet -m "[Add] AuviousSDK ($VERSION)"
git -C "$REPO" push --quiet origin HEAD
echo "Published AuviousSDK $VERSION"
