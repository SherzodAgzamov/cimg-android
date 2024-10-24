#!/bin/bash

echo "Initializing submodule..."
git submodule update --init --recursive
cd shared || exit && \
git checkout main
if [ -f automated-updates.sh ]; then
  source automated-updates.sh
else
  echo "Check if submodule was loaded; automated-updates.sh is missing"
  exit 1
fi
cd ..

generateDatedTags
RELEASE=$RELEASE.1

git checkout -b "release-v$RELEASE"

sdkmanager --update

CLT_VERSION=$(curl -s https://developer.android.com/studio#command-line-tools-only | grep "commandlinetools-linux" | grep -o '[0-9]\+'| tr -d '[:blank:]' | head -1)
echo "Command Line Tools version: $CLT_VERSION"

# keep on top of the latest gcloud CLI updates rather than relying on the in-use tag for the build
gcloud components update --quiet

GCLOUD_VERSION=$(gcloud version | head -1 | sed 's/[^0-9.]//g')
echo "Gcloud version: $GCLOUD_VERSION"

GRADLE_VERSION=$(curl --silent "https://api.github.com/repos/gradle/gradle/releases/latest" | jq -r .name | sed 's/^[^0-9]*//')
echo "Gradle version: $GRADLE_VERSION"

MAVEN_VERSION=$(curl --silent "https://api.github.com/repos/apache/maven/releases/latest" | jq -r .tag_name | sed 's/^[^0-9]*//')
echo "Maven version: $MAVEN_VERSION"

FASTLANE_VERSION=$(curl --silent "https://api.github.com/repos/fastlane/fastlane/releases/latest" | jq -r .tag_name)
echo "Fastlane version: $FASTLANE_VERSION"

BUILD_TOOLS_VERSIONS=$(sdkmanager --list | grep "build-tools" | awk -F';' '{print $2}' | awk -F'|' '{print $1}' | sort -t. -k1,1n -k2,2n -k3,3 -k4 -s | awk -F. '!seen[$1"."$2"-"$3]++' | sort -t. -Vr | awk -F. '!seen[$1]++' | tr -d '[:blank:]' | head -n 3)

readarray -t BUILD_TOOLS_ARRAY <<< "$BUILD_TOOLS_VERSIONS"

PLATFORMS=$(sdkmanager --list | grep "platforms;android" | cut -d'|' -f1 | grep -v 'Sandbox' | grep -v 'ext' | sort -t- -nk2 | tr -d '[:blank:]' | awk -F- '!seen[$NF]++' | tail -7)

readarray -t PLATFORMS_ARRAY <<< "$PLATFORMS"

sed -i '38c\ENV MAVEN_VERSION='"$MAVEN_VERSION"'' Dockerfile.template
sed -i '44c\ENV GRADLE_VERSION='"$GRADLE_VERSION"'' Dockerfile.template
sed -i '58c\RUN SDK_TOOLS_URL="https://dl.google.com/android/repository/commandlinetools-linux-'"$CLT_VERSION"'_latest.zip" && \\' Dockerfile.template
sed -i '69c\    echo y | ${CMDLINE_TOOLS_ROOT}/sdkmanager "build-tools;'"${BUILD_TOOLS_ARRAY[0]}"'" && \\' Dockerfile.template
sed -i '70c\    echo y | ${CMDLINE_TOOLS_ROOT}/sdkmanager "build-tools;'"${BUILD_TOOLS_ARRAY[1]}"'" && \\' Dockerfile.template
sed -i '71c\    echo y | ${CMDLINE_TOOLS_ROOT}/sdkmanager "build-tools;'"${BUILD_TOOLS_ARRAY[2]}"'"' Dockerfile.template
sed -i '72c\RUN echo y | ${CMDLINE_TOOLS_ROOT}/sdkmanager "'"${PLATFORMS_ARRAY[0]}"'" && \\' Dockerfile.template
sed -i '73c\    echo y | ${CMDLINE_TOOLS_ROOT}/sdkmanager "'"${PLATFORMS_ARRAY[1]}"'" && \\' Dockerfile.template
sed -i '74c\    echo y | ${CMDLINE_TOOLS_ROOT}/sdkmanager "'"${PLATFORMS_ARRAY[2]}"'" && \\' Dockerfile.template
sed -i '75c\    echo y | ${CMDLINE_TOOLS_ROOT}/sdkmanager "'"${PLATFORMS_ARRAY[3]}"'" && \\' Dockerfile.template
sed -i '76c\    echo y | ${CMDLINE_TOOLS_ROOT}/sdkmanager "'"${PLATFORMS_ARRAY[4]}"'" && \\' Dockerfile.template
sed -i '77c\    echo y | ${CMDLINE_TOOLS_ROOT}/sdkmanager "'"${PLATFORMS_ARRAY[5]}"'" && \\' Dockerfile.template
sed -i '78c\    echo y | ${CMDLINE_TOOLS_ROOT}/sdkmanager "'"${PLATFORMS_ARRAY[6]}"'"' Dockerfile.template
sed -i '84c\    sudo gem install fastlane --version '"$FASTLANE_VERSION"' --no-document && \\' Dockerfile.template
sed -i '89c\ENV GCLOUD_VERSION='"$GCLOUD_VERSION"'-0' Dockerfile.template

CMAKE_VERS=$(sdkmanager --list | grep cmake | cut -d'|' -f1 | sort -Vr | tr -d '[:blank:]' | head -2)

readarray -t CMAKE_ARRAY <<< "$CMAKE_VERS"

NDK_VERS=$(sdkmanager --list | grep ndk | cut -d'|' -f1 | sort -Vr | tr -d '[:blank:]' | sed 's/ndk;//g' | awk -F. '!seen[$1"."]++' | head -2)

readarray -t NDK_ARRAY <<< "$NDK_VERS"
echo ${NDK_ARRAY[1]}

sed -i '7c\RUN echo y | ${CMDLINE_TOOLS_ROOT}/sdkmanager "'"${CMAKE_ARRAY[1]}"'" && \\' variants/ndk.Dockerfile.template
sed -i '8c\	echo y | ${CMDLINE_TOOLS_ROOT}/sdkmanager "'"${CMAKE_ARRAY[0]}"'"' variants/ndk.Dockerfile.template
sed -i '12c\ENV NDK_LTS_VERSION "'"${NDK_ARRAY[0]}"'"' variants/ndk.Dockerfile.template
sed -i '20c\ENV NDK_STABLE_VERSION "'"${NDK_ARRAY[1]}"'"' variants/ndk.Dockerfile.template


shared/gen-dockerfiles.sh "$RELEASE"
git add .
git commit -m "Publish v$RELEASE. [release]"
git push -u origin "release-v$RELEASE"
gh pr create --title "Publish v$RELEASE. [release]" --head "release-v$RELEASE" --body "Publish v$RELEASE. [release]"
