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

provider "kubernetes" {
  config_path    = "~/.kube/config"
  config_context = "boring_wozniak"
}


# gcloud dns managed-zones create maelvls --description "My DNS zone" --dns-name=maelvls.dev
resource "google_dns_managed_zone" "maelvls" {
  name     = "maelvls"
  dns_name = "maelvls.dev."

  dnssec_config {
    kind          = "dns#managedZoneDnsSecConfig"
    non_existence = "nsec3"
    state         = "off"
  }
}

# Previously I was using kube.maelvls.dev and I moved to k.maelvls.dev. To
# ease the migration process, I add a CNAME redirection.
resource "google_dns_record_set" "frontend" {
  name = "kube.${google_dns_managed_zone.maelvls.dns_name}"
  type = "CNAME"
  ttl  = 300

  managed_zone = google_dns_managed_zone.maelvls.name

  rrdatas = ["k.${google_dns_managed_zone.maelvls.dns_name}"]
}

# Due to the fact that I delegate the k.maelvls.dev zone to ext-coredns,
# cert-manager will find out that k.maelvls.dev returns an SOA record, but
# it will also see that k.maelvls.dev isn't a zone in my Cloud DNS account
# (maelvls.dev is the actual zone).
#
# The solution is to use a CNAME record so that the
# _acme-challenge.k.maelvls.dev gets aliased to something in the Cloud DNS
# zone (as opposed to something in the k.maelvls.dev zone). See:
# https://cert-manager.io/docs/configuration/acme/dns01/#delegated-domains-for-dns01
resource "google_dns_record_set" "trick-for-cert-manager" {
  name = "_acme-challenge.k.${google_dns_managed_zone.maelvls.dns_name}"
  type = "CNAME"
  ttl  = 300

  managed_zone = google_dns_managed_zone.maelvls.name

  rrdatas = ["_acme-challenge.${google_dns_managed_zone.maelvls.dns_name}"]
}

# I use an instance of CoreDNS that I expose to the internet with a service
# type load balancer. This service has an annotation that ExternalDNS uses
# to set up an 'A' record named ns-k.maelvls.dev. Here, I create the NS
# record that points to ns-k.maelvls.dev.
resource "google_dns_record_set" "ext-coredns" {
  name = "k.${google_dns_managed_zone.maelvls.dns_name}"
  type = "NS"
  ttl  = 300

  managed_zone = google_dns_managed_zone.maelvls.name

  rrdatas = ["ns-k.${google_dns_managed_zone.maelvls.dns_name}"]
}


# Cert-manager related.
#
# NOTE: when trying to recreate a serviceaccount, first delete the role
# bindings! Otherwise, the recreated serviceaccount will not have the right
# role binding, see https://twitter.com/maelvls/status/1239104479951310848.

resource "kubernetes_namespace" "cert_manager" {
  metadata {
    name = "cert-manager"
  }
}

# gcloud iam service-accounts create cert-manager --display-name "For cert-manager dns01 challenge"
resource "google_service_account" "cert_manager" {
  account_id   = "cert-manager"
  display_name = "For cert-manager dns01 challenge"
}

# gcloud projects add-iam-policy-binding august-period-234610 --role='roles/dns.admin' --member='serviceAccount:cert-manager@august-period-234610.iam.gserviceaccount.com'
resource "google_project_iam_member" "cert_manager" {
  role   = "roles/dns.admin"
  member = "serviceAccount:${google_service_account.cert_manager.email}"
}

# gcloud iam service-accounts keys create /dev/stdout --iam-account cert-manager@august-period-234610.iam.gserviceaccount.com | kubectl -n cert-manager create secret generic jsonkey --from-file=jsonkey=/dev/stdin
resource "google_service_account_key" "cert_manager" {
  service_account_id = google_service_account.cert_manager.name
}
resource "kubernetes_secret" "cert_manager" {
  metadata {
    name      = "jsonkey"
    namespace = kubernetes_namespace.cert_manager.id
  }

  data = {
    jsonkey = base64decode(google_service_account_key.cert_manager.private_key)
  }
}

# External-dns related.

resource "kubernetes_namespace" "external_dns" {
  metadata {
    name = "external-dns"
  }
}

# gcloud iam service-accounts create external-dns --display-name "For external-dns"
resource "google_service_account" "external_dns" {
  account_id   = "external-dns"
  display_name = "For external-dns"
}

# gcloud projects add-iam-policy-binding august-period-234610 --role='roles/dns.admin' --member='serviceAccount:external-dns@august-period-234610.iam.gserviceaccount.com'
resource "google_project_iam_member" "external_dns" {
  role   = "roles/dns.admin"
  member = "serviceAccount:${google_service_account.external_dns.email}"
}

# gcloud iam service-accounts keys create /dev/stdout --iam-account external-dns@august-period-234610.iam.gserviceaccount.com | kubectl -n external-dns create secret generic external-dns --from-file=jsonkey=/dev/stdin
resource "google_service_account_key" "external_dns" {
  service_account_id = google_service_account.cert_manager.name
}
resource "kubernetes_secret" "external_dns" {
  metadata {
    name      = "jsonkey"
    namespace = kubernetes_namespace.external_dns.id
  }

  data = {
    jsonkey = base64decode(google_service_account_key.external_dns.private_key)
  }
}
