#!/usr/bin/env bash
set -uo pipefail

readonly SELF_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SELF_NAME="$(basename "${BASH_SOURCE[0]}")"
readonly ROOT_PATH="$(cd "${SELF_PATH}/../.." && pwd)"

[[ -z "${TESTS_DOCKER:-}" ]] \
    && echo "Please run tests with launcher.sh!" && exit 1

export TADS_ENV=test
readonly _tads="${ROOT_PATH}/tads"

# *** Functions
test_is_version_gte () {
    assertTrue "is_version_gte 2.0.0 1"
    assertTrue "is_version_gte 2.0.0 1.0"
    assertTrue "is_version_gte 2.0.0 1.0.0"
    assertTrue "is_version_gte 2.0.0 1.9.0"
    assertTrue "is_version_gte 2.0.0 1.9.9"
    assertTrue "is_version_gte 2.0.0 2.0.0"

    assertFalse "is_version_gte 1 2.0.0"
    assertFalse "is_version_gte 1.0 2.0.0"
    assertFalse "is_version_gte 1.0.0 2.0.0"
    assertFalse "is_version_gte 1.9.0 2.0.0"
    assertFalse "is_version_gte 1.9.9 2.0.0"

    assertFalse "is_version_gte '' 2.0.0"
    assertFalse "is_version_gte 2.0.0"
    assertFalse "is_version_gte"
    assertFalse "is_version_gte string 2.0.0"
    assertFalse "is_version_gte 2.0.0 string"
}

# *** Common
test_usage () {
    local result

    result="$(${_tads})"
    assertEquals "usage exit code should be 1" 1 "$?"
    assertContains "usage should be printed" \
        "${result}" "Usage"
}

# *** Vagrant
test_vagrant_usage () {
    local result

    result="$(${_tads} vagrant)"
    assertEquals "usage exit code should be 1" 1 "$?"
    assertContains "usage should be printed" \
        "${result}" "Usage"
}

test_vagrant_up_not_installed () {
    local result

    result="$(${_tads} vagrant up)"
    assertEquals "Exit code should be 1" 1 "$?"
    assertContains "Warning msg should be printed" \
        "${result}" "Vagrant must be installed on your local machine"
}

test_vagrant_up_outdated_version () {
    local result

    mock_command vagrant "Vagrant 1.0.0"

    result="$(${_tads} vagrant up)"
    assertEquals "Exit code should be 1" 1 "$?"
    assertContains "Warning msg should be printed" \
        "${result}" "Please upgrade it to at least version 2.0"
}

test_vagrant_up_virtualbox_not_installed () {
    local result

    mock_command vagrant "Vagrant 2.0.0"

    result="$(${_tads} vagrant up)"
    assertEquals "Exit code should be 1" 1 "$?"
    assertContains "Warning msg should be printed" \
        "${result}" "VirtualBox must be installed on your local machine"
}

test_vagrant_up_not_configured () {
    local result

    mock_command vagrant "Vagrant 2.0.0"
    mock_command vboxmanage

    result="$(${_tads} vagrant up)"
    assertEquals "Exit code should be 1" 1 "$?"
    assertContains "Warning msg should be printed" \
        "${result}" "Please copy vagrant/vagrant.sample.yml to vagrant/vagrant.yml and edit it first!"
}

test_vagrant_up () {
    local result

    mock_command vagrant "Vagrant 2.0.0"
    mock_command vboxmanage
    mock_file "${ROOT_PATH}/vagrant/vagrant.yml"

    result="$(${_tads} vagrant up)"
    assertEquals "Exit code should be 0" 0 "$?"
    assertMockedCmdCalled "vagrant" "vagrant up"
}

# *** Terraform
test_terraform_usage () {
    local result

    result="$(${_tads} terraform)"
    assertEquals "usage exit code should be 1" 1 "$?"
    assertContains "usage should be printed" \
        "${result}" "Usage"
}

test_terraform_apply_not_installed () {
    local result

    result="$(${_tads} terraform production apply)"
    assertEquals "Exit code should be 1" 1 "$?"
    assertContains "Warning msg should be printed" \
        "${result}" "Terraform must be installed on your local machine"
}

test_terraform_apply_outdated_version () {
    local result

    mock_command terraform "Terraform v0.1"

    result="$(${_tads} terraform production apply)"
    assertEquals "Exit code should be 1" 1 "$?"
    assertContains "Warning msg should be printed" \
        "${result}" "Please upgrade it to at least version 0.12"
}

test_terraform_apply_unknown_env () {
    local result

    mock_command terraform "Terraform v0.12.12"

    result="$(${_tads} terraform test apply)"
    assertEquals "Exit code should be 1" 1 "$?"
    assertContains "Warning msg should be printed" \
        "${result}" "Terraform ENVIRONMENT does not exist:"
}

test_terraform_apply () {
    local result

    local additional_mock_code
    read -r -d '' additional_mock_code <<'EOF'
case "$@" in
    "output ssh_user")
        echo "ubuntu"
        ;;

    "output -json manager_ips")
        echo '["254.254.254.1","254.254.254.2","254.254.254.3"]'
        ;;

    "output -json worker_ips")
        echo '["254.254.254.4"]'
        ;;
esac
EOF

    local expected_inventory
    read -r -d '' expected_inventory <<'EOF'
# Inventory file for production environment
# Automatically generated by ./tads terraform

# Manager nodes
manager-1 ansible_user=ubuntu ansible_host=254.254.254.1
manager-2 ansible_user=ubuntu ansible_host=254.254.254.2
manager-3 ansible_user=ubuntu ansible_host=254.254.254.3

# Worker nodes
worker-1 ansible_user=ubuntu ansible_host=254.254.254.4

[production]
manager-[1:3]
worker-[1:1]

[docker:children]
production

[production_encrypted:children]
production

[dockerswarm_manager]
manager-[1:3]

[dockerswarm_worker]
worker-[1:1]

[docker:vars]
dockerswarm_iface=eth0
EOF

    mock_command terraform "Terraform v0.12.12" "${additional_mock_code}"

    result="$(${_tads} terraform production apply)"
    assertEquals "Exit code should be 0" 0 "$?"
    assertMockedCmdCalled "terraform" "terraform apply"
    assertFileContentEquals "${ROOT_PATH}/ansible/inventories/production" "${expected_inventory}"
    rm -f "${ROOT_PATH}/ansible/inventories/production"
}

# *** Ansible
test_ansible_usage () {
    local result

    result="$(${_tads} ansible)"
    assertEquals "usage exit code should be 1" 1 "$?"
    assertContains "usage should be printed" \
        "${result}" "Usage"
}

test_ansible_not_installed () {
    local result

    result="$(${_tads} ansible localhost -m command -a ls)"
    assertEquals "usage exit code should be 1" 1 "$?"
    assertContains "Warning msg should be printed" \
        "${result}" "Ansible must be installed on your local machine"
}

test_ansible_outdated_version () {
    local result

    mock_command ansible "ansible 2.7.0"

    result="$(${_tads} ansible localhost -m command -a ls)"
    assertEquals "usage exit code should be 1" 1 "$?"
    assertContains "Warning msg should be printed" \
        "${result}" "Please upgrade it to at least version 2.8"
}

test_ansible_local () {
    local result

    mock_command ansible "ansible 2.9.1"

    result="$(${_tads} ansible localhost -m command -a ls)"
    assertEquals "Exit code should be 0" 0 "$?"
    assertMockedCmdCalled \
        "ansible" \
        "ansible -i ${ROOT_PATH}/ansible/inventories/localhost -D -c local -m command -a ls"
}

test_ansible_vagrant_not_created () {
    local result

    mock_command ansible "ansible 2.9.1"

    result="$(${_tads} ansible vagrant -m command -a ls)"
    assertEquals "Exit code should be 1" 1 "$?"
    assertContains "Warning msg should be printed" \
        "${result}" "Impossible to find vagrant auto-generated inventory file"
}

test_ansible_vagrant () {
    local result

    mock_command ansible "ansible 2.9.1"
    mock_file "${ROOT_PATH}/vagrant/.vagrant/provisioners/ansible/inventory/vagrant_ansible_inventory"

    result="$(${_tads} ansible vagrant -m command -a ls)"
    assertEquals "Exit code should be 0" 0 "$?"
    assertMockedCmdCalled \
        "ansible" \
        "ansible -i ${ROOT_PATH}/vagrant/.vagrant/provisioners/ansible/inventory/vagrant_ansible_inventory -D -m command -a ls"
}

test_ansible_production_not_created () {
    local result

    mock_command ansible "ansible 2.9.1"

    result="$(${_tads} ansible production -m command -a ls)"
    assertEquals "Exit code should be 1" 1 "$?"
    assertContains "Warning msg should be printed" \
        "${result}" "Unknown ENVIRONMENT: production"
}

test_ansible_production () {
    local result

    mock_command ansible "ansible 2.9.1"
    mock_file "${ROOT_PATH}/ansible/inventories/production"

    result="$(${_tads} ansible production -m command -a ls)"
    assertEquals "Exit code should be 0" 0 "$?"
    assertMockedCmdCalled "ansible" "ansible -i ${ROOT_PATH}/ansible/inventories/production -D -m command -a ls"
}

# *** Ansible-Playbook
test_ansible_playbook_usage () {
    local result

    result="$(${_tads} ansible-playbook)"
    assertEquals "usage exit code should be 1" 1 "$?"
    assertContains "usage should be printed" \
        "${result}" "Usage"
}

test_ansible_playbook_not_installed () {
    local result

    result="$(${_tads} ansible-playbook localhost all)"
    assertEquals "usage exit code should be 1" 1 "$?"
    assertContains "Warning msg should be printed" \
        "${result}" "Ansible must be installed on your local machine"
}

test_ansible_playbook_outdated_version () {
    local result

    mock_command ansible "ansible 2.7.0"

    result="$(${_tads} ansible-playbook localhost all)"
    assertEquals "usage exit code should be 1" 1 "$?"
    assertContains "Warning msg should be printed" \
        "${result}" "Please upgrade it to at least version 2.8"
}

test_ansible_playbook_local () {
    local result

    mock_command ansible "ansible 2.9.1"
    mock_command ansible-galaxy
    mock_command ansible-playbook

    result="$(${_tads} ansible-playbook localhost all)"
    assertEquals "Exit code should be 0" 0 "$?"
    assertMockedCmdCalled \
        "ansible-playbook" \
        "ansible-playbook -i ${ROOT_PATH}/ansible/inventories/localhost -D -c local ${ROOT_PATH}/ansible/all.yml --ask-become-pass"
}

test_ansible_playbook_requirements () {
    local result

    mock_command ansible "ansible 2.9.1"
    mock_command ansible-galaxy
    mock_command ansible-playbook

    result="$(${_tads} ansible-playbook localhost all)"
    assertMockedCmdCalled \
        "ansible-galaxy" \
        "ansible-galaxy role install -r ${ROOT_PATH}/ansible/requirements.yml"
}

test_ansible_playbook_vagrant_not_created () {
    local result

    mock_command ansible "ansible 2.9.1"
    mock_command ansible-galaxy
    mock_command ansible-playbook

    result="$(${_tads} ansible-playbook vagrant all)"
    assertEquals "Exit code should be 1" 1 "$?"
    assertContains "Warning msg should be printed" \
        "${result}" "Impossible to find vagrant auto-generated inventory file"
}

test_ansible_playbook_vagrant () {
    local result

    mock_command ansible "ansible 2.9.1"
    mock_command ansible-galaxy
    mock_command ansible-playbook
    mock_file "${ROOT_PATH}/vagrant/.vagrant/provisioners/ansible/inventory/vagrant_ansible_inventory"

    result="$(${_tads} ansible-playbook vagrant all)"
    assertEquals "Exit code should be 0" 0 "$?"
    assertMockedCmdCalled \
        "ansible-playbook" \
        "ansible-playbook -i ${ROOT_PATH}/vagrant/.vagrant/provisioners/ansible/inventory/vagrant_ansible_inventory -D ${ROOT_PATH}/ansible/all.yml --ask-become-pass"
}

test_ansible_playbook_production_not_created () {
    local result

    mock_command ansible "ansible 2.9.1"
    mock_command ansible-galaxy
    mock_command ansible-playbook

    result="$(${_tads} ansible-playbook production all)"
    assertEquals "Exit code should be 1" 1 "$?"
    assertContains "Warning msg should be printed" \
        "${result}" "Unknown ENVIRONMENT: production"
}

test_ansible_playbook_production_no_key () {
    local result

    mock_command ansible "ansible 2.9.1"
    mock_command ansible-galaxy
    mock_command ansible-playbook
    mock_file "${ROOT_PATH}/ansible/inventories/production"

    result="$(${_tads} ansible-playbook production all)"
    assertEquals "Exit code should be 1" 1 "$?"
    assertContains "Warning msg should be printed" \
        "${result}" "Vault key not found for ENVIRONMENT: production"
}

test_ansible_playbook_production () {
    local result

    mock_command ansible "ansible 2.9.1"
    mock_command ansible-galaxy
    mock_command ansible-playbook
    mock_file "${ROOT_PATH}/ansible/inventories/production"
    mock_file "${ROOT_PATH}/ansible/vault_keys/production"

    result="$(${_tads} ansible-playbook production all)"
    assertEquals "Exit code should be 0" 0 "$?"
    assertMockedCmdCalled \
        "ansible-playbook" \
        "ansible-playbook -i ${ROOT_PATH}/ansible/inventories/production -D --vault-id production@/tmp/tads/ansible/vault_keys/production ${ROOT_PATH}/ansible/all.yml"
}

# *** Ansible-Vault
test_ansible_vault_usage () {
    local result

    result="$(${_tads} ansible-vault)"
    assertEquals "usage exit code should be 1" 1 "$?"
    assertContains "usage should be printed" \
        "${result}" "Usage"
}

test_ansible_vault_init_key () {
    local result

    mock_command ansible "ansible 2.9.1"

    result="$(${_tads} ansible-vault test init-key)"
    assertEquals "usage exit code should be 0" 0 "$?"
    assertFileExists "${ROOT_PATH}/ansible/vault_keys/test"

    local key
    key="$(cat "${ROOT_PATH}/ansible/vault_keys/test")"
    assertEquals "Key must be 256 characters long" ${#key} 256

    rm -f "${ROOT_PATH}/ansible/vault_keys/test"
}

test_ansible_vault_no_key () {
    local result

    mock_command ansible "ansible 2.9.1"

    result="$(${_tads} ansible-vault production view)"
    assertEquals "usage exit code should be 1" 1 "$?"
    assertContains "Warning msg should be printed" \
        "${result}" "Vault key not found for ENVIRONMENT: production"
}

test_ansible_vault () {
    local result

    mock_command ansible "ansible 2.9.1"
    mock_command ansible-vault
    mock_file "${ROOT_PATH}/ansible/vault_keys/production"

    result="$(${_tads} ansible-vault production view)"
    assertEquals "usage exit code should be 0" 0 "$?"
    assertMockedCmdCalled \
        "ansible-vault" \
        "ansible-vault view --vault-id production@${ROOT_PATH}/ansible/vault_keys/production"
}




# *** shunit2
oneTimeSetUp () {
    # shellcheck source=scripts/tests/utils.sh
    source "${SELF_PATH}/utils.sh"

    # shellcheck source=scripts/includes/common.sh
    source "${SELF_PATH}/../includes/common.sh"
}

setUp () {
    setup_mocking
}

tearDown () {
    teardown_mocking
}

# shellcheck source=scripts/tests/shunit2.sh
source "${SELF_PATH}/shunit2.sh"
