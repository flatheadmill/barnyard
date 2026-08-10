# Local smoke

Barnyard's local smoke is a disposable end-to-end run on real Linux. It proves the road from an unprepared machine to a converged machine: delivery of the executable, creation and return of machine identity, installation of repository access and trust, cloning of generated configuration, verified extraction, operator dispatch, applied state, and machine-wide serialization. The rig uses an OrbStack Ubuntu machine and a separate SSH Git server container so no part of the repository delivery path is replaced by a mounted directory.

Everything in the rig is synthetic. The machine, server, repositories, hostnames, keys, identities, and configuration exist only for the run and refer to no real infrastructure or organization.

## Purpose

The smoke runs when Barnyard's road changes: how a machine receives the executable, how it receives identity and repository access, what the compiler emits, what apply reads, how configuration and code are verified and extracted, how dispatch resolves, or how the apply lock behaves. Those changes cross seams that the focused tests deliberately separate, so a green unit suite is not enough evidence for them.

The smoke does not run for an operator conversion. An operator conversion changes work performed after dispatch rather than the road to dispatch, and the conversion queue contains roughly seventy operators; requiring this rig for each one would turn a valuable system check into ceremony. Converted operators keep their focused tests, while the smoke remains reserved for changes to the road they all travel.

## Shape of the rig

The machine is an amd64 Ubuntu noble OrbStack machine named `barnyard`. It begins without Zsh and is reachable through OrbStack's local SSH transport with passwordless sudo. Its short hostname is part of the contract: `/etc/hostname` contains `barnyard`, and the compiler emits configuration under `conf/machines/barnyard`.

The other endpoint is a container named `barnyard-git`, reachable from the machine at a stable synthetic OrbStack DNS name such as `barnyard-git.orb.local`. It runs sshd as an unprivileged `git` user and serves one bare repository at a synthetic path such as `/srv/git/barnyard.git`. Its deploy-key authorization permits only repository reads: no PTY, no forwarding, and no arbitrary shell. A forced `git-upload-pack` command is appropriate because the server exists to prove one read path rather than to imitate a general hosting service.

The repository contains two independently signed refs. A configuration ref contains the compiler's output for `barnyard` and identifies the selected code ref. The code ref contains one fixture extension and one fixture operator. Apply verifies and extracts both refs, so the rig signs both rather than allowing a signed configuration commit to conceal an unsigned code commit.

The fixture operator performs one harmless and observable convergence, such as atomically writing its configured value and running commit to `/var/lib/barnyard/smoke/converged`. It also exposes a hold point used only by the lock scenario. This fixture proves that the extracted extension loads, the named operator resolves, its JSON is read, its operation dispatches, and its applied marker advances; it does not stand in for a production operator.

The eventual rig belongs in a small repository-local directory containing a Zsh driver, the Git-server container definition, the synthetic manifest, and the fixture extension. Generated keys, repositories, volumes, logs, and known-host material belong to a temporary or ignored state directory. The driver has distinct create, run, and destroy phases so a failed run can preserve enough state to inspect before anything is removed.

## Credential isolation

Credential isolation is an invariant of the rig, not one step in its sequence. A disposable environment that reads ambient credentials has borrowed the operator's identity and is not disposable, even if every file it creates under its own directory is later removed.

Every GPG subprocess runs with `GNUPGHOME` set to a mode-0700 directory beneath the rig state. The throwaway signing keys are generated, listed, exported, signed with, and verified only through that keyring. No command may address the operator's default GPG home, and destroying the rig removes the whole synthetic keyring without changing the operator's keys.

Every Git subprocess that constructs, signs, seeds, or verifies the synthetic repository runs with `GIT_CONFIG_GLOBAL` set to a rig-owned configuration and `GIT_CONFIG_NOSYSTEM=1`. That configuration explicitly supplies a synthetic name and `.invalid` email address, requires commit signing, selects OpenPGP signing, names the synthetic signing fingerprint and signing program, and states the verification trust policy. A missing rig key or configuration is a hard failure before a commit can be created; Git must never fall back to an ambient `commit.gpgsign`, `gpg.format`, `user.signingKey`, personal key, or system configuration.

OrbStack's local SSH access to the disposable machine is a declared transport prerequisite and is distinct from repository signing identity. The rig does not use an ambient SSH signing key merely because an SSH agent is available.

## Keys and trust

Each role receives a separate generated key. A deploy-key pair authorizes machine-to-server repository reads: the server receives the public key, while bootstrap installs the private key as `/etc/barnyard/id_barnyard`. A Git-server host key identifies the container: its public key becomes the exact `known_hosts` entry for the hostname used in the repository URL, and bootstrap installs that entry as `/etc/barnyard/known_hosts`.

A generated OpenPGP key signs the configuration and code tips. Its private half remains in the rig keyring on the control side. Bootstrap receives only its public key and fingerprint, imports the public key into the machine's Barnyard keyring, and establishes the trust needed by the current verified extraction path. A second generated OpenPGP key creates the negative-signature case but is never imported or trusted by the machine.

The machine creates its own age identity during preparation. Its private key remains at `/etc/barnyard/age`; the public identity returned through Barnyard's commit output is placed at `conf/age/barnyard` before the final configuration is compiled. The fixture need not consume an age-encrypted value for this round trip to prove that machine identity is created on the agent side and returned to the control side without exposing the private key.

An SSH commit-signing key is a separate role again. It is not the deploy key and not the server host key. The current runner cannot trust it because Barnyard has no allowed-signers bootstrap property and points Git's SSH allowed-signers file at `/dev/null`; the rig preserves this as an explicit diagnostic lane rather than weakening the green OpenPGP path.

The resulting trust graph is narrow. OrbStack authorizes the control side to reach the machine. The Git server authorizes the machine's deploy public key. The machine pins the Git server host key. The machine trusts the synthetic OpenPGP commit signer. The configuration and code tips are signed by the corresponding private key held only in rig state. None of these roles borrows another role's key.

## Repository construction

Repository construction happens in a temporary worktree under the isolated Git and GPG environment. The code ref contains the fixture extension in the same layout apply will extract and load. The configuration source contains a manifest naming exactly the machine `barnyard`, the returned public age identity, and one named fixture operator. `barnyard control generate` produces the per-machine JSON and `order.json`; those generated artifacts, not a hand-written substitute, are committed to the configuration ref.

The configuration chooses the code ref explicitly. Both selected tips are signed by the rig's OpenPGP key before the bare repository is created. The bare repository is copied into a container volume and served only over SSH. The Ubuntu machine never sees the construction worktree or a host filesystem mount, because either shortcut would remove clone, host verification, deploy-key authentication, and fetch from the road being tested.

## Sequence

1. The driver preflights OrbStack, its Docker context, the required local programs, the isolated signing environment, and the absence of conflicting rig-owned machine and container names. An existing machine is adopted only through an explicit choice; otherwise the rig creates a fresh amd64 noble machine named `barnyard`.

2. The checked-out `barnyard` executable runs `barnyard control prepare ubuntu` against the OrbStack machine. Preparation uses the real remote bootstrap: it installs Zsh and the base tools, installs zshctl, copies that exact executable to `/usr/local/bin/barnyard`, and runs the agent-side Ubuntu preparation that creates `/etc/barnyard`, the age identity, and the Barnyard GPG home.

3. The driver retrieves the agent's Barnyard commit archive over SSH and unpacks its public age record into the temporary configuration source. It does not mount the machine filesystem or read `/etc/barnyard/age` directly.

4. Under the isolated Git and GPG environment, the driver assembles the code ref, compiles the manifest, checks that the result is addressed as `conf/machines/barnyard`, signs the configuration and code tips, and creates the bare repository.

5. The Git container starts with the bare repository, generated host key, and deploy public key. Before bootstrap, the rig establishes that the Ubuntu machine resolves the exact repository hostname. The pinned `known_hosts` line is constructed from the generated host public key rather than learned by trusting a network scan.

6. `barnyard control bootstrap` sends one payload containing the Git server's pinned host identity, the deploy private key, the OpenPGP public key and fingerprint, the repository URL, and the configuration branch. The agent validates the version and the payload shape before installing trust and access, cloning the repository over SSH, and recording the selected branch.

7. The driver checks the provisioning products without substituting for them: the installed executable and machine identity, Git `known_hosts`, deploy private key, Barnyard GPG keyring, bare mirror, and branch file. The checks establish that bootstrap created the state apply depends on; they do not rewrite or repair it.

8. `sudo barnyard agent apply` fetches, verifies, and extracts the selected configuration and code, loads the fixture extension, and dispatches the recorded operation. The driver checks the converged file and applied marker, then runs apply again and checks that the fixture's selected policy prevents an unintended second dispatch.

9. The lock scenario selects a fixture path that enters its hold point after apply owns the machine-wide lock. A second apply begins only after the first reports entry. The second invocation must fail immediately and identify the first holder; releasing the fixture allows the first invocation to finish successfully.

10. The negative-signature scenario advances the configuration ref to an unsigned or wrong-key-signed tip. Fetch and apply must fail before fixture dispatch, while the prior converged file and applied marker remain unchanged. Restoring a tip signed by the trusted synthetic key must allow an ordinary rerun to converge without cleanup or rollback machinery.

11. A successful run destroys the Git container, volume, temporary repositories, isolated Git configuration, GPG home, generated keys, and optionally the OrbStack machine. A failed run preserves them and prints the exact commands needed to inspect container logs, the bare repository, the machine, and Barnyard's state before the explicit destroy phase is used.

## Signature lanes

The required green lane uses OpenPGP-signed configuration and code tips because bootstrap and the current runner already share that trust contract. Signature checking remains enabled throughout; `--no-check-signature` would make the end-to-end run easier by removing one of the road segments it exists to prove.

The negative OpenPGP lane proves that a wrong or absent signature stops before dispatch and that rerun is sufficient once a trusted tip is restored. Barnyard currently checks only the selected tip with `git log -n 1 --format=%G?`, so the rig describes this evidence as tip verification rather than full-history verification.

The SSH-signing lane is initially an expected failure. A correctly SSH-signed tip cannot verify while `gpg.ssh.allowedSignersFile` is `/dev/null`, and bootstrap has no way to install an allowed-signers policy. Once Barnyard gains a distinct allowed-signers property and installs a file such as `/etc/barnyard/allowed_signers`, the trusted SSH case becomes a required success and a wrong-key or wrong-principal case remains a required failure. The signing key remains separate from repository access keys in both forms of the test.

## What the smoke proves

A green run proves real Ubuntu preparation from a machine without Zsh; delivery of the exact Barnyard executable under test; machine age-identity generation and public-identity return; strict bootstrap payload validation; pinned Git host identity and deploy-key access; clone and fetch from a separate server over SSH; compiler output addressed by the machine's actual short hostname; verified extraction of independently signed configuration and code refs; branch selection; extension discovery; named-operator resolution; JSON configuration reading; operation dispatch; applied-marker behavior; machine-wide apply-lock contention; fail-fast rejection of an untrusted tip; and successful convergence by rerun after trusted state is restored.

These claims are deliberately about Barnyard's road. The synthetic fixture proves that the road reaches an operator and carries its configuration, not that any other operator converges its own domain.

## What the smoke does not prove

The smoke does not prove the correctness of a production operator, including an operator converted from the legacy queue. It does not exercise real service configuration, production secrets, secret rotation, a hardware-backed key, or access to an external provider. A green result cannot be used as evidence that PostgreSQL, WireGuard, DNS, TLS, or any other operator-specific system is correctly configured.

It does not prove production networking, DNS, firewall policy, cloud-init, bastion behavior, hosted Git policy, provider-side deploy-key controls, or the availability characteristics of a real repository service. The container proves the SSH Git protocol and the trust path Barnyard uses; it does not reproduce a hosted provider's authorization or operational controls.

It does not prove systemd scheduling, journal collection, unattended convergence, reboot behavior, or long-running service lifecycle. Apply is invoked deliberately for the smoke, and the observable fixture is narrower than a service managed across boots.

It does not prove another Linux distribution, arm64 behavior, production hardware, or production kernel topology. The selected target is amd64 Ubuntu noble, and OrbStack machines and containers share OrbStack's Linux substrate; this provides real Linux userspace, process, filesystem, SSH, Git, and networking behavior without reproducing a production hypervisor or physical host.

It does not prove fleet concurrency or orchestration across several machines. The lock scenario proves contention on one machine, not scheduling fairness, cross-machine coordination, throughput, or behavior under a fleet-wide rollout.

It does not prove upgrades, migration from an older Barnyard layout, preservation of unmanaged legacy state, rollback, or automated recovery. The machine is deliberately disposable and starts in the current shape. Barnyard's failure model remains fail, correct the cause, and rerun; the smoke verifies rerun after its controlled signature failure but does not claim a rollback system.

It does not prove full Git history authenticity. The current implementation verifies the selected configuration and code tips rather than every ancestor, and the rig must not describe a valid tip as a verified history.

It does not prove deterministic preparation while the installer consumes public package repositories and clones the `main` branch of zshctl. A green run proves what those sources delivered during that run. It cannot prove that a later run receives the same parser or dependency versions.

It does not prove performance, resource ceilings, network partitions, repository outages, disk exhaustion, interrupted package installation, or every partial bootstrap failure. Focused tests retain responsibility for deterministic failure branches; the smoke provides one happy road, explicit signature rejection, lock contention, and rerun.

## Known conditions

**The payload carries material, not claims about the machine.** Bootstrap once derived an expected hostname from the text after `@` in the SSH destination and sent it for the agent to check. The OrbStack destination `barnyard@orb` implies `orb` while `/etc/hostname` says `barnyard`, so the rig would have failed a correct machine. The expectation block is gone rather than made explicit: a machine's hostname comes from Terraform and its distribution from `/etc/os-release`, the control side has no independent source for either, and reaching the intended machine is settled by the pinned host key on the SSH connection. The rig therefore needs no expected-hostname input, and the OrbStack destination may differ from the machine name without arrangement.

**The SSH-signing lane must currently fail.** The runner points Git's SSH allowed-signers file at `/dev/null`, and bootstrap has no allowed-signers property. OpenPGP signing provides the initial green route. SSH signing remains a named diagnostic until Barnyard can provision and select explicit SSH commit trust.

**Both selected refs require signatures.** Apply verifies the configuration ref and then the code ref named by that configuration. The repository builder signs both tips and tests failures without describing one signed ref as a signed deployment.

**Preparation is not hermetic.** The Ubuntu prepare path uses apt and clones zshctl from its `main` branch. This is the real road today and therefore remains in the smoke, but it requires public network access and admits upstream drift. Deterministic preparation requires a pinned zshctl artifact rather than a rig-only substitute.

**Controller SSH trust is ambient.** Prepare and bootstrap invoke SSH directly, bootstrap requires strict host checking, and neither command accepts a dedicated control-side SSH configuration. OrbStack's managed local access is an explicit prerequisite for the first rig. A later isolated transport seam should be supported by Barnyard itself rather than by editing a user's SSH state or placing a deceptive wrapper in `PATH`.

**Machine identity retrieval is manual.** Agent preparation creates the Barnyard commit archive, but the current road has no control-side command that retrieves it. The driver reaches the existing agent command over SSH and unpacks the public result. Keeping this transfer visible is preferable to mounting the machine filesystem, which would prove a different path.

**The short hostname is load-bearing.** The machine is named `barnyard`, `/etc/hostname` is `barnyard`, and generated configuration lives under `conf/machines/barnyard`. Apply reads `/etc/hostname` to find that directory, so the name on the machine and the name in the compiler's output are the same string or the run finds nothing. The Git server may use an OrbStack FQDN because that name belongs to repository transport; the machine identity may not be silently expanded to one.
