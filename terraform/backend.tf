# -----------------------------
# Terraform backend config
# -----------------------------
terraform {
  backend "s3" {
    bucket         = "personal-projects-terraform-state-bucket"
    key            = "event-announcement-system.tfstate"
    encrypt        = true
    region         = "ap-south-1"
  }
}