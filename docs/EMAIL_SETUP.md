# Email verification: paused now, retained for later

**Current policy: verification sending is paused.** New accounts receive a real session without an email code. The top banner says “email verification will be required soon!” This is not proof that anyone controls their signup address, and it is not bot protection.

## Current configuration and retained capability

- `frontend/src/features/auth/verification.ts` exports `REQUIRE_EMAIL_VERIFICATION = false`.
- The dedicated Rockyforums project uses `mailer_autoconfirm = true` (Confirm email off).
- Signup requires a real returned session; a pending response is treated as a configuration mismatch, not successful authentication.
- The login recovery link is hidden. `/verify-email` shows a paused notice, not code/resend controls. Both API functions are also guarded against accidental calls.
- The eight-digit `verifyOtp` / confirmation-only `resend` flow, validation, cooldown, template, and enabled-policy API tests are retained for later.
- Current legal documents **1.2** explain the temporary pause. Versions 1.0 and 1.1 remain available as history.
- No SMTP or hosted-template setup has been completed. No existing users have been bulk-confirmed or deleted.

## Re-enable only as a coordinated release

First complete the provider setup below while confirmation remains disabled. Then publish updated legal disclosures identifying the actual sender, design re-verification for auto-confirmed accounts, set `REQUIRE_EMAIL_VERIFICATION = true` in the private workspace and publish a new database frontend release, and enable Supabase Confirm email (`mailer_autoconfirm = false`) in a controlled release. Update browser tests to exercise the enabled UI and complete the live smoke test below. A frontend constant is **not** a server-side security boundary; the matching provider configuration is required. Do not toggle just one side or describe legacy auto-confirmed addresses as verified.

## Provider setup before re-enabling

The available connector can toggle confirmation, but **cannot edit email templates or SMTP configuration**. Those settings have not been applied automatically. At the last inspection the project had no custom SMTP host, an eight-digit OTP setting, a 60-second email frequency setting, and the default link-based confirmation template.

1. Open the **Rockyforums** project (`rccshonvlrgskzvrpqhy`), not your older shared project.
2. In Authentication's email/SMTP settings, configure your transactional email provider and an authorized sender address. Enter its credentials **only in Supabase**. Do not paste them into chat, `VITE_` variables, GitHub issues, or this repository. The default sender is intended for testing and may restrict recipients and rate; do not assume it can serve public registrations.
3. Open **Email Templates → Confirm signup**. Use the subject `Your Rockyforums verification code` and paste the complete contents of [`supabase/templates/confirmation.html`](../supabase/templates/confirmation.html).
4. The template must contain `{{ .Token }}`. A template containing only `{{ .ConfirmationURL }}` sends a link, **not the code this UI expects**. The supplied template deliberately has no confirmation link.
5. Keep the email OTP length at **8** and the resend interval at **60 seconds** to match `frontend/src/features/auth/verification.ts`. The last observed OTP expiry was one hour; use a suitably short expiry in Supabase and test it. If you change code length or frequency, change the frontend constants and tests too. Do not mistake the TOTP/MFA code settings for email OTP settings.
6. Review provider email-send, verification-attempt, and signup rate limits. The browser's cooldown is only a usability aid; Supabase's server-side limits are the security boundary. Add a provider-supported CAPTCHA when appropriate rather than claiming email verification stops all bots.
7. Set the final HTTPS site URL. Do not add broad redirect wildcards; this code-only flow does not use callback URLs or parse confirmation-link fragments.
8. Before public launch, identify the actual production email provider in a new privacy-notice version, set a private support contact, and complete the rest of `SECURITY.md`.

Keep confirmation **disabled** until the sender, template, tested frontend release and coordinated rollout are ready. After re-enabling, do not toggle auto-confirmation merely to conceal a broken sender; fix delivery and handle affected accounts deliberately.

## Live smoke test (required)

Use a disposable email inbox you control. Do not share the received code with anyone.

1. Sign up with a new username, valid email, password, and current terms acceptance.
2. Confirm that `/verify-email` opens and that refreshing it retains the email but not the password or code.
3. Confirm there is no member session and that password login is blocked while the email is unconfirmed.
4. Check that the email contains an eight-digit code, not just a link.
5. Enter an incorrect code: access must remain blocked. Enter the correct, most recent code: a session should be created and the account screen should load.
6. Confirm that a consumed code cannot be used again. Request a replacement from another disposable pending account and test provider rate limits and code expiry. Do not exceed your provider's limits merely to test them.
7. Log out, then use normal password login. Reload and verify session persistence.

Browser tests intercept email APIs and therefore **do not prove real delivery, code expiry, or provider anti-abuse behavior**. Database tests likewise do not call the Auth HTTP endpoints. Complete this live check after the template and sender are configured.

## Pending accounts and older accounts

When verification is enabled, a pending Supabase user and its reserved username/consent record are created before confirmation. The unconfirmed account cannot log in, but email confirmation alone does not prevent someone from creating many pending accounts. Establish rate limits, abuse controls, and a pending-account cleanup/retention policy before public launch; automatic cleanup is not implemented here.

While the pause is active, older unconfirmed accounts may still be unable to log in; the app explains the limitation instead of requesting a non-working email. Handle individual cases deliberately through the operator, without bulk-confirming or deleting members.

Enabling confirmation affects new signups. It does not retroactively prove ownership of addresses on any accounts created under the previous auto-confirming configuration. Audit those accounts if present and design any re-verification migration deliberately; do not silently assume they were verified.
