################################################################################
# Aurora Serverless v2 PostgreSQL - Variables
################################################################################

variable "instance" {
  description = "Instance name"
  type        = string
}

# Optional: Override VPC discovery (mainly for testing)
# In production, leave empty to auto-discover from network action tags
variable "vpc_id" {
  description = "Existing VPC ID (optional - if not provided, discovers from network action)"
  type        = string
  default     = ""
}

variable "subnet_ids" {
  description = "Comma-separated subnet IDs (required if vpc_id is provided)"
  type        = string
  default     = ""
}

variable "database_name" {
  description = "Name of the default database"
  type        = string
  default     = "appdb"
}

variable "master_username" {
  description = "Master username"
  type        = string
  default     = "postgres"
}

variable "engine_version" {
  description = "Aurora PostgreSQL engine version"
  type        = string
  default     = "17.4"
}

variable "min_capacity" {
  description = "Minimum ACU capacity (0.5 to 128)"
  type        = number
  default     = 0.5
}

variable "max_capacity" {
  description = "Maximum ACU capacity (0.5 to 128)"
  type        = number
  default     = 4
}

variable "deletion_protection" {
  description = "Enable deletion protection"
  type        = bool
  default     = false
}

variable "publicly_accessible" {
  description = "Make database publicly accessible (NOT recommended for production)"
  type        = bool
  default     = false
}
