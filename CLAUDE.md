# Barnyard - Zsh-based VM Configuration Management

## Overview

Barnyard is Alan's sophisticated VM configuration management system, written entirely in Zsh. It's a direct alternative to Ansible/Puppet/Chef that embraces shell scripting rather than abstracting it away.

## Philosophy

"I didn't see the point in Ansible. Ten lines of YAML to say `mv here there`." - Alan

Instead of:
```yaml
- name: Move file from here to there
  ansible.builtin.copy:
    src: here
    dest: there
    remote_src: yes
```

Just write:
```bash
mv here there
```

## Architecture

### Core Components

1. **barnyard** - Main executable that runs on target VMs
   - Handles module execution lifecycle
   - Git-based configuration with GPG signing
   - Systemd integration for proper logging
   - Age encryption for secrets

2. **barnctl** - Control utility for managing Barnyard
   - Remote execution over SSH
   - Version management
   - Repository cloning and trust management

3. **Module System** - Individual configuration tasks
   - Simple shell scripts in `modules/` directory
   - Per-machine configurations in `machines/{hostname}/`
   - Configuration files use key=value format

### Security Model

- **GPG Signature Verification**: All git commits must be signed
- **SSH Key Authentication**: Dedicated barnyard SSH key
- **Age Encryption**: For sensitive configuration data
- **Systemd Integration**: Proper logging and service management

## Module Lifecycle

Modules can be configured to run:
- `once` - Run only on first deployment
- `always` - Run every time
- `diff` - Run only when configuration changes
- `never` - Disabled but present

## Configuration Format

```bash
# Special directives start with @
@apply=diff
@dependencies=postgresql users

# Regular configuration
version=16
listen+=10.255.252.1
user+=replicator

# Arrays
install+=postgresql-16
install+=alloy

# Base64 for multiline values
cert~base64=LS0tLS1CRUdJTi...
```

## Integration with Acres Infrastructure

Barnyard is Layer 2 in the four-layer architecture:
1. Terraform - VMs
2. **Barnyard - VM Configuration** (currently broken, being restored)
3. Cluster API - Kubernetes clusters
4. Kubernetes - Applications

### Current Work: Provider VM Monitoring

The `@provider` function in `/code/infrastructure/acreops-barnyard/code/common.zsh` has Alloy monitoring commented out:

```bash
# @ alloy_tls diff modules/tls_certificate name=alloy cn="alloy_${o_barnyard[hostname]//./_}"
# @ postgresql_hba diff line+="hostssl all $split[2]_$split[6]_$split[7]_grafana $(cidr $o_barnyard[hostname]) cert"
# @ wireguard_exporter dockerless=$dockerless
# @ alloy
```

This needs to be restored to get Sierra and other provider VMs reporting metrics properly.

## Zsh Sophistication

Barnyard leverages advanced Zsh features:
- Complex argument parsing with `zsh_parse_arguments`
- Associative arrays for configuration management
- Parameter expansion for string manipulation
- Heredocs with proper indentation handling
- Process substitution for secure key handling

## Module Examples

### Simple Module
```bash
# modules/motd/apply
cat <<EOF > /etc/motd
"Ever make mistakes in life? Let's make them birds. Yeah, they're birds now."
--Bob Ross
EOF
```

### Complex Module Pattern
```bash
@ locale diff
@ apt diff install+=postgresql-16 install+=alloy
@ postgresql_tls modules/tls_certificate name=postgresql
@ postgresql listen+=10.255.252.1
@ alloy_tls modules/tls_certificate name=alloy
@ alloy
```

## Benefits Over Traditional CM Tools

1. **No abstraction penalty** - It's just shell commands
2. **No YAML/DSL learning curve** - If you know shell, you know Barnyard
3. **Direct and readable** - What you write is what runs
4. **Full shell power** - No limitations of a DSL
5. **Git-native** - Configuration as code with proper signing

## Current Status

- Barnyard itself works but the infrastructure configuration is broken after the Cluster API refactor
- Provider VMs need Alloy deployment restored
- PWGE deployment needs to be restored for WireGuard metrics
- Sierra provider is the test case for getting monitoring working again