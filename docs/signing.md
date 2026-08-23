# Signing the release

One-time setup, about five minutes. `iOS Release` fails fast and loudly without it,
on purpose.

## Why this exists

The release job used to carry no certificate of its own. It archived with
`-allowProvisioningUpdates` and an App Store Connect API key, and let Xcode create
whatever it needed on demand. The file was rather pleased about this, and said so:

> One key does both jobs … That is why there is no
> exporting-a-.p12-and-base64ing-it-into-a-secret dance anywhere in this file.

That comment described a leak. A GitHub runner is destroyed after every job, so its
keychain starts empty every time, so Xcode did not *find* a certificate — it asked
Apple for a **brand new one**, on every single release. Apple caps how many an
account may hold.

The arithmetic caught up on 22 August 2026:

```
error: Choose a certificate to revoke. Your account has reached the maximum
number of certificates. To create a new one, you must choose a certificate to revoke.
```

Revoking one frees a slot; the next release consumes it again. The fix is for the
runner to **bring an identity and create none** — which is the dance the file was
avoiding, and which turns out to be the reason accounts do not run out of
certificates.

Provisioning profiles are still created on demand during the archive. Those are not
capped, and they derive from a certificate rather than the other way round, so there
is nothing to manage but the identity itself.

## You need two identities, not one

Automatic signing archives with **Apple Development** and leaves distribution to
`-exportArchive`, which re-signs with **Apple Distribution**. That is Apple's flow,
not a misconfiguration — forcing `CODE_SIGN_IDENTITY="Apple Distribution"` on the
archive fights automatic signing and fails.

So the `.p12` has to hold both, each with its private key. A `.p12` missing one of
them gets through the import and fails later with a vaguer message, which is why the
workflow checks for both up front.

## Setup

### 1. See what the account is holding

```bash
asc auth login --name Verso --key-id YOUR_KEY_ID --issuer-id YOUR_ISSUER_ID --private-key /path/to/AuthKey_YOUR_KEY_ID.p8
```

```bash
asc certificates list
```

Certificate writes may need an Admin or App Manager key role.

### 2. Free a slot, if the account is capped

Look for certificates whose private key no longer exists on any machine you have —
every one this CI minted is in that category, since the runner that made it was
deleted minutes later. They cannot sign anything ever again.

```bash
asc certificates revoke --id CERT_ID --confirm
```

Revoking invalidates any provisioning profile built on that certificate. The archive
step regenerates profiles automatically, so that is expected rather than a problem.

### 3. Create both certificates, keeping the private keys

Easiest in Xcode, because it puts the private key straight into your keychain:

**Xcode → Settings → Accounts → your Apple ID → Manage Certificates → `+`**, then
create both **Apple Development** and **Apple Distribution**.

### 4. Export them as one `.p12`

In **Keychain Access → login → My Certificates**, select *both* identities — the rows
that expand to reveal a private key, not the bare certificates — then right-click →
**Export 2 items…** and save as `Signing.p12` with a password.

If the export offers `.cer`, the wrong rows are selected: you have the certificates
without their keys, and the workflow will reject the result.

### 5. Set the secrets

```bash
base64 -i Signing.p12 | gh secret set SIGNING_P12
```

```bash
gh secret set SIGNING_P12_PASSWORD
```

Then delete the local `Signing.p12`. Keep the identities in your keychain — that is
your only copy of the private keys, and losing them means revoking and starting over.

## When a certificate expires

Apple Development lasts a year, Apple Distribution three. Expiry looks like a signing
failure rather than an expiry, so check it first:

```bash
asc certificates list
```

Repeat steps 3–5. Nothing in the workflow changes.

## What the workflow does with it

`Import the signing identities` decodes the `.p12` into a throwaway keychain in
`$RUNNER_TEMP`, unlocks it for six hours (the default 300-second auto-lock is shorter
than an archive, and a keychain that locks partway through fails a different target
every run), authorises `codesign` to use the key without a UI prompt, and prepends the
keychain to the search list.

It counts identities and never prints them: a certificate's common name carries the
team name, and this repository is public.

`Remove the credentials` deletes the keychain and the API key, always, including on
failure.
