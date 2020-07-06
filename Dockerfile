ARG NGINX_VERSION=1.16.1
ARG NGINX_RTMP_VERSION=23ec4ce2d769830124abf3be1353dd9b105ab09c
ARG FFMPEG_VERSION=4.3
ARG NV_CODEC_VERSION=n9.1.23.1


##############################
# Build the NGINX-build image.
FROM nvidia/cuda:10.2-devel as build-nginx
ARG NGINX_VERSION
ARG NGINX_RTMP_VERSION

# Build dependencies.
RUN apt update && apt install -y \
  ca-certificates \
  curl \
  gcc \
  libc-dev \
  make \
  libssl-dev \
  libpcre3 \
  libpcre3-dev \
  linux-headers-$(uname -r) \
  pkg-config \
  wget \
  zlib1g-dev

# Get nginx source.
RUN cd /tmp && \
  wget https://nginx.org/download/nginx-${NGINX_VERSION}.tar.gz && \
  tar zxf nginx-${NGINX_VERSION}.tar.gz && \
  rm nginx-${NGINX_VERSION}.tar.gz

# Get nginx-rtmp module.
RUN cd /tmp && \
  wget https://github.com/sergey-dryabzhinsky/nginx-rtmp-module/archive/${NGINX_RTMP_VERSION}.tar.gz && \
  tar zxf ${NGINX_RTMP_VERSION}.tar.gz && rm ${NGINX_RTMP_VERSION}.tar.gz

# Compile nginx with nginx-rtmp module.
RUN cd /tmp/nginx-${NGINX_VERSION} && \
  ./configure \
  --prefix=/usr/local/nginx \
  --add-module=/tmp/nginx-rtmp-module-${NGINX_RTMP_VERSION} \
  --conf-path=/etc/nginx/nginx.conf \
  --with-threads \
  --with-file-aio \
  --with-http_ssl_module \
  --with-debug \
  --with-cc-opt="-Wimplicit-fallthrough=0" && \
  cd /tmp/nginx-${NGINX_VERSION} && make -j4 && make install

###############################
# Build the FFmpeg-build image.
FROM nvidia/cuda:10.2-devel as build-ffmpeg
ARG FFMPEG_VERSION
ARG PREFIX=/usr/local
ARG NV_CODEC_VERSION

# FFmpeg build dependencies.
RUN apt update && apt install -y \
  autoconf \
  automake \
  build-essential \
  coreutils \
  cmake \
  git-core \
  libass-dev \
  libfreetype6-dev \
  libgnutls28-dev \
  libfdk-aac-dev \
  libmp3lame-dev \
  libnuma-dev \
  libogg-dev \
  libopus-dev \
  libsdl2-dev \
  libssl-dev \
  libtheora-dev \
  libtool \
  libva-dev \
  libvdpau-dev \
  libvorbis-dev \
  libvpx-dev \
  libwebp-dev \
  libx264-dev \
  libx265-dev \
  nasm \
  pkg-config \
  texinfo \
  wget \
  yasm \
  zlib1g-dev

RUN git clone https://git.videolan.org/git/ffmpeg/nv-codec-headers.git && \
  cd nv-codec-headers && \
  git checkout ${NV_CODEC_VERSION} && \
  make && \
  make install

# Get FFmpeg source.
RUN cd /tmp/ && \
  wget http://ffmpeg.org/releases/ffmpeg-${FFMPEG_VERSION}.tar.gz && \
  tar zxf ffmpeg-${FFMPEG_VERSION}.tar.gz && rm ffmpeg-${FFMPEG_VERSION}.tar.gz

# Compile ffmpeg.
RUN cd /tmp/ffmpeg-${FFMPEG_VERSION} && \
  ./configure \
  --prefix=${PREFIX} \
  --enable-version3 \
  --enable-gpl \
  --enable-nonfree \
  --enable-small \
  --enable-libmp3lame \
  --enable-libx264 \
  --enable-libx265 \
  --enable-libvpx \
  --enable-libtheora \
  --enable-libvorbis \
  --enable-libopus \
  --enable-libfdk-aac \
  --enable-libass \
  --enable-libwebp \
  --enable-postproc \
  --enable-avresample \
  --enable-libfreetype \
  --enable-openssl \
  --enable-nvenc \
  --enable-cuda \
  --enable-cuvid \
  --extra-cflags=-I/usr/local/cuda/include \
  --extra-ldflags=-L/usr/local/cuda/lib64 \
  --disable-debug \
  --disable-doc \
  --disable-ffplay \
  --extra-libs="-lpthread -lm" && \
  make -j4 && make install && make distclean

# Cleanup.
RUN rm -rf /var/cache/* /tmp/*

##########################
# Build the release image.
FROM nvidia/cuda:10.2-base
LABEL MAINTAINER Marc Khouri <github@khouri.ca>

# Set default ports.
ENV HTTP_PORT 80
ENV HTTPS_PORT 443
ENV RTMP_PORT 1935

RUN apt update && apt install -y \
  ca-certificates \
  gettext \
  openssl \
  lame \
  libogg0 \
  curl \
  libass9 \
  libasound2 \
  libfdk-aac1 \
  libsdl2-2.0-0 \
  libsndio6.1 \
  libva2 \
  libvpx5 \
  libvorbis0a \
  libwebp6 \
  libtheora0 \
  libopus0 \
  libpcre3 \
  libxcb-shape0 \
  libxcb-xfixes0 \
  libxv1 \
  libva-drm2 \
  libva-x11-2 \
  libvdpau1 \
  libwebpmux3 \
  rtmpdump \
  libx264-dev \
  libx265-dev

COPY --from=build-nginx /usr/local/nginx /usr/local/nginx
COPY --from=build-nginx /etc/nginx /etc/nginx
COPY --from=build-ffmpeg /usr/local /usr/local

# Add NGINX path, config and static files.
ENV PATH "${PATH}:/usr/local/nginx/sbin"
ADD nginx.conf /etc/nginx/nginx.conf.template
RUN mkdir -p /opt/data && mkdir /www
ADD static /www/static

EXPOSE 1935
EXPOSE 80

CMD envsubst "$(env | sed -e 's/=.*//' -e 's/^/\$/g')" < \
  /etc/nginx/nginx.conf.template > /etc/nginx/nginx.conf && \
  nginx
