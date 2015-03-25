FROM base/archlinux
MAINTAINER Paolo Galeone <nessuno@nerdz.eu>

RUN sed -i -e 's#https://mirrors\.kernel\.org#http://mirror.clibre.uqam.ca#g' /etc/pacman.d/mirrorlist && \
       pacman -Sy  wget base-devel nginx libunistring --noconfirm

COPY builder /opt/
RUN bash /opt/builder

VOLUME ["/etc/nginx", "/srv/http"]

EXPOSE 80 443

ENTRYPOINT /usr/bin/nginx -g 'daemon off;'
