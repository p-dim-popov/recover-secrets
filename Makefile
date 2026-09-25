# Builds the two root scripts from source/.
#   make        rebuild recover.sh and decrypt.sh after editing source/
#   make check  fail if the committed root scripts are out of date
#
# recover.sh is self-extracting: it writes the source files into a temporary
# directory with quoted heredocs and runs main.sh from there, so the files in
# source/ stay runnable and testable on their own.
# decrypt.sh is source/decrypt.sh with detect.sh pasted at its include marker.

BUNDLE := source/detect.sh source/filter.sh source/encrypt-age.sh \
          source/encrypt-gpg.sh source/encrypt-openssl.sh source/main.sh
EOF_MARK := RS_SOURCE_EOF
OUT ?= .

.PHONY: all check
all: $(OUT)/recover.sh $(OUT)/decrypt.sh

define BUNDLE_HEADER
#!/usr/bin/env bash
# recover-secrets. Built by `make` from source/. Edit the files there, not this one.
# Encrypts GitHub Actions secrets to your public key and prints the blob.
# Inputs are environment variables: RS_SECRETS_JSON, RS_PUBLIC_KEY_URL or
# RS_PUBLIC_KEY, RS_INCLUDE, RS_ARTIFACT_NAME. See README.md.
set -euo pipefail
umask 077
RS_SRC="$$(mktemp -d)"
trap 'rm -rf -- "$$RS_SRC"' EXIT
endef
export BUNDLE_HEADER

$(OUT)/recover.sh: $(BUNDLE) Makefile
	@if grep -q -- '$(EOF_MARK)' $(BUNDLE); then \
	  echo "a file in source/ contains the heredoc delimiter $(EOF_MARK)" >&2; exit 1; fi
	@{ printf '%s\n' "$$BUNDLE_HEADER"; \
	   for f in $(BUNDLE); do \
	     printf '\ncat > "$$RS_SRC/%s" <<'"'"'$(EOF_MARK)'"'"'\n' "$$(basename "$$f")"; \
	     cat "$$f"; \
	     printf '%s\n' '$(EOF_MARK)'; \
	   done; \
	   printf '\nbash "$$RS_SRC/main.sh"\n'; \
	} > $@.tmp && chmod +x $@.tmp && mv $@.tmp $@

$(OUT)/decrypt.sh: source/decrypt.sh source/detect.sh Makefile
	@awk -v inc=source/detect.sh ' \
	  NR == 1 { print; print "# Built by `make` from source/decrypt.sh. Edit that file, not this one."; next } \
	  /^# include detect.sh$$/ { \
	    while ((getline line < inc) > 0) { \
	      if (line == "# BEGIN detect") on = 1; \
	      if (on) print line; \
	      if (line == "# END detect") on = 0; \
	    } \
	    close(inc); next } \
	  { print }' source/decrypt.sh > $@.tmp && chmod +x $@.tmp && mv $@.tmp $@

check:
	@tmp="$$(mktemp -d)"; \
	$(MAKE) -s OUT="$$tmp" all && \
	  diff -q "$$tmp/recover.sh" recover.sh && diff -q "$$tmp/decrypt.sh" decrypt.sh; \
	rc=$$?; rm -rf -- "$$tmp"; \
	[ $$rc -eq 0 ] || { echo "root scripts are out of date: run make" >&2; exit 1; }
