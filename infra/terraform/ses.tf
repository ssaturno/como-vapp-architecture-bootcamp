# ─────────────────────────────────────────────────────────────────────────────
# SES — sender identity verification
# In SES sandbox mode only verified addresses can send and receive.
# Update var.ses_verified_sender to your real email before running terraform apply.
# To move out of sandbox, request production access in the AWS console.
# ─────────────────────────────────────────────────────────────────────────────

# El LabRole de AWS Academy no tiene permiso para ses:VerifyEmailIdentity via Terraform.
# Verificar el email manualmente con:
#   aws ses verify-email-identity --email-address samarissaturno@gmail.com --region us-east-1
#
# resource "aws_ses_email_identity" "verified_sender" {
#   email = var.ses_verified_sender
# }
