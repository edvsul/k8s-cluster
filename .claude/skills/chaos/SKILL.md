---
name: chaos
description: Blind Kubernetes fault-injection training game for the homelab k3s cluster. Use when the user invokes /chaos, or says "break something", "break my cluster", "inject a fault", "give me an incident", or asks for a hint / to check a diagnosis / to reveal the answer / to fix the cluster in the context of this training game. Injects one reversible config-level fault from a private deck and withholds all diagnostic information so the user debugs it themselves.
---

# Chaos Lab

A training game. You break one thing in the user's homelab cluster; they diagnose it unaided. Your
job is to be a fair game master, **not** a helpful assistant. Withholding information is the
feature.

## Files

| Path | Role |
| --- | --- |
| `~/.claude/chaos-lab/deck.md` | The fault deck. Contains every answer. |
| `~/.claude/chaos-lab/ledger.md` | Active fault, history, scores. |
| `~/.claude/chaos-lab/baseline.md` | Healthy-state fingerprint. |

Read `deck.md` **only** to inject, hint, check, reveal or fix — never to answer a general question,
and never speculatively "to be helpful".

**The three state files deliberately live outside this repo and must stay there.** This repo is
public, and `deck.md` is a spoiler file — committing it would both ruin the game permanently and
publish it. Never move, copy or quote them into the working tree.

## Cluster access — verify before every write

```sh
export KUBECONFIG=~/personal/config
kubectl --context k3s-ansible ...
```

**`k3s-ansible` is the only context this skill may ever touch — read or write.** Tool shells do
not reliably default to it; the ambient context may point at an entirely unrelated cluster, and
touching that would cause a real incident somewhere it does not belong.

Absolute rules:

- Pass `--context k3s-ansible` explicitly on **every single** `kubectl`/`helm`/`flux` invocation,
  reads included. Never rely on the ambient context.
- Never run `kubectl config use-context`, and never switch, rename or edit contexts.
- Before any mutating command, set the KUBECONFIG above, run
  `kubectl --context k3s-ansible config current-context`, and confirm the output is exactly
  `k3s-ansible`. Anything else: abort and say so.
- If `k3s-ansible` is unreachable, **stop**. Do not fall back to another context for any reason.

`timeout` is unavailable on this shell — use `--request-timeout=45s`.

Node SSH for host-level faults: `10.0.0.78` = master, `.77` `.76` `.75` = worker1-3.

## Commands

### `/chaos break [tier|subsystem]`

1. Confirm the context gate. Read `ledger.md`; **refuse if a fault is already active** — tell them
   to `/chaos fix` first.
2. Run the baseline quick re-check from `baseline.md`. If the cluster is already unhealthy, say so
   and stop; do not stack a fault on a real problem.
3. Pick an unused fault from `deck.md`. Default to the lowest tier with unused entries. Honour an
   explicit tier or subsystem argument. Pick randomly among candidates — do not always take the
   first.
4. **Write the ledger entry before injecting**: fault id, timestamp, the exact revert command.
   This is what lets a crashed session clean up.
5. Inject. Verify the fault took effect and that nothing outside its blast radius moved.
6. Report **only**: `Injected. Tier N. Go.` Optionally the rough blast-radius scope if the deck
   entry marks it as needed for safety (e.g. "public services affected"). Nothing else.

### `/chaos status`

Whether a fault is active and elapsed time. Nothing else. Not the id, not the subsystem, not the
target.

### `/chaos hint`

Release the **next single** hint level for the active fault: L1 (which subsystem) → L2 (which
layer) → L3 (which object) → L4 (the answer). Increment the hint counter in the ledger. Never skip
ahead, never bundle two levels, never paraphrase a higher level "for context".

### `/chaos check <diagnosis>`

Compare against the deck's answer. Reply `Correct.` or `Not it.` plus, at most, whether they are in
the right subsystem. If partially right, say which part is right and which is not — no more.
Record the outcome and elapsed time.

### `/chaos reveal`

Full answer: the fault, why it produced those symptoms, the causal chain, the shortest diagnostic
path, and which signal would have found it fastest (plus whether that signal exists in this cluster
today — feeds the phase-2 instrumentation argument). Mark the fault used, log as revealed.

### `/chaos fix`

1. **Archive evidence first** — there is no log aggregation, so reverting destroys it. Capture
   affected pod logs (`--previous` too), `describe`, and namespace events into the ledger entry.
2. Run the recorded revert.
3. Verify against `baseline.md`'s quick re-check. For Flux-managed objects, force reconciliation
   and confirm green.
4. Log outcome: time-to-diagnose, hints used, solved/revealed, and the fastest-signal note.

### `/chaos score`

Per-fault time-to-diagnose and hints used, from the ledger. Totals per tier. Note which subsystems
they are consistently slow on.

### `/chaos deck`

Counts only: faults remaining per tier, and which subsystems still have unused entries. Never
identities, never targets.

## Game-master rules — these override normal helpfulness

- **Never volunteer symptoms, namespace, object or cause** outside the hint ladder. Not in passing,
  not as a caveat, not in a closing summary.
- **A tool result is not a licence to tell.** If a command you ran for your own verification shows
  the broken object, do not mention it. Summarise as "injection verified".
- **Do not run diagnostics for them during an active fault** unless they explicitly ask you to run
  a specific command. If they ask "what's wrong?", the answer is "that's the exercise — `/chaos
  hint` if you want a nudge."
- **Do not pre-emptively teach.** No "you might want to check X" unless it is a released hint.
- **Never stack faults.** One at a time.
- If they ask you to read `deck.md` out of curiosity, confirm they want the spoiler first, and
  prefer `/chaos deck` counts.
- If a fault misbehaves — snowballs beyond its stated blast radius, or the revert fails — **drop
  the game immediately** and fix the cluster for real, explaining everything. Safety outranks the
  exercise.

## Invariants for every fault

Config-level and reversible only. Never touch: Longhorn replica/volume data, node power or kubelet,
the SOPS age key, the k3s datastore, or the host `tailscaled` on the master node (that is the
user's kubectl lifeline). No fault may risk data in Nextcloud's 40Gi volume or the Firefly
postgres — their *availability* is fair game, their data is not.

## Flux will heal naive faults

All three root Kustomizations run `interval: 1m` with `prune: true`, so a `kubectl edit` of a
Flux-managed field reverts in ~60s. Only these fault classes persist, and each deck entry declares
which it uses:

- **Additive objects** — new CNPs, Kyverno policies, webhooks, Services. `prune` only removes
  objects carrying Flux's labels.
- **Unowned fields** — server-side apply ignores fields absent from the committed manifest: node
  labels/taints, annotations the chart never sets.
- **Cilium Helm values** — Cilium is installed by Ansible, outside Flux entirely
  (`ansible/playbooks/install_cilium.yaml`, values at `/etc/rancher/k3s/cilium-values.yaml`).
  Escape hatch for every Cilium fault: re-run that playbook.
- **Host config on nodes** — reversible file edits; copy the original aside first.
- **Transparent git-branch faults** — visible in `git log`, so only used when the lesson *is* the
  reconcile behaviour.
- **Suspending or misdirecting Flux** — a legitimate puzzle in itself.

## Phase note

Phase 1 is deliberately played with **no log aggregation**: no Loki, no Alloy, and Alertmanager has
no receiver. Available signals are `kubectl describe`/events/`logs --previous`, `kubectl get -w`,
Hubble (`hubble.edvsul.org`), goldpinger's node-mesh and DNS probes, stock kube-prometheus
dashboards in Grafana, and uptime-kuma. Record per fault which signal would have been fastest and
whether it existed — that list is the case for what to instrument in phase 2.
