FROM base/archlinux
MAINTAINER Paolo Galeone <nessuno@nerdz.eu>

RUN sed -i -e 's#https://mirrors\.kernel\.org#http://mirror.clibre.uqam.ca#g' /etc/pacman.d/mirrorlist && pacman -Sy php \
       php-pgsql \
       php-pear \
       php-gd \
       php-fpm \
       php-composer \
       php-apcu \
       wget \
       git nodejs --noconfirm
RUN npm install uglify-js -g

COPY conf/php-fpm.conf /etc/php/
COPY conf/php.ini /etc/php/
RUN echo "extension=apcu.so" >  /etc/php/conf.d/apcu.ini

EXPOSE 9000

VOLUME /srv/http

COPY startup.sh /opt/

ENTRYPOINT bash /opt/startup.sh
