# 00 — Project Objective

## Objective

Build **Vizoure NMS**, an enterprise network monitoring system based on Zabbix 7.4.x,
fully rebranded as Vizoure (name, logos, UI text, titles, themes), and deployable as a
ready-to-use product. It provides device monitoring, problem detection and alerting,
dashboards, maps and reporting through the rebranded web UI and the JSON-RPC API.

## Scope now

The rebranded Vizoure NMS itself (rebrand, build, install, configuration) as it exists
in this repo.

## Planned later (out of scope for now)

A separate custom Vizoure web portal that will sit on top of Vizoure NMS and use its
JSON-RPC API. Do not create or plan any portal code until instructed.

## Open items from Step 1 that bear on this objective ⚠️ needs confirmation

- The vendored reference tree at `zabbix-master/` reports `ZABBIX_VERSION =
  '8.0.0rc2'`, not 7.4.x — it does not match the "Zabbix 7.4.x" stated here and in
  `README.md`. Unconfirmed whether the objective's version target is still
  7.4.x or has moved.
- This working directory is not a git repository, so "based on … as it exists in this
  repo" cannot currently be tied to any commit history.
