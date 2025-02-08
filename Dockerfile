# Base container that is used for both building and running the app
FROM registry.astralinux.ru/astra/ubi18 as base
ARG NODEJS_VERSION="18"
ENV FOREMAN_FQDN=foreman.example.com
ENV FOREMAN_DOMAIN=example.com

RUN \
  apt update -y && \
  apt install -y nodejs && \
  apt install -y postgresql-server-dev-all postgresql-server-dev-15 \
      ruby ruby-rubygems rake bundler npm netcat-openbsd hostname 

ARG HOME=/home/foreman
WORKDIR $HOME
ARG UID=1001
ARG GID=1001
# add our user and group first to make sure their IDs get assigned consistently, regardless of whatever dependencies get added
RUN groupadd -r foreman -g ${GID} && useradd -u ${UID} -c "systemuser for foreman application" -r -g foreman foreman -d ${HOME}
RUN usermod -aG root foreman
# Add a script to be executed every time the container starts.
COPY extras/containers/entrypoint.sh /usr/bin/
RUN chmod +x /usr/bin/entrypoint.sh
ENTRYPOINT ["entrypoint.sh"]

# Temp container that download gems/npms and compile assets etc
FROM base as builder
ENV RAILS_ENV=production
ENV FOREMAN_APIPIE_LANGS=en
ENV BUNDLER_SKIPPED_GROUPS="test development openid libvirt journald facter console"

RUN \
  apt update && apt install -y devscripts \
    gcc cpp make bzip2 gettext tar \
    libxml2-dev libcurl4-openssl-dev ruby-dev \
    postgresql-server-dev-all postgresql-server-dev-15 \
    libyaml-dev
ENV DATABASE_URL=nulldb://nohost

ARG HOME=/home/foreman
USER 0
WORKDIR $HOME
COPY --chown=1001:1001 . ${HOME}/
RUN bundle config set --local without "${BUNDLER_SKIPPED_GROUPS}" && \
  bundle config set --local clean true && \
  bundle config set --local path vendor && \
  bundle config set --local jobs 5 && \
  bundle config set --local retry 3
RUN bundle install && \
  bundle binstubs --all && \
  rm -rf vendor/ruby/*/cache/*.gem && \
  find vendor/ruby/*/gems -name "*.c" -delete && \
  find vendor/ruby/*/gems -name "*.o" -delete
RUN \
  make -C locale all-mo && \
  mv -v db/schema.rb.nulldb db/schema.rb && \
  bundle exec rake assets:clean assets:precompile

RUN npm install --no-audit --no-optional && \
  ./node_modules/webpack/bin/webpack.js --config config/webpack.config.js && \
# cleanups
  rm -rf public/webpack/stats.json ./node_modules vendor/ruby/*/cache vendor/ruby/*/gems/*/node_modules bundler.d/nulldb.rb db/schema.rb && \
  bundle config without "${BUNDLER_SKIPPED_GROUPS} assets" && \
  bundle install

USER 0
RUN chgrp -R 1001 ${HOME} && \
    chmod -R g=u ${HOME}

USER 1001

FROM base

USER 0
RUN chgrp -R 1001 ${HOME} && \
    chmod -R g=u ${HOME}
USER 1001
ARG HOME=/home/foreman
ENV RAILS_ENV=production
ENV RAILS_SERVE_STATIC_FILES=true
ENV RAILS_LOG_TO_STDOUT=true

USER 1001
WORKDIR ${HOME}
COPY --chown=1001:1001 . ${HOME}/
COPY --from=builder /usr/bin/entrypoint.sh /usr/bin/entrypoint.sh
COPY --from=builder --chown=1001:1001 ${HOME}/.bundle/config ${HOME}/.bundle/config
COPY --from=builder --chown=1001:1001 ${HOME}/Gemfile.lock ${HOME}/Gemfile.lock
COPY --from=builder --chown=1001:1001 ${HOME}/vendor/ruby ${HOME}/vendor/ruby
COPY --from=builder --chown=1001:1001 ${HOME}/public ${HOME}/public
RUN rm -rf bundler.d/nulldb.rb bin/spring

#RUN date -u > BUILD_TIME

# Start the main process.
CMD bundle exec bin/rails server

EXPOSE 3000/tcp
EXPOSE 5910-5930/tcp
