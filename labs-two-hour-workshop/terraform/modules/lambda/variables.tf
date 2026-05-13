variable "aws_assume_role_arn" {
  description = "ARN of an existing principal that can assume roles created in this module"
  type        = string
  default     = ""
}
