-- Publish the temporary no-email policy without rewriting earlier legal versions.
update public.legal_documents set is_current = false
  where kind in ('terms', 'privacy') and is_current;

with revisions(kind, previous_id, patches) as (
  values
    ('terms', 'terms-1.1', $terms_patch$[
  {
    "id": "changes-in-1-2",
    "title": "Email verification temporarily paused",
    "paragraphs": [
      "Verification email delivery is on hold while the sending service is prepared. New accounts can join and sign in without a verification code for now. The website announces that verification will be required soon; its return will be explained in a new terms version."
    ]
  },
  {
    "id": "your-account",
    "paragraphs": [
      "Choose a username that does not impersonate another person or the site team. Keep your password private and use an email address you are entitled to use. You are responsible for activity on your account, except where applicable law provides otherwise.",
      "Email ownership is not currently verified at signup. Use an address you control, and do not treat another member’s email address or an internal confirmation timestamp as proof of identity or mailbox ownership. Email-code verification will be required in a future release after email delivery is ready."
    ]
  },
  {
    "id": "current-scope",
    "paragraphs": [
      "This release provides account creation, login, and legal-document acceptance. Email-code verification is implemented but temporarily paused. Public threads, replies, direct messages, file uploads, paid services, and other community features are not available in this release.",
      "Before introducing features that materially change your rights, privacy, or responsibilities, we will publish the relevant rules in a new terms version and ask you to accept it. This version does not grant us a broad license to content that you have not submitted."
    ]
  }
]$terms_patch$::jsonb),
    ('privacy', 'privacy-1.1', $privacy_patch$[
  {
    "id": "changes-in-1-2",
    "title": "Verification sending is on hold",
    "paragraphs": [
      "New signups do not request a verification email while email delivery is paused. Accounts currently use unverified email addresses. Previously collected verification records may remain under the retention rules below."
    ]
  },
  {
    "id": "why-we-use-it",
    "paragraphs": [
      "We use this information to create and authenticate accounts, maintain sessions, keep the service secure, and record agreement to the current rules. We do not use this release to sell account data or serve targeted advertising.",
      "Email verification is temporarily off. New accounts can sign in without a code, and the application does not request verification messages while this policy is paused. Supabase’s auto-confirmation is an internal account setting, not proof that someone controls the address. We do not send marketing messages."
    ]
  },
  {
    "id": "what-we-store",
    "paragraphs": [
      "For this release, we store your email address and password credentials in Supabase Auth. Supabase hashes passwords; the application does not store plaintext passwords. Your profile stores a username, account identifier, and creation time.",
      "We also store each terms version you accept and a server-generated acceptance time. The website host and Supabase may process technical information such as IP addresses, browser details, and security or operational logs.",
      "If email verification is enabled again, Supabase will process email-verification tokens and confirmation timestamps, and the configured email-delivery provider will process the recipient address and confirmation message. The application does not log or persist verification codes or passwords."
    ]
  },
  {
    "id": "storage-and-providers",
    "paragraphs": [
      "Supabase provides authentication and database storage. This project is configured in the United States, so information may be processed outside your province or country and subject to the laws of that location. The website host processes requests needed to deliver the site. A production email provider must be identified before verification sending is enabled.",
      "Our application restricts profile and consent-history access to the signed-in account. Service administrators and providers may access information where needed to operate, secure, or comply with legal obligations for the service."
    ]
  }
]$privacy_patch$::jsonb)
), documents as (
  select r.kind, d.title, r.patches->0 as change_summary,
    jsonb_agg(
      s.value || coalesce(
        (select p.value from jsonb_array_elements(r.patches) as p(value)
          where p.value->>'id' = s.value->>'id'),
        '{}'::jsonb
      ) order by s.ordinality
    ) filter (where s.value->>'id' not like 'changes-in-%') as sections
  from revisions r
  join public.legal_documents d on d.id = r.previous_id
  cross join lateral jsonb_array_elements(d.sections) with ordinality as s(value, ordinality)
  group by r.kind, d.title, r.patches
)
insert into public.legal_documents
  (id, kind, version, title, effective_at, is_current, sections)
select kind || '-1.2', kind, '1.2', title, now(), true,
  jsonb_build_array(change_summary) || sections
from documents;

do $$
begin
  if (select count(*) from public.legal_documents where version = '1.2' and is_current) <> 2 then
    raise exception 'Both current legal documents must be published';
  end if;
end;
$$;
