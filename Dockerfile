FROM alpine:3.10
LABEL "repository"="https://github.com/sholeksandr/hw-mgmt/"
LABEL "homepage"="https://github.com/sholeksandr/hw-mgmt/"
LABEL "maintainer"="Oleksandr S"

COPY entrypoint2_.sh /entrypoint_2.sh

RUN apk update && apk add bash git curl jq python && apk add --update nodejs npm && npm install -g semver

ENTRYPOINT ["/entrypoint_2.sh"]

