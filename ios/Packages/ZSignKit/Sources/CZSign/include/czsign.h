#ifndef CZSIGN_H
#define CZSIGN_H

#ifdef __cplusplus
extern "C" {
#endif

/// zsign's command line entry point (same options as the zsign CLI).
int zsign_main(int argc, char *argv[]);

/// Resets getopt so zsign_main can be called more than once per process.
void czsign_reset_getopt(void);

/// Creates a throw-away local CA (restricted to localhost / 127.0.0.1) and a TLS server
/// certificate signed by it. Writes the CA certificate (DER) and the server identity (PKCS#12).
/// The CA private key is never stored. Returns 0 on success.
int czsign_make_local_ca(const char *ca_der_path, const char *server_p12_path,
                         const char *p12_password, char *error, int error_len);

#ifdef __cplusplus
}
#endif

#endif
