# lemux — install with:  make install            (system-wide, /usr/local)
#                        make install PREFIX=~/.local
PREFIX  ?= /usr/local
DESTDIR ?=
BINDIR   = $(DESTDIR)$(PREFIX)/bin
LIBDIR   = $(DESTDIR)$(PREFIX)/lib/lemux
MANDIR   = $(DESTDIR)$(PREFIX)/share/man/man1
SHAREDIR = $(DESTDIR)$(PREFIX)/share
VERSION := $(shell sed -n 's/^LEMUX_VERSION="\(.*\)"/\1/p' lib/lemux/core.sh)

.PHONY: all install uninstall test lint check dist

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
	shellcheck -x bin/lemux lib/lemux/*.sh completions/lemux.bash

check: lint test

dist:
	git archive --format=tar.gz --prefix=lemux-$(VERSION)/ -o lemux-$(VERSION).tar.gz v$(VERSION)
