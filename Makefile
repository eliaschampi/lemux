# lemux — install with:  make install            (system-wide, /usr/local)
#                        make install PREFIX=~/.local
PREFIX  ?= /usr/local
DESTDIR ?=
BINDIR   = $(DESTDIR)$(PREFIX)/bin
LIBDIR   = $(DESTDIR)$(PREFIX)/lib/lemux
MANDIR   = $(DESTDIR)$(PREFIX)/share/man/man1
SHAREDIR = $(DESTDIR)$(PREFIX)/share
VERSION := $(shell sed -n 's/^LEMUX_VERSION="\(.*\)"/\1/p' lib/lemux/core.sh)

ARCHIVE   = lemux-$(VERSION).tar.gz
INSTALLER = dist/install.sh

.PHONY: all install uninstall test lint check dist installer

all:
	@echo "lemux $(VERSION): make install [PREFIX=~/.local] | make test | make lint"

install:
	install -Dm755 bin/lemux "$(BINDIR)/lemux"
	install -d "$(LIBDIR)"
	install -m644 lib/lemux/*.sh "$(LIBDIR)/"
	install -Dm644 man/lemux.1 "$(MANDIR)/lemux.1"
	install -Dm644 completions/lemux.bash "$(SHAREDIR)/bash-completion/completions/lemux"
	install -Dm644 completions/_lemux "$(SHAREDIR)/zsh/site-functions/_lemux"
	install -Dm644 completions/lemux.fish "$(SHAREDIR)/fish/vendor_completions.d/lemux.fish"

uninstall:
	rm -f "$(BINDIR)/lemux" "$(MANDIR)/lemux.1" \
	  "$(SHAREDIR)/bash-completion/completions/lemux" \
	  "$(SHAREDIR)/zsh/site-functions/_lemux" \
	  "$(SHAREDIR)/fish/vendor_completions.d/lemux.fish"
	rm -rf "$(LIBDIR)"

test:
	bats tests

lint:
	shellcheck -x bin/lemux lib/lemux/*.sh completions/lemux.bash scripts/install.sh

check: lint test

dist:
	git archive --format=tar.gz --prefix=lemux-$(VERSION)/ -o "$(ARCHIVE)" v$(VERSION)

# Render from the exact archive that will be uploaded to the release.
installer:
	@set -e; out="$(INSTALLER)"; parent=$$(dirname -- "$$out"); \
	  sum=$$(sha256sum <"$(ARCHIVE)"); digest=$${sum%% *}; \
	  mkdir -p -- "$$parent"; temporary=$$(mktemp -- "$$parent/.lemux-installer.XXXXXXXX"); \
	  trap 'rm -f -- "$$temporary"' EXIT; \
	  chmod 644 -- "$$temporary"; \
	  sed -e 's/@RELEASE_VERSION@/$(VERSION)/g' -e "s/@RELEASE_SHA256@/$$digest/g" \
	    scripts/install.sh >"$$temporary"; \
	  mv -fT -- "$$temporary" "$$out"
