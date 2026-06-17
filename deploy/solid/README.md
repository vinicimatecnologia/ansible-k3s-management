# Solid NAS → k3s worker lifecycle (systemd)

Systemd unit on the NAS that:

- runs `make uncordon` at boot once network is up — workers become
  schedulable again as soon as the NAS returns
- runs `make cordon-drain` on shutdown BEFORE the network is torn down,
  so pods using NFS/Longhorn storage from the NAS get a chance to stop
  gracefully instead of crashing on storage loss

## Prerequisites (run on the NAS as root)

1. Ansible installed
   ```bash
   ansible --version
   ```

2. kubectl installed and a kubeconfig at `/root/.kube/config`
   ```bash
   # Install kubectl (Debian/OMV):
   curl -fsSL -o /usr/local/bin/kubectl \
     "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
   chmod 0755 /usr/local/bin/kubectl

   # Copy the k3s kubeconfig from any master (cole/tess/yuna) and
   # rewrite the server address to a master-reachable IP:
   mkdir -p /root/.kube
   scp root@<master>:/etc/rancher/k3s/k3s.yaml /root/.kube/config
   sed -i 's|127\.0\.0\.1|<master-ip>|' /root/.kube/config
   chmod 600 /root/.kube/config

   # Verify:
   kubectl get nodes
   ```

3. The IaC checkout at `/opt/ansible-k3s-management`
   ```bash
   git clone https://github.com/marcosviniciusi/ansible-k3s-management.git \
     /opt/ansible-k3s-management
   ```

## Install

```bash
cd /opt/ansible-k3s-management
chmod 755 deploy/solid/wrap.sh
install -m 0644 deploy/solid/k3s-lifecycle.service \
  /etc/systemd/system/k3s-lifecycle.service
systemctl daemon-reload
systemctl enable k3s-lifecycle.service
```

## Verify (no destructive action)

```bash
# Quick read-only check that the playbooks resolve and kubectl works:
cd /opt/ansible-k3s-management
make status

# Dry-run uncordon (idempotent — uncordoning an uncordoned node is a no-op):
make uncordon
```

When ready for an end-to-end test, run the unit explicitly:

```bash
# Will cordon + drain all workers — workloads WILL be evicted!
systemctl start k3s-lifecycle.service   # ExecStart = uncordon
systemctl stop k3s-lifecycle.service    # ExecStop  = cordon-drain
```

Follow logs with `journalctl -u k3s-lifecycle.service -f`.

## How shutdown timing works

- `Type=oneshot` + `RemainAfterExit=yes` keeps the unit `active` during
  normal NAS uptime, so systemd will fire `ExecStop` when the host goes
  down (`shutdown -h now`, `reboot`, UPS-triggered halt — all funnel
  through `shutdown.target`).
- Default ordering puts this unit `Before=shutdown.target` and ordered
  against `network.target`, so cordon+drain runs while the network is
  still up — kubectl on the NAS can reach the API server on the masters.
- Per-node drain is capped at 2 minutes (`--timeout=120s` in
  `group_vars/all.yml`), then we log and move on. Whole-unit cap is
  15 minutes (`TimeoutStopSec=900`) — past that systemd kills the
  wrapper and the shutdown continues even if some pods are still
  terminating.
- Drain runs in force mode (`--disable-eviction --grace-period=60`)
  — bypasses PodDisruptionBudgets, gives each pod 60s to terminate
  cleanly. Required because Longhorn's instance-manager PDBs
  (`MAX_UNAVAILABLE=0`) deadlock PDB-aware drain across multiple
  workers.

## Disable

```bash
systemctl disable --now k3s-lifecycle.service
rm /etc/systemd/system/k3s-lifecycle.service
systemctl daemon-reload
```

## Troubleshooting

- `journalctl -u k3s-lifecycle.service -n 200 --no-pager` — full last run.
- API not reachable from solid: check `kubectl get nodes` works as root.
  The kubeconfig server address must NOT be `127.0.0.1` (the loopback of
  a master); rewrite it to that master's reachable LAN IP.
- Drain stuck on a node: shouldn't happen in force mode (PDBs bypassed),
  but if it does the per-node `--timeout=120s` will fire and the play
  moves on with a failure logged. Likely cause: a finalizer or terminating
  pod that ignores SIGTERM.
- Want to skip a specific worker? Override the label selector for one
  run:
  ```bash
  make cordon-drain EXTRA='-e worker_label=node-role.kubernetes.io/worker,kubernetes.io/hostname!=aloy'
  ```
