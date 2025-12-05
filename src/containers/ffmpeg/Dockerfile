FROM lscr.io/linuxserver/ffmpeg:latest

RUN apt-get update && \
    apt-get install -y \
    ruby-full \
    build-essential

RUN ruby -v

ENV APP_HOME=/ffmpeg
RUN mkdir -p $APP_HOME
WORKDIR $APP_HOME

ADD Gemfile .
ADD Gemfile.lock .
RUN gem install bundler
RUN bundle install

ADD ffmpeg.rb .
RUN chmod +x ./ffmpeg.rb

ENTRYPOINT ["./ffmpeg.rb"]
