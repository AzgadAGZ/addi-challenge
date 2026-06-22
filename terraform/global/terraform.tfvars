aws_region                = "us-east-1"
domain_name               = "addi.com"
cloudtrail_s3_bucket_name = "addi-cloudtrail-logs"
approved_regions          = ["us-east-1", "us-east-2"]

tags = {
  ManagedBy = "addi-platform"
  Project   = "addi"
  Layer     = "global"
}
