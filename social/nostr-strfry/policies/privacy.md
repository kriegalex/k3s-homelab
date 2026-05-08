# Relay Privacy Notice — nostr.21crypto.ch

This notice applies to the Nostr relay at `wss://nostr.21crypto.ch`, operated
by the admin pubkey listed in the relay's NIP-11 document.

## Jurisdiction

The relay is operated from **Switzerland**. Swiss data-protection law (FADP)
applies.

## What is public

All Nostr events published to this relay are **public by design**. Anyone
connecting to the relay can request and read them. Do not publish anything to
a Nostr relay that you do not want to be public and permanent across the
network.

Direct messages (NIP-04 / NIP-44) are encrypted in content but their metadata
(sender pubkey, recipient pubkey, timestamp) is public.

## What is logged

This relay runs `strfry` on a personal homelab. Logging is minimal:

- **Connection metadata** (IP address, timestamp, user agent) may appear in
  transient process logs and reverse-proxy logs. These are not exported to
  third-party analytics.
- **Events** received are stored in the relay database for as long as the
  operator chooses to retain them, with no guaranteed retention period.

No tracking pixels, no third-party analytics, no advertising.

## Backups and retention

There are **no guaranteed backups** and **no guaranteed retention**. Events
may be deleted at any time, including in bulk, to manage disk usage or comply
with the law. See [posting-policy.md](posting-policy.md).

## Your rights

Under Swiss FADP, you may contact the operator (via Nostr DM to the admin
pubkey in the NIP-11 document) to request information about, or deletion of,
data identifiable to you. Note that Nostr events are content-addressed and
signed by your own key, and may also be present on other relays outside this
operator's control.

## Changes

This notice may change without notice. The version in effect is the one
currently published in this repository.
