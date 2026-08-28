# Producer-owned recovery manifests and archives

These full schema-2 manifests and their exact ZIP assets are deterministic
producer contract fixtures for the cross-repository `vt2-mod-updater` recovery
resolver and streaming stager. The manifests are emitted from the real
recovery-record constructors and the sole production serializer,
`ConvertTo-VtReleaseManifestBytes`, in
`tools/publish-release/release-manifest.ps1`. The ZIPs are emitted by
`New-ReleaseZipBytesFromImmutableOutput`, the same immutable-output archive
constructor exercised by release-manifest validation.

Regenerate deliberately from the repository root:

```powershell
pwsh -NoProfile -File .\qa\check_release_recovery_record.ps1 -SelfTest -UpdateFixtures
```

Ordinary `-SelfTest` is read-only and reproduces each manifest in a temporary
Git repository before comparing the checked-in bytes and frozen hashes. The
temporary repository uses fixed author/committer identities, the UTC commit
date `2026-08-26T00:00:00Z`, `core.autocrlf=false`, and manifest
`published_at` value `2026-08-26T00:00:00.0000000Z`. Git-local environment
state is removed for each fixture command and restored exactly afterward.

Frozen outputs:

- `producer-tracked-manifest.json`: 3,964 bytes,
  SHA-256 `c367667af8ddf00c08d8b78f2fb5f8b791dc6b7897109f06316835d41a527dc6`
- `producer-tracked.zip`: 546 bytes,
  SHA-256 `7d1f642208d5851b8cfa748e4207093c24de70a2a6377b2473b1b1996d86b4e0`
- `producer-receipt-manifest.json`: 3,860 bytes,
  SHA-256 `812f656096f178fecfcb59e2a74b37811b046ab187516b0df8b65cc1e43981ec`
- `producer-receipt.zip`: 546 bytes,
  SHA-256 `7d1f642208d5851b8cfa748e4207093c24de70a2a6377b2473b1b1996d86b4e0`

The tracked- and receipt-authority archives are intentionally byte-identical:
authority changes the manifest proof, not the immutable canonical output set.
These fixtures prove producer serialization, archive construction, and schema
compatibility only. They grant no release-selection, download, ZIP extraction,
install, deploy, Workshop, or restore authority.
