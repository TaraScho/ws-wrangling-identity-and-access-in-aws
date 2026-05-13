# ═══════════════════════════════════════════════════════════════════════════
# Crown Jewels S3 Bucket
# ═══════════════════════════════════════════════════════════════════════════
# This bucket contains the "crown jewels" flag file that learners attempt
# to access before and after privilege escalation. Starting users cannot
# reach it; escalated (admin) users can.

resource "aws_s3_bucket" "crown_jewels" {
  bucket = "iamws-crown-jewels-${var.aws_account_id}"

  force_destroy = true

  tags = {
    Name    = "iamws-crown-jewels"
    Purpose = "Workshop flag file for privilege escalation proof"
  }
}

resource "aws_s3_bucket_public_access_block" "crown_jewels" {
  bucket = aws_s3_bucket.crown_jewels.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_object" "flag" {
  bucket  = aws_s3_bucket.crown_jewels.id
  key     = "flag.txt"
  content = <<-EOF
    ============================================
       YOU FOUND THE CROWN JEWELS!
    ============================================

    Congratulations, partner. You've rustled your
    way past the fences and claimed the loot.

    This file proves you escalated from a
    low-privilege IAM user to full admin access. Yeehaw!

    ============================================
  EOF

  content_type = "text/plain"
}
