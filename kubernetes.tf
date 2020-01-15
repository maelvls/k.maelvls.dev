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

variable "location" {
  default     = "us-east1-c"
  description = "region (europe-west1) or zone (europe-west1-d)"
  type        = string
}

resource "google_container_cluster" "k8s-cluster" {
  name                     = "august-period-234610"
  remove_default_node_pool = true

  location = var.location

  master_auth {
    username = ""
    password = ""
  }

  logging_service    = "none"
  monitoring_service = "none"

  addons_config {
    http_load_balancing {
      disabled = true
    }
  }

  initial_node_count = 1
}

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

resource "google_container_node_pool" "worker" {
  name       = "worker"
  location   = var.location
  cluster    = google_container_cluster.k8s-cluster.name
  node_count = 1

  node_config {
    preemptible  = true
    machine_type = "n1-standard-1"

    oauth_scopes = [
      "https://www.googleapis.com/auth/compute",
      "https://www.googleapis.com/auth/devstorage.read_only",
      "https://www.googleapis.com/auth/logging.write",
      "https://www.googleapis.com/auth/monitoring",
      "https://www.googleapis.com/auth/cloudkms",
    ]
  }
}

output "cluster_name" {
  value = google_container_cluster.k8s-cluster.name
}

output "location" {
  value = google_container_cluster.k8s-cluster.location
}

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
