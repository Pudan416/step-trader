# Happenings device build — 2026-09-15

The user explicitly requested installing this feature branch and instructed not to push to the closed current-integration PR. No remote publication or integration update was performed.

Built from clean revision `0f8aec47ab0198fe6368ed6c839d11d82abee7a3` on `codex/happenings-field`, using scheme Steps4, Debug, generic iOS, with dedicated DerivedData at `/private/tmp/nowhere-happenings-device-20260915-dd`.

The signed app and all four embedded extensions passed strict signature verification and contain provisioning profiles supporting iPhone Costa. Required resources passed validation: 11 registered fonts, Metal library, asset catalog, 21 matching gate images in app/ShieldConfiguration, and 122 WAV files. Background audio and launch screen configuration are present.

App bundle: `/private/tmp/nowhere-happenings-device-20260915-dd/Build/Products/Debug-iphoneos/Nowhere.app`.

Installation and launch succeeded over Wi-Fi on iPhone Costa at 00:48 Europe/Belgrade on 2026-09-15. Installed Git revision: `0f8aec47ab0198fe6368ed6c839d11d82abee7a3`. The later documentation-only commit did not change the built app.

The first attempt timed out after 180 seconds; the second failed with Connection interrupted. After the user requested retrying over Wi-Fi, the third attempt completed successfully. `devicectl device process launch --terminate-existing` then confirmed app launch.

Physical-device installation and launch are confirmed. Visual, gesture and typography checks remain the previously recorded simulator checks; no physical-device UI inspection was performed.
