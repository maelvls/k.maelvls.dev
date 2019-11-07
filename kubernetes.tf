terraform {
  backend "gcs" {
    bucket = "terraform-state-august-period-234610"
    prefix = "gke-terraform/state"
  }
}

provider "google" {
  project = "august-period-234610"
  region  = "europe-west1"
}

variable "location" {
  default     = "europe-west1-d"
  description = "region (europe-west1) or zone (europe-west1-d)"
  type        = "string"
}

resource "google_container_cluster" "k8s-cluster" {
  name                     = "august-period-234610"
  remove_default_node_pool = true

  location = "${var.location}"

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

resource "google_container_node_pool" "worker" {
  name       = "worker"
  location   = "${var.location}"
  cluster    = "${google_container_cluster.k8s-cluster.name}"
  node_count = 1

  node_config {
    preemptible  = true
    machine_type = "n1-standard-1"

    oauth_scopes = [
      "https://www.googleapis.com/auth/compute",
      "https://www.googleapis.com/auth/devstorage.read_only",
      "https://www.googleapis.com/auth/logging.write",
      "https://www.googleapis.com/auth/monitoring",
    ]
  }
}

output "cluster_name" {
  value = "${google_container_cluster.k8s-cluster.name}"
}

output "location" {
  value = "${google_container_cluster.k8s-cluster.location}"
}

# # external-dns
# data "google_service_account" "myaccount" {
#   account_id = "myaccount-id"
# }

# resource "google_service_account_key" "mykey" {
#   service_account_id = "${data.google_service_account.myaccount.name}"
# }

# resource "kubernetes_secret" "external-dns-gcp-jsonkey" {
#   metadata = {
#     name = "external-dns-gcp-jsonkey"
#   }
#   data {
#     credentials.json = "${base64decode(google_service_account_key.mykey.private_key)}"
#   }
# }

# data "google_service_account_key" "mykey" {
#   name            = "${google_service_account_key.mykey.name}"
#   public_key_type = "TYPE_X509_PEM_FILE"
# }

# resource "google_service_account" "object_viewer" {
#   account_id   = "external-dns"
#   display_name = "For external-dns operation"
# }
