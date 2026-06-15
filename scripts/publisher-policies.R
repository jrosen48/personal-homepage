# Publisher self-archiving policy lookup.
# NOTE: policies change. Treat this as a best-effort snapshot to be reviewed
# manually for any entry before publishing. Each entry lists a `verified_on`
# so we know when to refresh.
#
# Columns:
#   match_pattern: regex (case-insensitive) matched against Crossref `publisher`
#                  OR the vita venue string as a fallback.
#   share:         "yes" | "yes-default" | "no" | "unknown"
#                  "yes-default" means we're applying the optimistic default;
#                  treat as "plausibly yes, verify if in doubt."
#   version:       "SM" (submitted / preprint)
#                  "AM" (accepted manuscript / post-print)
#                  "VoR" (version of record / published PDF)
#   embargo_months: integer; 0 = immediate.
#   policy_url:     link to the publisher's self-archiving policy page.
#   note:           display text for each entry on the site.
#   verified_on:    YYYY-MM-DD of last manual check.

PUBLISHER_POLICIES <- tibble::tribble(
  ~match_pattern,                    ~share, ~version, ~embargo_months, ~policy_url, ~note, ~verified_on,

  # Taylor & Francis (Informa UK) — permits AM on personal page, no embargo
  # for SSH journals; educational journals count as SSH.
  "informa|taylor.*francis|routledge|tandf",
    "yes", "AM", 0,
    "https://authorservices.taylorandfrancis.com/research-impact/sharing-versions-of-journal-articles/",
    "Author's accepted manuscript posted per Taylor & Francis self-archiving policy.",
    "2026-04-17",

  # Wiley — AM on personal page immediately
  "wiley|john wiley",
    "yes", "AM", 0,
    "https://authorservices.wiley.com/author-resources/Journal-Authors/licensing/self-archiving.html",
    "Author's accepted manuscript posted per Wiley self-archiving policy.",
    "2026-04-17",

  # Elsevier — AM on personal site, no embargo (institutional repos may embargo)
  "elsevier",
    "yes", "AM", 0,
    "https://www.elsevier.com/about/policies/sharing",
    "Author's accepted manuscript posted per Elsevier sharing policy.",
    "2026-04-17",

  # ACM — author's accepted version permitted; ACM DL link is canonical
  "acm|association for computing machinery",
    "yes", "AM", 0,
    "https://authors.acm.org/author-resources/author-rights",
    "Author's accepted version posted per ACM author rights policy.",
    "2026-04-17",

  # Springer Nature — AM allowed on personal page after 12mo (STM) / immediate for some SSH
  "springer",
    "yes", "AM", 12,
    "https://www.springernature.com/gp/open-research/policies/journal-policies/self-archiving-policy",
    "Author's accepted manuscript posted per Springer Nature self-archiving policy.",
    "2026-04-17",

  # SAGE — AM on personal page, 12mo embargo for most journals
  "sage publications|sage publishing",
    "yes", "AM", 12,
    "https://us.sagepub.com/en-us/nam/journal-author-archiving-policies-and-re-use",
    "Author's accepted manuscript posted per SAGE self-archiving policy.",
    "2026-04-17",

  # AERA — AERA journals permit published version on personal page (journals now
  # with Sage; AERA Open is gold OA). Defer to parent where Sage applies.
  "^aera|american educational research association",
    "yes", "AM", 0,
    "https://www.aera.net/Publications/Journals/AERA-Journals-Publications",
    "Posted per AERA author rights.",
    "2026-04-17",

  # International Society of the Learning Sciences — author retains rights
  "learning sciences",
    "yes", "VoR", 0,
    "https://www.isls.org/publications/",
    "Posted per ISLS author rights.",
    "2026-04-17",

  # Center for Open Science (OSF preprints) — always green-OA
  "center for open science|osf",
    "yes", "SM", 0,
    "https://osf.io/tos/",
    "OSF preprint.",
    "2026-04-17",

  # MDPI — all gold OA
  "mdpi",
    "yes", "VoR", 0,
    "https://www.mdpi.com/authors/rights",
    "Open access under publisher's license.",
    "2026-04-17",

  # Routledge — is Taylor & Francis; covered by first rule but keep explicit
  "^routledge$",
    "yes", "AM", 0,
    "https://authorservices.taylorandfrancis.com/research-impact/sharing-versions-of-journal-articles/",
    "Author's accepted manuscript posted per Routledge (Taylor & Francis) self-archiving policy.",
    "2026-04-17",

  # MIT Press — HDSR is CC-BY, other journals vary
  "mit press",
    "yes", "VoR", 0,
    "https://mitpress.mit.edu/books-authors/authors/journals-author-information",
    "Posted per MIT Press policy.",
    "2026-04-17",

  # IGI Global — AM on personal page after 6mo
  "igi global",
    "yes", "AM", 6,
    "https://www.igi-global.com/about/rights-permissions/",
    "Author's accepted manuscript posted per IGI Global policy.",
    "2026-04-17",

  # AACE (LearnTechLib / SITE proceedings) — author retains rights
  "association for the advancement of computing in education|aace",
    "yes", "VoR", 0,
    "https://www.aace.org/pubs/ethics/",
    "Posted per AACE author rights.",
    "2026-04-17",

  # National Academies Press — publicly available PDFs via nap.edu; free to share
  "national academies press",
    "yes", "VoR", 0,
    "https://nap.nationalacademies.org/reprint_permission.html",
    "Posted per National Academies reuse policy.",
    "2026-04-17",

  # The Conversation — CC-BY-ND, republication allowed
  "the conversation",
    "yes", "VoR", 0,
    "https://theconversation.com/us/republishing-guidelines",
    "Republished under The Conversation's CC BY-ND license.",
    "2026-04-17",

  # IASE / IAStatE
  "international association for statistical|statistics education",
    "yes", "VoR", 0,
    NA_character_,
    "Posted per IASE conference proceedings policy (author retains rights).",
    "2026-04-17",

  # Australasian Soc. for Computers in Learning — ASCILITE AJET is OA
  "australasian society for computers in learning",
    "yes", "VoR", 0,
    "https://ajet.org.au/index.php/AJET/about",
    "Open access under AJET's CC BY-NC-ND license.",
    "2026-04-17",

  # Edward Elgar — post-print allowed after 18mo embargo
  "edward elgar",
    "yes", "AM", 18,
    "https://www.e-elgar.com/publish-with-us/author-hub/open-access-and-self-archiving/",
    "Author's accepted manuscript posted per Edward Elgar policy.",
    "2026-04-17",
)
