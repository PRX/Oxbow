# FROM public.ecr.aws/amazonlinux/amazonlinux:2023

# RUN dnf update -y \
#     && dnf install -y wget tar xz nscd \
#     && dnf install -y ruby3.2

# See https://docs.aws.amazon.com/linux/al2023/release-notes/all-packages.html
# to figure out which specific version of Ruby is installed using the ruby3.2
# package.

FROM lscr.io/linuxserver/ffmpeg:latest

RUN apt-get update && \
    apt-get install -y \
    ruby-full \
    build-essential

ENV APP_HOME /ffmpeg
RUN mkdir -p $APP_HOME
WORKDIR $APP_HOME

# RUN wget https://johnvansickle.com/ffmpeg/builds/ffmpeg-git-amd64-static.tar.xz
# RUN tar xvJf ffmpeg-git-amd64-static.tar.xz
# RUN mkdir -p ffmpeg-bin
# RUN mv ffmpeg-git-*-amd64-static/ffmpeg ffmpeg-bin/
# RUN mv ffmpeg-git-*-amd64-static/ffprobe ffmpeg-bin/

ADD Gemfile .
ADD Gemfile.lock .
RUN gem install bundler
RUN bundle install

ADD ffmpeg.rb .
RUN chmod +x ./ffmpeg.rb

ENTRYPOINT ["./ffmpeg.rb"]
