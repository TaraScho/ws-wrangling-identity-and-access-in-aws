output "bucket_name" {
  description = "Name of the crown jewels S3 bucket"
  value       = aws_s3_bucket.crown_jewels.id
}
