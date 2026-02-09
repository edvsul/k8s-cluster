## Prerequisites

# Install python3.12 >=

# Install ansible-core
python3 -m pip install ansible-core

# Run playbook

ansible-playbook -i ~/.rostr/generated/ansible-inventory.yaml extend_lvm.yaml