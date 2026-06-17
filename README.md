# ansible-k3s-management

Ansible playbooks that gracefully wind down k3s worker nodes before the
Solid NAS shuts down (cordon + drain) and bring them back when it boots
(uncordon). Modeled after
[ansible-emby-jellyfin-apple-silicon](https://github.com/marcosviniciusi/ansible-emby-jellyfin-apple-silicon)
— same lifecycle pattern, same systemd hook on the NAS.

## Why

Most workloads on this cluster mount NFS from the Solid NAS (and use
Longhorn replicas hosted on the workers themselves). When Solid halts,
NFS disappears and pods crash. Draining first lets pods stop cleanly
(SIGTERM + 60s grace) instead of being killed mid-write by NFS loss.

Drain runs in **force mode** (`--disable-eviction`) because Longhorn's
`instance-manager-*` PDBs with `MAX_UNAVAILABLE=0` block PDB-aware
eviction on every Longhorn pod when more than one worker drains — the
play would just time out and leave everything running. For a NAS
shutdown we want every worker empty, so we use the DELETE API and
accept that we're bypassing the disruption budget.

We only touch **worker** nodes (label `node-role.kubernetes.io/worker`).
Control-plane / etcd / master nodes are left alone.

## Layout

| file | purpose |
|---|---|
| `cordon-drain.yml` | cordon all workers, then drain in force mode — bypasses PDBs, 60s graceful termination per pod, capped at 2 min/node |
| `uncordon.yml` | uncordon all workers; waits up to 5 min for the API on boot |
| `status.yml` | `kubectl get nodes -l <worker-label> -o wide` |
| `group_vars/all.yml` | label selector, kubeconfig path, drain flags, API-wait knobs |
| `deploy/solid/` | systemd unit + wrapper + install README for the NAS |

## Quick start

Requires `kubectl` + a working kubeconfig wherever you run the playbook.

```bash
make status
make uncordon         # idempotent, safe to run any time
make cordon-drain     # evicts pods from all workers
```

Override variables ad-hoc:

```bash
make cordon-drain EXTRA='-e kubeconfig=/etc/rancher/k3s/k3s.yaml'
make status        EXTRA='-e worker_label=node-role.kubernetes.io/worker'
```

## Run from the Solid NAS (recommended)

See [deploy/solid/README.md](deploy/solid/README.md) for the systemd
hook that runs `uncordon` at boot and `cordon-drain` at shutdown.
