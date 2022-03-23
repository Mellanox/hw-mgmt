FROM alpine:3.10
LABEL "repository"="https://github.com/sholeksandr/hw-mgmt/"
LABEL "homepage"="https://github.com/sholeksandr/hw-mgmt/"
LABEL "maintainer"="Oleksandr S"

COPY version_tag.py /version_tag.py
RUN install ./version_tag.py /usr/local/bin

RUN apk update && apk add bash git curl jq python && apk add --update nodejs npm
COPY entrypoint_2.sh /entrypoint_2.sh
ENTRYPOINT ["/entrypoint_2.sh"]

