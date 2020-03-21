terraform {
  backend "gcs" {
    bucket = "terraform-state-august-period-234610"
    prefix = "gke-terraform/state"
  }
}

provider "google" {
  project = "august-period-234610"
  region  = "us-east1"
}


resource "google_dns_managed_zone" "maelvls" {
  name        = "maelvls"
  dns_name    = "example-.com."
  description = "Example DNS zone"
  labels = {
    foo = "bar"
  }
}

resource "random_id" "rnd" {
  byte_length = 4
}

gcloud dns managed-zones create maelvls --description "My DNS zone" --dns-name=maelvls.dev




# resource "google_service_account" "kubernetes_cluster_account" {
#   account_id = "kubernetes-cluster-account"
# }

# resource "google_service_account_iam_binding" "kubernetes_cluster_account_binding1" {
#   service_account_id = google_service_account.kubernetes_cluster_account.account_id
#   role = "roles/compute.admin"
# }

# resource "google_service_account_iam_binding" "kubernetes_cluster_account_binding2" {
#   service_account_id = google_service_account.kubernetes_cluster_account.account_id
#   role = "roles/storage.objectViewer"
# }

# resource "google_service_account_iam_binding" "kubernetes_cluster_account_binding3" {
#   service_account_id = google_service_account.kubernetes_cluster_account.account_id
#   role = "roles/storage.objectViewer"
# }




# # external-dns
# data "google_service_account" "myaccount" {
#   account_id = "myaccount-id"
# }

# resource "google_service_account_key" "mykey" {
#   service_account_id = data.google_service_account.myaccount.name
# }

# resource "kubernetes_secret" "external-dns-gcp-jsonkey" {
#   metadata = {
#     name = "external-dns-gcp-jsonkey"
#   }
#   data {
#     credentials.json = base64decode(google_service_account_key.mykey.private_key)
#   }
# }

# data "google_service_account_key" "mykey" {
#   name            = google_service_account_key.mykey.name
#   public_key_type = "TYPE_X509_PEM_FILE"
# }

# resource "google_service_account" "object_viewer" {
#   account_id   = "external-dns"
#   display_name = "For external-dns operation"
# }



# Create a KMS key ring
resource "google_kms_key_ring" "key_ring" {
  location = "global"
  name     = "vault-auto-seal-key-ring"
}

# Create a crypto key for the key ring
resource "google_kms_crypto_key" "crypto_key" {
  name            = "vault-auto-seal-crypto-key"
  key_ring        = google_kms_key_ring.key_ring.self_link
  rotation_period = "100000s"
}
