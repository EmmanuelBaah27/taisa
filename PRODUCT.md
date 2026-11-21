# Product

<!-- impeccable:product-schema 1 -->

## Platform

ios

## Users

Taisa is built first for Baah: a professional who wants to capture everyday work naturally and turn it into grounded career reflection without maintaining a conventional task or performance-management system.

## Product Purpose

Taisa is a personal AI career companion. It helps the user capture daily work by voice or text, preserve trustworthy evidence of what happened, understand wins and challenges, and turn reflection into concrete Actions and CV-worthy material. Success means the user can return to an accurate, useful account of their work and decide what to do next without the product inventing achievements or commitments.

## Positioning

Taisa connects private, device-authoritative work records with evidence-grounded coaching. Its distinctive mechanism is not generic task management or generic chat: conversation, Actions, Goals, evidence, reviews, and career progress remain linked to accepted records that the user can inspect and correct.

## Operating Context

- The user records or types reflections about work as the week unfolds.
- Senior Self helps interpret those reflections while distinguishing inference from known facts.
- Career Work holds Goals, Milestones, canonical Actions, evidence, and their history.
- Home surfaces selected current attention and review material rather than every stored record.
- The shipping product is a native SwiftUI iPhone and iPad application. The React Native application remains a migration source until its required behavior and unique work are accounted for.

## Capabilities and Constraints

- Readable personal data is encrypted and device-authoritative.
- The device UUID remains the v1 user identity boundary; product work must not introduce application authentication accidentally.
- An Action is an independently managed concrete commitment. A Goal is a broader outcome, a Milestone marks progress within one Goal, and a checklist item is a lightweight supporting step inside one Action.
- Product behavior must never silently create, merge, complete, drop, reopen, delete, reprioritize, or reschedule an Action.
- Claims about impact, quality, reception, or progress require evidence; completing an Action records only the factual completion.
- Native Product work is design-system-first. Every authored component, interaction style, token, and icon must use an approved shared TaisaDesignSystem contract and Central Icons mapping.
- Preserve SwiftUI and the iOS/iPadOS 26+ deployment target.
- Ordinary browsing and local mutation must not require AI, provider, or network access.

## Brand Commitments

The product is named Taisa. Its voice is thoughtful, grounded, direct, and collaborative. It should help the user think without overstating certainty, diagnosing them from missing information, or turning every reflection into a productivity intervention.

## Evidence on Hand

- Approved live product Scope, Plan, acceptance, and gate evidence are held in the Taisa Linear project.
- Versioned architecture, storage, migration, verification, and design-system contracts live in this repository.
- Native preview fixtures under `apple/TaisaPreview` provide synthetic product states; they are not user evidence and must not be presented as real outcomes.
- No testimonials, public customer claims, performance benchmarks, or third-party endorsements are authorized for invention.

## Product Principles

1. Ground guidance in accepted evidence and label inference honestly.
2. Keep the user authoritative over commitments, corrections, and personal records.
3. Reduce the most consequential uncertainty before adding structure or advice.
4. Make private work understandable and useful without requiring administrative upkeep.
5. Prefer coherent native behavior and shared system contracts over feature-local novelty.

## Accessibility & Inclusion

Shipping native surfaces must support Dynamic Type, VoiceOver, increased contrast, Reduce Motion and transparency, keyboard use, safe areas, and at least 44-point interactive targets across supported iPhone and iPad configurations. Meaning must not depend on color or iconography alone.
