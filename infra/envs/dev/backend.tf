# Remote state for DEV: its own bucket and key, separate from prod so a dev mistake can never touch prod state.
# S3 native locking (use_lockfile, Terraform >= 1.10) replaces the old DynamoDB lock table.
# The bucket must exist first (versioning + encryption on); see README "Remote state".
# For offline review without AWS access, use ./scripts/tf-plan-offline.sh dev (local state, mock credentials).
terraform {
  backend "s3" {
    bucket       = "hotel-booking-tfstate-dev"
    key          = "envs/dev/terraform.tfstate"
    region       = "ap-south-1"
    encrypt      = true
    use_lockfile = true
  }
}
