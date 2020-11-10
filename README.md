# Terraform and Helm config for *.k.maelvls.dev

Infra-as-code (terraform + helm 3) for creating a Kubernetes cluster with:

- ExternalDNS is only used to set up `ns.k.maelvls.dev` since I delegate
  `k.maelvls.dev` to my own name server. I used to use ExternalDNS directly
  but it would litter the maelvls.dev zone.
- I use a special instance of CoreDNS that runs
  [k8s_gateway](https://github.com/ori-edge/k8s_gateway)). This instance of
  CoreDNS does not replace the "kube-dns"-compatible CoreDNS instance that
  run the `kubernetes` plugin.
- The zone delegated to this instance of CoreDNS is `*.k.maelvls.dev`
- For maelvls.dev itself, I was using Cloudflare and a domain at Godaddy.
  Now, I use a Google Domain and Google Cloud DNS.
- Letsencrypt certificates rotated automatically on a per-ingress basis
  using cert-manager.
  > ⚠️ Since the DNS zone that cert-manager wants to update in order to pass
  > the DNS-01 challenges is now handled by CoreDNS and that CoreDNS isn't
  > supported yet (and doesn't support [rfc2136](https://tools.ietf.org/html/rfc2136)),
  > I can't issue wildcard domains anymore and my `*.minio.k.maelvls.dev`
  > per-bucket domains is now broken. One idea could be to use Ricardo Katz'
  > [rikatz/acme-solver](https://github.com/rikatz/acme-solver) which fakes
  > cert-manager's DNS provider and instead uses the Order and Challenge
  > objects to set CoreDNS records using its proxying-through-grpc mechanism.

Then:

```sh
# Prerequisite:
#  - have a Kubernetes cluster with the context "boring_wozniak".
#  - have the Google Cloud project "august-period-234610" on us-east1 (use the legacy way `gcloud auth application-default login`, not the new `gcloud auth login` since the gcloud terraform module uses the application-default method)
#  - have .envrc set with the env variables (see .envrc.example).
terraform apply # idempotent
./helm_apply    # idempotent
```

## Launch the Traefik dashboard

```sh
$ kubectl proxy
Starting to serve on 127.0.0.1:8001
```

Then, open: <http://127.0.0.1:8001/api/v1/namespaces/traefik/services/http:traefik-dashboard:80/proxy>

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

```sh
Error while evaluating the ingress spec: service is type "ClusterIP", expected "NodePort" or "LoadBalancer"
```

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

### Traefik does not register an Ingress

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

## Quick & dirty Kubernetes dashboard

```sh
kubectl apply -f https://raw.githubusercontent.com/kubernetes/dashboard/master/aio/deploy/head.yaml
kubectl proxy
# Paste the content of that in the dashboard:
kubectl -n kubernetes-dashboard get secret $(kubectl -n kubernetes-dashboard get sa kubernetes-dashboard -ojsonpath='{.secrets[*].name}') -ojsonpath='{.data.token}' | base64 -d | pbcopy
```
