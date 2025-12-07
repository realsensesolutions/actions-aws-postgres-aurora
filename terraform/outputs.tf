################################################################################
# Aurora Serverless v2 PostgreSQL - Outputs
################################################################################

output "cluster_endpoint" {
  description = "Cluster writer endpoint"
  value       = aws_rds_cluster.main.endpoint
}

output "cluster_arn" {
  description = "Cluster ARN"
  value       = aws_rds_cluster.main.arn
}

output "cluster_id" {
  description = "Cluster identifier"
  value       = aws_rds_cluster.main.cluster_identifier
}

output "secret_arn" {
  description = "Secrets Manager ARN (contains credentials and connection_string)"
  value       = aws_secretsmanager_secret.credentials.arn
}

output "database_name" {
  description = "Database name"
  value       = aws_rds_cluster.main.database_name
}

output "master_username" {
  description = "Master username"
  value       = aws_rds_cluster.main.master_username
}

output "port" {
  description = "Database port"
  value       = aws_rds_cluster.main.port
}

output "security_group_id" {
  description = "Security group ID"
  value       = aws_security_group.main.id
}

output "connection_string" {
  description = "Connection string template (get actual password from secret_arn)"
  value       = "postgres://${aws_rds_cluster.main.master_username}:PASSWORD@${aws_rds_cluster.main.endpoint}:${aws_rds_cluster.main.port}/${aws_rds_cluster.main.database_name}?sslmode=require"
}
