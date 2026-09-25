#!/usr/bin/env bash
# shellcheck source=lib.sh
source "$(dirname "$0")/lib.sh"
# shellcheck source=../source/detect.sh
source "$REPO_ROOT/source/detect.sh"

test_detects_pem_rsa()        { gen_rsa 2048 k; assert_eq openssl "$(detect_key_format k.pub)"; }
test_detects_pem_rsa_legacy() { printf -- '-----BEGIN RSA PUBLIC KEY-----\nAAAA\n-----END RSA PUBLIC KEY-----\n' > k; assert_eq openssl "$(detect_key_format k)"; }
test_detects_pgp()            { gen_gpg gh pub.asc; assert_eq gpg "$(detect_key_format pub.asc)"; }
test_detects_age_recipient()  { gen_age a; assert_eq age "$(detect_key_format a.pub)"; }
test_detects_ssh_ed25519()    { gen_ssh ed25519 s; assert_eq age "$(detect_key_format s.pub)"; }
test_detects_ssh_rsa()        { gen_ssh rsa s; assert_eq age "$(detect_key_format s.pub)"; }
test_detects_keys_list_with_comment() {
  gen_ssh ed25519 s; { echo '# github keys'; cat s.pub; } > list
  assert_eq age "$(detect_key_format list)"
}
test_rejects_unknown_key()    { echo 'hello' > k; assert_fails detect_key_format k; }
test_rejects_private_key()    { gen_rsa 2048 k; assert_fails detect_key_format k; }

test_blob_age()     { assert_eq age     "$(detect_blob_format 'rs1:age:AAAA')"; }
test_blob_gpg()     { assert_eq gpg     "$(detect_blob_format 'rs1:gpg:AAAA')"; }
test_blob_openssl() { assert_eq openssl "$(detect_blob_format 'rs1:openssl:AAAA')"; }
test_blob_unknown_version() { assert_fails detect_blob_format 'rs2:age:AAAA'; }
test_blob_unknown_backend() { assert_fails detect_blob_format 'rs1:rot13:AAAA'; }
test_blob_garbage()         { assert_fails detect_blob_format 'AAAA'; }

run_tests
