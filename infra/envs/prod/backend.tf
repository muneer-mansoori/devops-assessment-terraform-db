# Remote state for PROD: separate bucket (ideally in a separate AWS account) and key from dev.
# S3 native locking (use_lockfile, Terraform >= 1.10) prevents concurrent applies.
# The bucket must exist first (versioning + encryption on); see README "Remote state".
# For offline review without AWS access, use ./scripts/tf-plan-offline.sh prod (local state, mock credentials).
terraform {
  backend "s3" {
    bucket       = "hotel-booking-tfstate-prod"
    key          = "envs/prod/terraform.tfstate"
    region       = "ap-south-1"
    encrypt      = true
    use_lockfile = true
  }
}
