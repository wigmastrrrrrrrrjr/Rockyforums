-- Email verification changes the account rules and processing notice.
-- Preserve both 1.0 documents and all earlier acceptance records.
update public.legal_documents set is_current = false
  where kind in ('terms', 'privacy') and is_current;

insert into public.legal_documents
  (id, kind, version, title, effective_at, is_current, sections)
values
('terms-1.1', 'terms', '1.1', 'Terms of Service', now(), true, $terms$[
  {
    "id": "changes-in-1-1",
    "title": "What changed in version 1.1",
    "paragraphs": [
      "Email-code verification is now required before a newly registered account can sign in. This helps reduce automated misuse, but it is not a guarantee that a member is human or trustworthy. All other community boundaries continue to apply."
    ]
  },
  {
    "id": "welcome",
    "title": "A place for real people",
    "paragraphs": [
      "Welcome to Rockyforums, an independent, open-source community project. These terms govern your use of the website and your account. By creating an account or explicitly accepting an updated version, you agree to this version of the terms.",
      "You must be at least 16 years old and legally able to accept these terms where you live. If your local law requires a parent or guardian to agree, obtain that permission before using the service."
    ]
  },
  {
    "id": "your-account",
    "title": "Your account, your responsibility",
    "paragraphs": [
      "Choose a username that does not impersonate another person or the site team. Keep your password private and use an email address you are entitled to use. You are responsible for activity on your account, except where applicable law provides otherwise.",
      "Before you can sign in, confirm your email address with the one-time code sent to your inbox. Use an address you control and never share a verification code. Confirming an email demonstrates access to that mailbox, not a person’s legal identity or trustworthiness."
    ]
  },
  {
    "id": "community-conduct",
    "title": "Be curious. Be decent.",
    "paragraphs": [
      "Do not use the service for unlawful activity, exploitation of children, threats, targeted harassment, hateful abuse, or sharing someone else’s private information without permission. Do not distribute malware, spam, or deceptive content, impersonate others, or evade a suspension.",
      "You may disagree with ideas; do not attack people. Respect intellectual property and the privacy of other members. Do not try to bypass security controls, scrape private account data, or disrupt the service."
    ]
  },
  {
    "id": "current-scope",
    "title": "Starting small, on purpose",
    "paragraphs": [
      "This release provides account creation, email-code verification, login, and legal-document acceptance. Public threads, replies, direct messages, file uploads, paid services, and other community features are not available in this release.",
      "Before introducing features that materially change your rights, privacy, or responsibilities, we will publish the relevant rules in a new terms version and ask you to accept it. This version does not grant us a broad license to content that you have not submitted."
    ]
  },
  {
    "id": "safety-and-moderation",
    "title": "Keeping the space safe",
    "paragraphs": [
      "The operator may investigate misuse and restrict or suspend accounts that violate these terms, create security risks, or must be restricted by law. Measures should be proportionate; a serious safety issue may require action without advance notice.",
      "A private support and appeal channel must be published before community features launch. Never post passwords, access tokens, or private identity documents in a public issue or discussion."
    ]
  },
  {
    "id": "privacy-and-choices",
    "title": "Your information and your choices",
    "paragraphs": [
      "The Privacy Notice describes account data, session storage, service providers, and your privacy choices. We do not ask you to publish your email address or password.",
      "You may stop using the service at any time. Account-access and deletion requests should be made privately to the site operator. Self-service account deletion is not yet available; a private request channel must be published before public launch."
    ]
  },
  {
    "id": "availability-and-rights",
    "title": "A few practical boundaries",
    "paragraphs": [
      "Rockyforums is an early-stage project. Availability, uninterrupted access, and recovery of lost information are not guaranteed. To the extent permitted by applicable law, the service is provided as available without additional warranties.",
      "Nothing in these terms excludes liability or rights that cannot legally be excluded, including applicable consumer and privacy rights. Do not use the service for emergency communications or as your only copy of important information."
    ]
  },
  {
    "id": "terms-updates",
    "title": "When the ground rules change",
    "paragraphs": [
      "Each published version has an effective date and remains available at a permanent version URL. We record the terms version and server timestamp when you accept it; accepting a new version does not overwrite earlier acceptance records.",
      "Material changes require fresh, explicit acceptance before continued participation. We will describe important changes with the new version, rather than treating silence as agreement. If you do not agree, you may sign out, stop using the service, and request account deletion through the operator’s private channel once published."
    ]
  }
]$terms$::jsonb),
('privacy-1.1', 'privacy', '1.1', 'Privacy Notice', now(), true, $privacy$[
  {
    "id": "changes-in-1-1",
    "title": "Email verification, now included",
    "paragraphs": [
      "This version adds processing needed to send and check one-time email-verification codes. It replaces the account-only release’s previous no-verification policy."
    ]
  },
  {
    "id": "what-we-store",
    "title": "The information we collect",
    "paragraphs": [
      "For this release, we store your email address and password credentials in Supabase Auth. Supabase hashes passwords; the application does not store plaintext passwords. Your profile stores a username, account identifier, and creation time.",
      "We also store each terms version you accept and a server-generated acceptance time. The website host and Supabase may process technical information such as IP addresses, browser details, and security or operational logs.",
      "Supabase also processes email-verification tokens and confirmation timestamps. The configured email-delivery provider processes the recipient address and confirmation message to deliver the code. The application does not log or persist the code or password."
    ]
  },
  {
    "id": "why-we-use-it",
    "title": "Why we use it",
    "paragraphs": [
      "We use this information to create and authenticate accounts, maintain sessions, keep the service secure, and record agreement to the current rules. We do not use this release to sell account data or serve targeted advertising.",
      "New accounts must confirm their email address with a one-time code before signing in. We use email to send registration and requested replacement codes, not marketing messages. Verification helps prevent misuse but does not establish a member’s legal identity."
    ]
  },
  {
    "id": "storage-and-providers",
    "title": "Where information lives",
    "paragraphs": [
      "Supabase provides authentication and database storage. This project is configured in the United States, so information may be processed outside your province or country and subject to the laws of that location. The website host processes requests needed to deliver the site, and the configured email provider processes verification-message delivery. The operator must identify the production email provider before public launch.",
      "Our application restricts profile and consent-history access to the signed-in account. Service administrators and providers may access information where needed to operate, secure, or comply with legal obligations for the service."
    ]
  },
  {
    "id": "browser-storage",
    "title": "What stays in your browser",
    "paragraphs": [
      "The site uses browser local storage for Supabase session tokens after you sign in. The verification screen may retain your email address and the code-request time in this tab’s navigation history so a reload can resume confirmation. Passwords and verification codes are not put in navigation state or URLs, and are not saved by application code. Your browser or password manager has its own storage settings.",
      "Logging out ends this browser’s session. Other devices remain signed in. This release does not add advertising cookies or third-party analytics, and fonts are served with the website rather than fetched from a font service."
    ]
  },
  {
    "id": "retention-and-requests",
    "title": "Retention and your rights",
    "paragraphs": [
      "Account and consent records remain while your account exists. Deleting an account removes its profile and linked consent records from the live application database. Provider backups and security logs may persist under their retention policies; we cannot promise immediate removal from every backup. Unconfirmed registration records may remain until removed by the operator; automatic cleanup of pending accounts is not implemented in this release.",
      "Depending on applicable law, you may have rights to access, correct, export, delete, or object to processing of your information. Self-service requests are not available yet. A private contact channel must be published before public launch. Do not share private account information in the public source repository."
    ]
  },
  {
    "id": "privacy-changes",
    "title": "As the community grows",
    "paragraphs": [
      "This notice covers the account-only release. Before adding public profiles, conversations, messaging, uploads, analytics, or other material data uses, we will describe the new processing and update the relevant legal documents.",
      "Published notices keep a version number and effective date. Where a change requires consent under applicable law, we will request it explicitly rather than treating continued browsing as consent."
    ]
  }
]$privacy$::jsonb);
