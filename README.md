# AWX (Ansible Tower) on GKE using Terraform

![kubernetes-awx](https://user-images.githubusercontent.com/2195781/56848717-75d56280-68ec-11e9-8b6e-36fee9fbb712.png)

Infra-as-code (terraform + helm) for creating a Kubernetes cluster with AWX
(Ansible Tower) and featuring

- external DNS configured dynamically by the cluster when the LoadBalancer
  (traefik) gets its external IP. Regarding the fqdn `*.kube.maelvls.dev`:
  at first, I was using Cloudflare and a domain at Godaddy. Now, I use a
  Google Domain and Google Cloud DNS.
- Letsencrypt certificates rotated automatically on a per-ingress basis
- Metrics using prometheus operator (prometheus, node exporter,
  alertmanager, kube-state-metrics) with grafana on
  <https://grafana.kube.maelvls.dev>
- Kubernetes dashboard + heapster
- and of course AWX on <https://awx.kube.maelvls.dev> (admin/password)

The whole thing should fit on a single `n1-standard-4` node (4 vCPUs, 15GB
RAM), although it should be better with a least two nodes (memcached will
complain about not being able to scale two replicas on two different
nodes).

Then:

```sh
gcloud init
terraform apply
./post-install.sh
source .envrc # if you have direnv, skip this

kubectl apply -f k8s/helm-tiller-rbac.yml
helm init --service-account tiller --history-max 200

kubectl apply -f https://raw.githubusercontent.com/jetstack/cert-manager/master/deploy/manifests/00-crds.yaml --validate=false
helm repo add jetstack https://charts.jetstack.io && helm repo update
helm install --name traefik stable/traefik --values helm/traefik.yaml --namespace kube-system
helm install jetstack/cert-manager --name cert-manager --values helm/cert-manager.yaml --namespace kube-system
kubectl apply -f k8s/cert-manager-issuers.yaml

# Create a zone first (not idempotent)
gcloud dns managed-zones create maelvls --description "My DNS zone" --dns-name=maelvls.dev

# Create a service account for 'external-dns' (will manage dns records)
gcloud iam service-accounts create external-dns --display-name "For external-dns"
gcloud projects add-iam-policy-binding august-period-234610 --role='roles/dns.admin' --member='serviceAccount:dns-exporter@august-period-234610.iam.gserviceaccount.com'
gcloud iam service-accounts keys create credentials.json --iam-account dns-exporter@august-period-234610.iam.gserviceaccount.com
kubectl create secret generic external-dns --from-file=credentials.json=credentials.json
helm install --name external-dns stable/external-dns --values helm/external-dns.yaml

# Create a service account for 'vault' storage
gcloud iam service-accounts create vault-store --display-name "For vault storage"
gcloud projects add-iam-policy-binding august-period-234610 --role='roles/storage.objectAdmin' --member='serviceAccount:vault-store@august-period-234610.iam.gserviceaccount.com'
gcloud iam service-accounts keys create credentials.json --iam-account vault-store@august-period-234610.iam.gserviceaccount.com
kubectl -n vault create secret generic vault-storage-cred-file --from-file=credentials.json=credentials.json

helm repo add incubator http://storage.googleapis.com/kubernetes-charts-incubator
helm install --name vault incubator/vault --namespace vault --values helm/vault.yaml
```

Extras:

```sh
helm install --name kubernetes-dashboard stable/kubernetes-dashboard --values helm/kubernetes-dashboard.yaml --namespace kube-system
helm install --name operator stable/prometheus-operator --namespace kube-system --values helm/operator.yaml
kubectl apply -f k8s/grafana-dashboards.yaml
```

In order to destroy:

```sh
terraform destroy
```

## Launch the Traefik dashboard

```sh
$ kuberctl proxy
Starting to serve on 127.0.0.1:8001
```

Then, open: <http://127.0.0.1:8001/api/v1/namespaces/kube-system/services/http:traefik-dashboard:80/proxy/dashboard>

## Launching the Kubernetes Dashboard

Instructions: <https://github.com/kubernetes/dashboard/wiki/Creating-sample-user>

```sh
kubectl apply -f k8s/kubernetes-dashboard-user.yaml
kubectl -n kube-system describe secret $(kubectl -n kube-system get secret | grep admin-user | awk '{print $1}')
kubectl proxy
open http://127.0.0.1:8001/api/v1/namespaces/kube-system/services/https:kubernetes-dashboard:443/proxy
```

## Kubernetes config management

<https://blog.argoproj.io/the-state-of-kubernetes-configuration-management-d8b06c1205>

- plain kubectl yaml in git
- templated kubectl yaml (terraform, ansible)
- specialized templated kubectl yaml (kustomize, ksonnet)
- config-as-javascript (pulumi)

## FAQ

### Error with some ingress+service

    error while evaluating the ingress spec: service is type "ClusterIP", expected "NodePort" or "LoadBalancer"

I realized this is because, in the Ingress, the portNumber must be a name,
not a number. See: <https://stackoverflow.com/questions/51572249>

### EXTERNAL-IP is pending on GKE

<https://stackoverflow.com/questions/45082494/pending-state-stuck-on-external-ip-for-kubernetes-service>

I disabled the embeded LB (see addon `http_load_balancing`) as I try to use
traefik instead. Info:
<http://blog.chronos-technology.nl/post/disabling-gke-load-balancer-in-kubernetes>

SOLUTION: I could only have one external IP at any time because of the free
trial. For some reason, I had already created a static IP in GCP. As soon
as I removed it, the LoadBalancer got an external IP.

### Trafik logs

```json
{
  "level": "warning",
  "msg": "Endpoints not available for kube-system/grafana",
  "time": "2019-04-23T02:13:17Z"
}
```

I think this is because the endpoints have `notReadyAddresses` status:

    kubectl get endpoints -n kube-system grafana -o yaml

```yaml
apiVersion: v1
kind: Endpoints
metadata:
  labels:
    app: grafana
    chart: grafana-3.3.1
    heritage: Tiller
    release: grafana
  name: grafana
  namespace: kube-system
subsets:
  - notReadyAddresses:
      - ip: 10.0.0.19
        nodeName: gke-august-period-234610-worker-bea0349b-gjtw
        targetRef:
          kind: Pod
          name: grafana-69df5dfc5c-mkfwh
          namespace: kube-system
    ports:
      - name: service
        port: 3000
        protocol: TCP
```

See: <https://www.jeffgeerling.com/blog/2018/fixing-503-service-unavailable-and-endpoints-not-available-traefik-ingress-kubernetes>.

```json
{
  "level": "error",
  "msg": "Error configuring TLS for ingress kube-system/grafana: secret kube-system/grafana-example-tls does not exist",
  "time": "2019-04-23T15:17:42Z"
}
```

## ACME not refreshing LetsEncrypt certs

In order to refresh the certificate issued by LetsEncrypt, just remove the
corresponding secret:

```sh
kubectl delete secret -n kube-system prometheus-example-tls
```
