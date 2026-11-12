#include "czsign.h"

#include <stdio.h>
#include <string.h>
#include <unistd.h>
#include <getopt.h>

#include <OpenSSL/evp.h>
#include <OpenSSL/err.h>
#include <OpenSSL/pem.h>
#include <OpenSSL/pkcs12.h>
#include <OpenSSL/rand.h>
#include <OpenSSL/x509.h>
#include <OpenSSL/x509v3.h>

#if defined(__APPLE__)
extern int optreset;
#endif

void czsign_reset_getopt(void)
{
#if defined(__APPLE__)
    optreset = 1;
#endif
    optind = 1;
    opterr = 0;
}

static void set_error(char *error, int error_len, const char *message)
{
    if (error == NULL || error_len <= 0) {
        return;
    }
    unsigned long code = ERR_get_error();
    if (code != 0) {
        char detail[256];
        ERR_error_string_n(code, detail, sizeof(detail));
        snprintf(error, (size_t)error_len, "%s (%s)", message, detail);
    } else {
        snprintf(error, (size_t)error_len, "%s", message);
    }
}

static int add_extension(X509 *cert, X509 *issuer, int nid, const char *value)
{
    X509V3_CTX ctx;
    X509V3_set_ctx_nodb(&ctx);
    X509V3_set_ctx(&ctx, issuer, cert, NULL, NULL, 0);
    X509_EXTENSION *ext = X509V3_EXT_conf_nid(NULL, &ctx, nid, value);
    if (ext == NULL) {
        return 0;
    }
    int ok = X509_add_ext(cert, ext, -1);
    X509_EXTENSION_free(ext);
    return ok;
}

static int random_serial(X509 *cert)
{
    unsigned char bytes[16];
    if (RAND_bytes(bytes, sizeof(bytes)) != 1) {
        return 0;
    }
    bytes[0] &= 0x7F; // keep it positive
    BIGNUM *bn = BN_bin2bn(bytes, sizeof(bytes), NULL);
    if (bn == NULL) {
        return 0;
    }
    int ok = BN_to_ASN1_INTEGER(bn, X509_get_serialNumber(cert)) != NULL;
    BN_free(bn);
    return ok;
}

static X509 *new_certificate(EVP_PKEY *key, const char *common_name, long days)
{
    X509 *cert = X509_new();
    if (cert == NULL) {
        return NULL;
    }
    X509_set_version(cert, 2);
    if (!random_serial(cert)) {
        X509_free(cert);
        return NULL;
    }
    X509_gmtime_adj(X509_getm_notBefore(cert), -24 * 3600);
    X509_gmtime_adj(X509_getm_notAfter(cert), days * 24 * 3600);
    X509_set_pubkey(cert, key);
    X509_NAME *name = X509_get_subject_name(cert);
    X509_NAME_add_entry_by_txt(name, "CN", MBSTRING_UTF8, (const unsigned char *)common_name, -1, -1, 0);
    X509_NAME_add_entry_by_txt(name, "O", MBSTRING_UTF8, (const unsigned char *)"IPA Beam (lokal)", -1, -1, 0);
    return cert;
}

int czsign_make_local_ca(const char *ca_der_path, const char *server_p12_path,
                         const char *p12_password, char *error, int error_len)
{
    int result = -1;
    EVP_PKEY *ca_key = NULL;
    EVP_PKEY *server_key = NULL;
    X509 *ca = NULL;
    X509 *server = NULL;
    PKCS12 *p12 = NULL;
    FILE *file = NULL;

    ca_key = EVP_RSA_gen(2048);
    server_key = EVP_RSA_gen(2048);
    if (ca_key == NULL || server_key == NULL) {
        set_error(error, error_len, "Schlüssel konnten nicht erzeugt werden");
        goto done;
    }

    // --- Root CA: only allowed to issue certificates for this device's loopback address.
    ca = new_certificate(ca_key, "IPA Beam Local CA", 3650);
    if (ca == NULL) {
        set_error(error, error_len, "CA-Zertifikat konnte nicht erstellt werden");
        goto done;
    }
    X509_set_issuer_name(ca, X509_get_subject_name(ca));
    if (!add_extension(ca, ca, NID_basic_constraints, "critical,CA:TRUE,pathlen:0") ||
        !add_extension(ca, ca, NID_key_usage, "critical,keyCertSign,cRLSign") ||
        !add_extension(ca, ca, NID_subject_key_identifier, "hash") ||
        !add_extension(ca, ca, NID_name_constraints,
                       "critical,permitted;IP:127.0.0.1/255.255.255.255,permitted;DNS:localhost")) {
        set_error(error, error_len, "CA-Erweiterungen fehlgeschlagen");
        goto done;
    }
    if (X509_sign(ca, ca_key, EVP_sha256()) <= 0) {
        set_error(error, error_len, "CA konnte nicht signiert werden");
        goto done;
    }

    // --- Server certificate for https://127.0.0.1 (Apple: <= 825 days, SAN, serverAuth).
    server = new_certificate(server_key, "127.0.0.1", 800);
    if (server == NULL) {
        set_error(error, error_len, "Server-Zertifikat konnte nicht erstellt werden");
        goto done;
    }
    X509_set_issuer_name(server, X509_get_subject_name(ca));
    if (!add_extension(server, ca, NID_basic_constraints, "critical,CA:FALSE") ||
        !add_extension(server, ca, NID_key_usage, "critical,digitalSignature,keyEncipherment") ||
        !add_extension(server, ca, NID_ext_key_usage, "serverAuth") ||
        !add_extension(server, ca, NID_subject_alt_name, "IP:127.0.0.1,DNS:localhost") ||
        !add_extension(server, ca, NID_subject_key_identifier, "hash") ||
        !add_extension(server, ca, NID_authority_key_identifier, "keyid:always")) {
        set_error(error, error_len, "Server-Erweiterungen fehlgeschlagen");
        goto done;
    }
    if (X509_sign(server, ca_key, EVP_sha256()) <= 0) {
        set_error(error, error_len, "Server-Zertifikat konnte nicht signiert werden");
        goto done;
    }

    // --- Write the CA certificate (DER) for the configuration profile.
    file = fopen(ca_der_path, "wb");
    if (file == NULL || i2d_X509_fp(file, ca) != 1) {
        set_error(error, error_len, "CA-Zertifikat konnte nicht gespeichert werden");
        goto done;
    }
    fclose(file);
    file = NULL;

    // --- Server identity as PKCS#12 with algorithms iOS can import (3DES + SHA-1 MAC).
    STACK_OF(X509) *chain = sk_X509_new_null();
    sk_X509_push(chain, ca);
    p12 = PKCS12_create(p12_password, "IPA Beam Server", server_key, server, chain,
                        NID_pbe_WithSHA1And3_Key_TripleDES_CBC,
                        NID_pbe_WithSHA1And3_Key_TripleDES_CBC,
                        2048, -1, 0);
    sk_X509_free(chain);
    if (p12 == NULL || PKCS12_set_mac(p12, p12_password, -1, NULL, 0, 2048, EVP_sha1()) != 1) {
        set_error(error, error_len, "PKCS#12 konnte nicht erstellt werden");
        goto done;
    }
    file = fopen(server_p12_path, "wb");
    if (file == NULL || i2d_PKCS12_fp(file, p12) != 1) {
        set_error(error, error_len, "Server-Identität konnte nicht gespeichert werden");
        goto done;
    }
    result = 0;

done:
    if (file != NULL) fclose(file);
    PKCS12_free(p12);
    X509_free(server);
    X509_free(ca);
    EVP_PKEY_free(server_key);
    EVP_PKEY_free(ca_key); // the CA key is never written anywhere
    return result;
}
