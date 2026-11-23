# MaPrimeRénov' (MPR): legal-history tracking for policy evaluation

## 1. Project context

- **Goal.** Build a dated change log of all significant changes to MaPrimeRénov' since its introduction (2020). The aim is to find policy variation that can justify identification restrictions in a policy-evaluation setting.
- **Primary task.** Track changes in **grant amounts**: forfaits by *geste* × income category, plus expense caps and ceilings.
- **Secondary task.** Track changes in **technical characteristics and eligibility conditions**, so that no major change is missed.
- **Research interests.**
  - My own: supply-side outcomes, namely output, employment, firm investment, entry, and firms' reach.
  - Co-authors': interactions between MPR and the CEE (*Certificats d'économies d'énergie*).
- **Existing setup.**
  - French administrative microdata via CASD: Base TVA mensuelle, DADS, DSN, with MPR installer registries matched to TVA declarations.
  - Event studies and DiD with continuous treatment (Callaway–Sant'Anna, de Chaisemartin–D'Haultfœuille) in `fixest`.
  - Existing design: PAC vs. CET around the April 2022 subsidy increase.
  - Tooling: R and DuckDB.

## 2. Core legal texts

| Role | Text | Link |
|---|---|---|
| Establishes MPR | Décret (Jan 2020) | https://www.legifrance.gouv.fr/loda/id/JORFTEXT000041400291 |
| Grant amounts per equipment/work | Arrêté (Jan 2020, consolidated) | https://www.legifrance.gouv.fr/loda/id/JORFTEXT000041400376 |
| Technical characteristics / eligibility | Arrêté (Nov 2020) | https://www.legifrance.gouv.fr/jorf/id/JORFTEXT000042532442 |

## 3. Access constraints

- Légifrance blocked automated fetching in the claude.ai session (bot detection). It may behave the same way here, so test it first.
- Preferred routes, in order:
  1. **PISTE Légifrance API** (https://piste.gouv.fr). Free OAuth credentials, scriptable in R. It returns article versions with validity dates.
  2. **DILA LEGI open-data dump** (bulk XML of consolidated texts with version history).
  3. Manual download of versions from the Légifrance "Versions" tab, then local diffing.
- Use secondary sources (press, comparators) for corroboration and significance only, not as the primary record.

## 4. Coverage gaps: the three texts are NOT the whole policy

Track these on parallel tracks:

- **MPR Sérénité / Accompagnée (Parcours accompagné).** Largely governed by the ANAH *Règlement général* (RGA) and ANAH board *délibérations*, not by the arrêtés above.
- **Income ceilings and expense caps.** Revised through separate instruments. They change treatment status even when nominal grants don't move.
- **Cumulation rules.** The *écrêtement* of MPR + CEE as a share of costs. Key for the co-authors' CEE angle.
- **CEE amounts.** Coup de pouce *arrêtés* and their bonifications sit on a separate legal track. Treat CEE as a parallel track, not as an afterthought.
- **Firm-side rules.** These are likely the most relevant for supply-side outcomes:
  - RGE certification requirements;
  - subcontracting rules;
  - the ban on cold-calling (2020);
  - Mon Accompagnateur Rénov';
  - anti-fraud measures.

## 5. Known or likely major episodes (to verify; dates from memory, not checked)

- **2020:** launch, restricted to low-income households (blue/yellow).
- **Late 2020 / Jan 2021:** extension to all income categories and landlords under France Relance; MPR Copropriétés.
- **Spring 2022:** temporary bonus (~+€1,000) for replacing fossil heating with renewable systems. It was announced before it took effect, so there is an anticipation risk.
- **2023:** exclusion of fossil (gas) boilers from eligibility.
- **2024:** reform splitting MPR into *par geste* and *Parcours accompagné*. The announced restrictions on *par geste* were partly reversed in spring 2024.
- **Mid-2025:** suspension of Accompagnée applications (budget and fraud).
- **2026:** check the current budget-law changes.

## 6. Output specification

One table (CSV or parquet), with **one row per change** and these columns:

| column | content |
|---|---|
| `text_id` | JORFTEXT / LEGIARTI identifier |
| `article` | article number |
| `date_announced` | first public announcement (press release, minister) |
| `date_jo` | publication in the Journal officiel |
| `date_effective` | entry into force |
| `date_applies_to` | which *dépôt de dossier* / quote / works date the rule applies to |
| `geste` | type of work/equipment (PAC air-eau, CET, insulation, etc.) |
| `income_cat` | bleu / jaune / violet / rose / all |
| `old_value`, `new_value` | amount, cap, or condition |
| `change_type` | amount / cap / eligibility / firm_rule / cumulation / procedure |
| `sources` | URLs (legal + corroborating) |
| `significance` | short note informed by press and trade-body commentary |

Keep the four dates separate. Anticipation and confounding (the 2022 energy crisis, CEE Coup de pouce revisions) are the main threats to event-study designs here.

## 7. Identification angles to keep in mind

- **Cross-sectional variation.** Changes differ by *geste* and by income category. This allows a firm-level exposure measure: a firm's pre-period mix of *gestes* × Δsubsidy. That gives a continuous-treatment, shift-share-type design, consistent with the existing PAC vs. CET setup.
- **References:**
  - de Chaisemartin & D'Haultfœuille (2024), *Difference-in-Differences Estimators of Intertemporal Treatment Effects*;
  - Callaway, Goodman-Bacon & Sant'Anna (2024), *Difference-in-Differences with a Continuous Treatment*.

## 8. Corroborating sources

- **Cour des comptes.** Reports on energy renovation and on the CEE (both 2024).
- **Sénat.** Commission of inquiry on energy renovation (2023).
- **ANAH.** Annual activity reports, the *Guide des aides financières*, France Rénov' pages.
- **Trade bodies.** CAPEB, FFB, AFPAC (heat pumps), Uniclima.
- **Consumers.** UFC-Que Choisir.
- **Comparators.** Effy, Hellio: historical grant tables, unofficial, cross-check only.
- Possible gap: no known academic paper systematically codes MPR's legal history. This is unverified.

## 9. Working preferences

- **Answers.** Short by default. Link content to references, and flag uncertainty or a lack of sources.
- **R code layout.** Segment scripts into RStudio-navigable sections (`# Section ----`). Put user-facing functions at the top, helpers below them, and helpers-of-helpers further down. Don't define named functions inside functions.
- **R code commentary.** Keep it minimal. Comment only particularly complex parts. No general commentary in headers.
