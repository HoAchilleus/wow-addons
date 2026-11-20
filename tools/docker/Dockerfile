# Lint and test environment, used both locally (scripts/check.ps1) and in CI,
# so results match. Lua 5.1 is the version WoW runs.
FROM alpine:3.20

RUN apk add --no-cache lua5.1 lua5.1-dev luarocks5.1 build-base git python3 py3-pytest \
	&& ln -s /usr/bin/luarocks-5.1 /usr/local/bin/luarocks \
	&& luarocks install busted 2.2.0-1 \
	&& luarocks install luacheck 1.2.0-1

WORKDIR /repo
