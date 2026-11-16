# Reproducible Linux build environment for Finder (x64 or arm64, matching
# the Docker host). Ubuntu 22.04 keeps the glibc baseline low (2.35), so the
# packages run on most current distributions.
#
#   docker build -t finder-linux packaging/linux
#   docker run --rm -v "$PWD":/src:ro -v "$PWD/build/release":/out finder-linux
FROM ubuntu:22.04
ARG FLUTTER_VERSION=3.47.9
ENV DEBIAN_FRONTEND=noninteractive
# Optional: networks that inspect HTTPS can drop their root CA(s) next to this
# Dockerfile as extra-ca*.crt (git-ignored). `Dockerfile` is listed so the COPY
# never matches nothing.
COPY Dockerfile extra-ca*.crt /tmp/ca/
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates \
  && for f in /tmp/ca/*.crt; do [ -e "$f" ] && cp "$f" /usr/local/share/ca-certificates/; done; \
  update-ca-certificates && rm -rf /tmp/ca
ENV SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt
RUN apt-get update && apt-get install -y --no-install-recommends \
      curl git unzip xz-utils zip file rsync \
      clang cmake ninja-build pkg-config libgtk-3-dev liblzma-dev libstdc++-12-dev \
      dpkg-dev rpm imagemagick desktop-file-utils \
  && rm -rf /var/lib/apt/lists/*
RUN git clone --depth 1 --branch ${FLUTTER_VERSION} https://github.com/flutter/flutter.git /opt/flutter
ENV PATH=/opt/flutter/bin:/opt/flutter/bin/cache/dart-sdk/bin:$PATH
RUN git config --global --add safe.directory /opt/flutter \
  && flutter config --no-analytics --enable-linux-desktop \
  && flutter precache --linux
# Copies the read-only source to a scratch tree (so the host's .dart_tool and
# build folders are never touched), packages it, and exports the results.
CMD rsync -a --exclude build --exclude .dart_tool --exclude third_party/windows \
      --exclude third_party/macos /src/ /work/ \
  && cd /work && flutter pub get && tool/package_linux.sh \
  && cp build/release/*linux* /out/
