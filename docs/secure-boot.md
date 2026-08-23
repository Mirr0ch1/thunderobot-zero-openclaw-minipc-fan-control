# Building & signing the kernel module for Secure Boot

On modern Ubuntu systems with **Secure Boot enabled**, the kernel runs in
`lockdown: integrity` mode.  Two consequences matter here:

1. **Unsigned modules cannot be loaded.**  Every module must be signed with a
   key whose certificate is enrolled in the system keyring (a MOK).
2. **The stock `ec_sys` write path is unusable:**
   * `modprobe ec_sys write_support=1` fails — `write_support` is an *unsafe
     module parameter*, which lockdown rejects:
     `Lockdown: modprobe: unsafe module parameters is restricted`
   * Even a *writable debugfs file* is rejected:
     `Lockdown: <cmd>: debugfs access is restricted`

That is why this project ships a tiny custom module (`ec_rw`) that exposes EC
RAM through a **misc device** (`/dev/ec_rw`) instead of debugfs, and signs it
with the MOK key.  A misc character device is not subject to either lockdown
check.

## Signing with the enrolled MOK key (DKMS)

If you already have a MOK key enrolled (e.g. because you installed the NVIDIA
driver on a Secure Boot system), it lives at:

```
/var/lib/shim-signed/mok/MOK.priv   # private key
/var/lib/shim-signed/mok/MOK.der    # certificate
```

`install.sh` writes `/etc/dkms/framework.conf.d/sign_with_mok.conf` pointing
DKMS at these files, so every DKMS build (this module and NVIDIA's) is signed
automatically:

```
mok_signing_key="/var/lib/shim-signed/mok/MOK.priv"
mok_certificate="/var/lib/shim-signed/mok/MOK.der"
```

Verify the installed module is signed (the signer name is the CN of the MOK
key you enrolled, so it differs per machine — this is example output):

```console
$ modinfo ec_rw | grep -E 'signer|sig_hash'
signer:        Machine Owner Key
sig_hashalgo:  sha512
```

## Enrolling a new MOK key (if you don't have one)

If there is no MOK key yet, generate one and enroll it (one-time, requires a
reboot):

```console
$ openssl req -new -x509 -newkey rsa:2048 -keyout MOK.priv \
      -outform DER -out MOK.der -nodes -days 36500 \
      -subj "/CN=Machine Owner Key/"
$ sudo mokutil --import MOK.der
# reboot, complete the MOK enrollment in the blue MokManager screen
```

Then point `sign_with_mok.conf` at your key paths and rebuild.

## Without Secure Boot

If Secure Boot is **disabled**, none of this is needed:

* Delete `/etc/dkms/framework.conf.d/sign_with_mok.conf`.
* DKMS will still build and install the module; the kernel will load it
  unsigned.

## Manual (non-DKMS) build

```console
$ cd dkms
$ make KERNELRELEASE=$(uname -r)
$ sudo /usr/src/linux-headers-$(uname -r)/scripts/sign-file sha256 \
      /var/lib/shim-signed/mok/MOK.priv /var/lib/shim-signed/mok/MOK.der ec_rw.ko
$ sudo insmod ec_rw.ko
$ ls -l /dev/ec_rw
```
