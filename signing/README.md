# Test signing key (CI/test builds only)

`omniverse-test.p12.b64` is the base64 of the ecosystem's **shared test key**
(the same `signing/omniverse-test.p12` committed in The-Omniverse repo),
stored as text so it can travel through text-only tooling. It is a public key
by design — anyone with the repo can sign as it — so it is **never** used for
public releases; those use the private release key via `OMNI_KEYSTORE`.

- Alias `omniverse`; store and key password `omniverse-test`. PKCS12.
- `android/app/build.gradle` decodes it into the build directory and signs
  with it whenever `OMNI_KEYSTORE` is not set, so every CI build of the Brawler
  carries the SAME signature and installs over the previous one.
- Before this, CI builds fell back to the runner's throwaway debug key and
  Android refused updates ("package conflicts with an existing package") —
  the failure that forced the Nov 10, 2026 identity rotation.

Note: the first build signed with this key cannot install over a debug-keyed
install (or vice versa). That one transition needs a reinstall — with the
identity transfer code held in another app (LPE), the Brawler's own Import
restores the identity afterwards.
