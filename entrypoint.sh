#!/bin/bash
set -e

################################################################################
# Aurora Serverless v2 PostgreSQL - Entrypoint
################################################################################

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TERRAFORM_DIR="${SCRIPT_DIR}/terraform"

log() {
    echo "[$(date '+%H:%M:%S')] $1"
}

error() {
    echo "[$(date '+%H:%M:%S')] ERROR: $1" >&2
    exit 1
}

################################################################################
# Initialize Terraform
################################################################################
init_terraform() {
    log "Initializing Terraform..."
    cd "${TERRAFORM_DIR}"

    local bucket="${TF_BACKEND_BUCKET:-}"
    local key="${TF_BACKEND_KEY:-aurora/${TF_VAR_instance}/terraform.tfstate}"
    local region="${TF_BACKEND_REGION:-${TF_VAR_aws_region:-us-east-1}}"
    local dynamodb="${TF_BACKEND_DYNAMODB_TABLE:-}"

    if [[ -n "${bucket}" ]]; then
        local args="-backend-config=bucket=${bucket}"
        args="${args} -backend-config=key=${key}"
        args="${args} -backend-config=region=${region}"
        [[ -n "${dynamodb}" ]] && args="${args} -backend-config=dynamodb_table=${dynamodb}"
        
        log "Using S3 backend: s3://${bucket}/${key}"
        terraform init -input=false -reconfigure ${args}
    else
        log "Using local backend"
        cat > backend_override.tf <<EOF
terraform {
  backend "local" {
    path = "${TF_VAR_instance}.tfstate"
  }
}
EOF
        terraform init -input=false -reconfigure
    fi
}

################################################################################
# Set GitHub Actions Outputs
################################################################################
set_outputs() {
    log "Setting outputs..."
    cd "${TERRAFORM_DIR}"
    
    local outputs
    outputs=$(terraform output -json 2>/dev/null || echo "{}")
    
    if [[ -n "${GITHUB_OUTPUT}" ]]; then
        echo "cluster_endpoint=$(echo "${outputs}" | jq -r '.cluster_endpoint.value // empty')" >> "${GITHUB_OUTPUT}"
        echo "cluster_arn=$(echo "${outputs}" | jq -r '.cluster_arn.value // empty')" >> "${GITHUB_OUTPUT}"
        echo "cluster_id=$(echo "${outputs}" | jq -r '.cluster_id.value // empty')" >> "${GITHUB_OUTPUT}"
        echo "secret_arn=$(echo "${outputs}" | jq -r '.secret_arn.value // empty')" >> "${GITHUB_OUTPUT}"
        echo "database_name=$(echo "${outputs}" | jq -r '.database_name.value // empty')" >> "${GITHUB_OUTPUT}"
        echo "master_username=$(echo "${outputs}" | jq -r '.master_username.value // empty')" >> "${GITHUB_OUTPUT}"
        echo "port=$(echo "${outputs}" | jq -r '.port.value // empty')" >> "${GITHUB_OUTPUT}"
        echo "security_group_id=$(echo "${outputs}" | jq -r '.security_group_id.value // empty')" >> "${GITHUB_OUTPUT}"
        echo "connection_string=$(echo "${outputs}" | jq -r '.connection_string.value // empty')" >> "${GITHUB_OUTPUT}"
        log "Outputs set successfully"
    else
        echo "${outputs}" | jq '.'
    fi
}

################################################################################
# Main
################################################################################
main() {
    local action="${TF_ACTION:-apply}"
    local lock_timeout="${TF_LOCK_TIMEOUT:-5m}"
    
    log "=========================================="
    log "Aurora Serverless v2 PostgreSQL"
    log "=========================================="
    log "Instance:   ${TF_VAR_instance}"
    log "Action:     ${action}"
    log "Database:   ${TF_VAR_database_name:-appdb}"
    log "Capacity:   ${TF_VAR_min_capacity:-0.5} - ${TF_VAR_max_capacity:-4} ACU"
    log "=========================================="
    
    [[ -z "${TF_VAR_instance}" ]] && error "name is required"
    
    init_terraform
    cd "${TERRAFORM_DIR}"
    
    case "${action}" in
        apply)
            log "Planning..."
            terraform plan -input=false -lock-timeout="${lock_timeout}" -out=tfplan
            log "Applying..."
            terraform apply -input=false -lock-timeout="${lock_timeout}" -auto-approve tfplan
            set_outputs
            ;;
        destroy)
            log "Destroying..."
            terraform destroy -input=false -lock-timeout="${lock_timeout}" -auto-approve
            ;;
        plan)
            log "Planning..."
            terraform plan -input=false -lock-timeout="${lock_timeout}"
            ;;
        *)
            error "Unknown action: ${action}. Valid: apply, destroy, plan"
            ;;
    esac
    
    log "Done!"
}

main "$@"
