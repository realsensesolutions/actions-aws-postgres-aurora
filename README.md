# AWS Aurora Serverless v2 PostgreSQL Action

GitHub Action to provision Aurora Serverless v2 PostgreSQL clusters with Terraform.

## Features

- 🚀 **Aurora Serverless v2** - Auto-scaling from 0.5 to 128 ACU
- 🔒 **Secure by Default** - SSL enforced, encrypted storage, Secrets Manager
- 🌐 **Network Integration** - Auto-discovers VPC/subnets from `actions-aws-network`
- 📊 **1 Database per Cluster** - Complete isolation per environment

## Usage

```yaml
- name: Deploy Aurora PostgreSQL
  uses: realsensesolutions/actions-aws-postgres-aurora@main
  id: aurora
  with:
    name: my-app
```

### With Environment-Specific Configuration

```yaml
- name: Deploy Aurora PostgreSQL
  uses: realsensesolutions/actions-aws-postgres-aurora@main
  id: aurora
  with:
    name: ${{ inputs.instance_name }}
    deletion_protection_enabled: ${{ inputs.environment == 'production' }}
    min_capacity: ${{ inputs.environment == 'production' && '1' || '0.5' }}
    max_capacity: ${{ inputs.environment == 'production' && '16' || '4' }}
```

## Full Example (infra.yml)

```yaml
jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          submodules: recursive

      - uses: aws-actions/configure-aws-credentials@v4
        with:
          aws-region: us-east-1
          role-to-assume: ${{ secrets.aws_role_arn }}

      - uses: realsensesolutions/actions-aws-backend-setup@main
        id: backend
        with:
          instance: ${{ inputs.instance_name }}

      - uses: realsensesolutions/actions-aws-network@main
        id: network

      - uses: realsensesolutions/actions-aws-postgres-aurora@main
        id: aurora
        with:
          name: ${{ inputs.instance_name }}
          database_name: ${{ inputs.instance_name }}db
          deletion_protection_enabled: ${{ inputs.environment == 'production' }}
          min_capacity: ${{ inputs.environment == 'production' && '1' || '0.5' }}
          max_capacity: ${{ inputs.environment == 'production' && '16' || '4' }}

      - uses: realsensesolutions/actions-aws-function-go@main
        with:
          name: ${{ inputs.instance_name }}-lambda
          env: |
            AURORA_SECRET_ARN: ${{ steps.aurora.outputs.secret_arn }}
          permissions: |
            secretsmanager: read
```

## Inputs

| Input | Description | Required | Default |
|-------|-------------|----------|---------|
| `name` | Instance name (must match network action) | ✅ | - |
| `action` | Action: `apply`, `destroy`, `plan` | ❌ | `apply` |
| `database_name` | Database name | ❌ | `appdb` |
| `min_capacity` | Minimum ACU (0.5-128) | ❌ | `0.5` |
| `max_capacity` | Maximum ACU (0.5-128) | ❌ | `4` |
| `deletion_protection_enabled` | Enable deletion protection | ❌ | `false` |
| `publicly_accessible` | Make database publicly accessible (NOT recommended for production) | ❌ | `false` |
| `lock_timeout` | Terraform lock timeout | ❌ | `5m` |

### Configuration Notes

**Region:** Inherited from `AWS_REGION` environment variable or AWS config. Set via:
```yaml
- uses: aws-actions/configure-aws-credentials@v4
  with:
    aws-region: us-east-1  # Sets AWS_REGION
```

**VPC/Subnets:** Auto-discovered from `actions-aws-network` tags. For testing without network action, set job-level environment variables:
```yaml
env:
  TF_VAR_vpc_id: ${{ secrets.TEST_VPC_ID }}
  TF_VAR_subnet_ids: ${{ secrets.TEST_SUBNET_IDS }}
```

**Backups:** Hardcoded to 7 days retention (best practice default)

## Outputs

| Output | Description |
|--------|-------------|
| `cluster_endpoint` | Aurora cluster endpoint |
| `cluster_arn` | Aurora cluster ARN |
| `cluster_id` | Aurora cluster identifier |
| `secret_arn` | Secrets Manager ARN with credentials |
| `database_name` | Database name |
| `master_username` | Master username |
| `port` | Database port (5432) |
| `security_group_id` | Security group ID |
| `connection_string` | Connection string template |

## Secrets Manager Format

The `secret_arn` contains:

```json
{
  "host": "xxx-aurora.cluster-xxx.us-east-1.rds.amazonaws.com",
  "port": 5432,
  "username": "postgres",
  "password": "xxx",
  "dbname": "appdb",
  "connection_string": "postgres://postgres:xxx@xxx:5432/appdb?sslmode=require"
}
```

## Lambda Connection (Go)

```go
package db

import (
    "context"
    "database/sql"
    "encoding/json"
    "os"
    "sync"

    "github.com/aws/aws-sdk-go-v2/aws"
    "github.com/aws/aws-sdk-go-v2/config"
    "github.com/aws/aws-sdk-go-v2/service/secretsmanager"
    _ "github.com/lib/pq"
)

var (
    db   *sql.DB
    once sync.Once
)

type DBSecret struct {
    ConnectionString string `json:"connection_string"`
}

func GetDB(ctx context.Context) (*sql.DB, error) {
    var err error
    once.Do(func() {
        cfg, _ := config.LoadDefaultConfig(ctx)
        client := secretsmanager.NewFromConfig(cfg)
        
        result, _ := client.GetSecretValue(ctx, &secretsmanager.GetSecretValueInput{
            SecretId: aws.String(os.Getenv("AURORA_SECRET_ARN")),
        })
        
        var secret DBSecret
        json.Unmarshal([]byte(*result.SecretString), &secret)
        
        db, err = sql.Open("postgres", secret.ConnectionString)
        if err == nil {
            db.SetMaxOpenConns(2)
            db.SetMaxIdleConns(2)
        }
    })
    return db, err
}
```

## Resources Created

1. `aws_rds_cluster` - Aurora Serverless v2 cluster
2. `aws_rds_cluster_instance` - Serverless instance (db.serverless)
3. `aws_db_subnet_group` - Private subnets from network action
4. `aws_security_group` - VPC CIDR access only
5. `aws_rds_cluster_parameter_group` - SSL enforced
6. `aws_secretsmanager_secret` - Credentials storage

## Advanced Usage

### Production with All Options

```yaml
- uses: realsensesolutions/actions-aws-postgres-aurora@main
  id: aurora
  with:
    name: my-app-prod
    database_name: production
    min_capacity: '1'
    max_capacity: '16'
    deletion_protection_enabled: 'true'
    lock_timeout: '10m'
```

### Development with Public Access (Testing Only)

```yaml
- uses: realsensesolutions/actions-aws-postgres-aurora@main
  id: aurora
  with:
    name: my-app-dev
    publicly_accessible: 'true'  # ⚠️ Opens to internet - dev only!
```

**Note:** Even with `publicly_accessible: true`, the database must be in a public subnet. This is primarily for local testing/debugging. Use SSH tunnels or VPN for production access.

## Best Practices Applied

- ✅ Storage encryption enabled
- ✅ SSL connections enforced (`rds.force_ssl = 1`)
- ✅ Credentials in Secrets Manager (not outputs)
- ✅ Private subnets only (secure by default)
- ✅ Security group restricts to VPC CIDR
- ✅ 7-day backup retention
- ✅ Password without special chars (no URL encoding issues)

## Cost Estimate

| ACU | ~Monthly Cost |
|-----|---------------|
| 0.5 (min) | ~$36/month |
| 4 (default max) | ~$288/month if sustained |

Aurora Serverless v2 scales automatically - you only pay for what you use.

## License

Apache License 2.0
