# <center>Gloo Mesh - GitOPS</center>



## The Goal of this document

Use gitops to deploy an application on multiple clusters (Multi cloud provider), and use Gloo Mesh to deploy traffic and security policies and monitor the environment. 

![Gloo Mesh graph](images/gloo-mesh-zi-full.svg)



## Introduction <a name="introduction"></a>

[Gloo Mesh Enterprise](https://www.solo.io/products/gloo-mesh/) is a management plane which makes it easy to operate [Istio](https://istio.io) on one or many Kubernetes clusters deployed anywhere (any platform, anywhere).

### Istio support

The Gloo Mesh Enterprise subscription includes end to end Istio support:

- Upstream first
- Specialty builds available (FIPS, ARM, etc)
- Long Term Support (LTS) N-4 
- Critical security patches
- Production break-fix
- One hour SLA Severity 1
- Install / upgrade
- Architecture and operational guidance, best practices

### Gloo Mesh overview

Gloo Mesh provides many unique features, including:

- multi-tenancy based on global workspaces
- zero trust enforcement
- global observability (centralized metrics and access logging)
- simplified cross cluster communications (using virtual destinations)
- advanced gateway capabilities (oauth, jwt, transformations, rate limiting, web application firewall, ...)

![Gloo Mesh graph](images/gloo-mesh-graph.png)

### Want to learn more about Gloo Mesh

You can find more information about Gloo Mesh in the official documentation:
[https://docs.solo.io/gloo-mesh/latest/](https://docs.solo.io/gloo-mesh/latest/)


# Phase 1.1 GitOps 

GitOps is becoming increasingly popular approach to manage Kubernetes components. It works by using Git as a single source of truth for declarative infrastructure and applications, allowing your application definitions, configurations, and environments to be declarative and version controlled. This helps to make these workflows automated, auditable, and easy to understand.

To learn move about GitOps and how it can be leveraged with solo.io product check the following link [https://www.solo.io/gitops/](https://www.solo.io/gitops/)

This repo is using the App of Apps pattern, more info [here](https://argo-cd.readthedocs.io/en/stable/operator-manual/cluster-bootstrapping/#app-of-apps-pattern)

# Let's get started

## Prerequisites


### Make this repo your own
 
- Please fork this repo, and replace all occurrences in the forked project of `https://github.com/asayah/gloo-mesh-zi/` to point to your forked repo and push the changes to your repo. (do not create a PR to merge with original repo). 


### Environment 

We will need 4 clusters 
- 3 in GKE (4 nodes, 4CPU min, 8Go min per Node)
- 1 in EKS (4 nodes, 4CPU min, 8Go min per Node)

You can use the basic script in ./misc to create them. 

Note: The cluster should be able to create LB that are publicly reachable. or at least reachable to all the clusters listed above. 
The Lb address of the Gloo Mesh service can be found using this command: 

```bash
kubectl --context ${mgmt_context} -n gloo-mesh get svc gloo-mesh-mgmt-server -o jsonpath='{.status.loadBalancer.ingress[0].*}'
```
Make sure that the address retrieved by the command above is reachable from all the other clusters, on port 9900. 

After creating the clusters, rename the Kubernetes contexts to: 
- mgmt: the management cluster 
- cluster1: 1st workload cluster in GKE 
- cluster2: 2nd workload cluster in GKE 
- cluster3: 3rd cluster in GKE


## Deploy Argo and install Istio + Gloo mesh

Run the following script to deploy the stack: 

```bash 
./deploy.sh
```

### Understand the deployment

The `deploy.sh` script will install the following: 
- ArgoCD will be installed on the 4 clusters

- ArgoCD App for **Cluster configuration**  will be installed, installing cert manager and creating the namespaces in each clusters
- ArgoCD App for **Infra configuration**  will be installed, installing Gloo Mesh and Istio in each cluster
- ArgoCD App for **App configuration**  will be installed, installing the demo application (book info) in each workload cluster
- ArgoCD App for **Mesh configuration**  will be installed, installing required configuration on the management plane cluster (for example workspaces) and installing workload configuration in each workload cluster (like routeTables for routing...)

### Argo Application: Infra configuration

```
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: meta-mgmt-cluster-config
  namespace: argocd
  finalizers:
  - resources-finalizer.argocd.argoproj.io
spec:
  project: default
  source:
    repoURL: https://github.com/asayah/gloo-mesh-zi/
    targetRevision: main
    path: environments/mgmt/cluster-config/active/
  destination:
    server: https://kubernetes.default.svc
  syncPolicy:
    automated:
      prune: false
      selfHeal: false

```
This will deploy everything under `./environments/mgmt/cluster-config/active/` to your `mgmt` cluster, the similar pattern is followed for `cluser1`, `cluser2` and `cluser3`. 

The **Cluster configuration** contains some essential components that will be needed later, for example cert-manager, and will create the namespaces that are required to deploy istio and gloo mesh. 

Note: we are creating separate namespaces for istiod (istio-system) and the istio ingress gateways (istio-gateways), this is to follow a good pattern of separate the gateways installing from the istiod installation. 


### Argo Application: Infra configuration

Following the same pattern as in the previous step, this time we are installing the infra layer, here we will be installing the an Argo application in each of our clusters to deploy everything under `./environments/<environment>/infra/active`


### Argo Application: Infra configuration

Following the same pattern as in the previous step, this time we are installing the application layer, here we will be installing the an Argo application in each of our clusters to deploy everything under `./environments/<environment>/apps/active`


### Argo Application: Mesh configuration

Following the same pattern as in the previous step, this time we are installing the application layer, here we will be installing the an Argo application in each of our clusters to deploy everything under `./environments/<environment>/mesh-config/active`



### Validation

Let's access Gloo Mesh UI to see if Everything got installed correctly

```bash
kubectl port-forward -n gloo-mesh svc/gloo-mesh-ui 8090 --context mgmt
```

You should see that 3 workload clusters get created: 

![Phase 0 OK](images/gloo-mesh-step0.png)

You can also access the ArgoCD UI in each cluster: 

```bash
kubectl port-forward svc/argocd-server -n argocd 9999:443 --context mgmt 
```
You can connect now to argo using the following path: `localhost:9999/argo`
Using the username/password `admin/solo.io`



# Phase 1.2 Workspaces 


Workspaces allow multi tenancy in a Multi cluster environment, to read more about workspaces check the following link: 
[https://docs.solo.io/gloo-mesh-enterprise/main/concepts/multi-tenancy/](https://docs.solo.io/gloo-mesh-enterprise/main/concepts/multi-tenancy/)


## Setup the WorkspaceSettings for the east gateways 
In the management cluster add: 

```
apiVersion: admin.gloo.solo.io/v2
kind: WorkspaceSettings
metadata:
  name: global
  namespace: gloo-mesh
spec:
  options:
    eastWestGateways:
      - selector:
          labels:
            istio: eastwestgateway
```

In this example we are we will have 4 teams, the gateway team described above and 3 application teams: productpage (UI team), details, and reviews, let's create the workspaces using the following config:
```

apiVersion: admin.gloo.solo.io/v2
kind: Workspace
metadata:
  name: productpage
  namespace: gloo-mesh
spec:
  workloadClusters:
  - name: '*'
    namespaces:
    - name: productpage


---
apiVersion: admin.gloo.solo.io/v2
kind: Workspace
metadata:
  name: details
  namespace: gloo-mesh
spec:
  workloadClusters:
  - name: '*'
    namespaces:
    - name: details

---
apiVersion: admin.gloo.solo.io/v2
kind: Workspace
metadata:
  name: reviews
  namespace: gloo-mesh
spec:
  workloadClusters:
  - name: '*'
    namespaces:
    - name: reviews

``` 


In this example the bookinfo application is splitted accross 2 different clusters, the cluster1 has the north south gateway and the UI application (productpage), and the backend applications live on the cluster2: reviews and details. 

To allow the communication between these components we will use workspaces settings, that will allow us to import and export configuration from a workspace to another: 


```
apiVersion: admin.gloo.solo.io/v2
kind: WorkspaceSettings
metadata:
  name: gateways
  namespace: istio-gateways
spec:
  importFrom:
  - workspaces:
    - name: productpage
  exportTo:
  - workspaces:
    - name: "*"
  options:
    federation:
      enabled: true
      serviceSelector:
      - namespace: gloo-mesh-addons    

---
apiVersion: admin.gloo.solo.io/v2
kind: WorkspaceSettings
metadata:
  name: productpage
  namespace: productpage
spec:
  importFrom:
  - workspaces:
    - name: reviews
    - name: details
    - name: gateways    
  exportTo:
  - workspaces:
    - name: gateways
---

apiVersion: admin.gloo.solo.io/v2
kind: WorkspaceSettings
metadata:
  name: details
  namespace: details
spec:
  importFrom:
  - workspaces:
    - name: gateways 
  exportTo:
  - workspaces:
    - name: productpage
  options:
    federation:
      enabled: true
      serviceSelector:
      - workspace: details
        labels:
          app: details    
---

apiVersion: admin.gloo.solo.io/v2
kind: WorkspaceSettings
metadata:
  name: reviews
  namespace: reviews
spec:
  importFrom:
  - workspaces:
    - name: gateways 
  exportTo:
  - workspaces:
    - name: productpage
  options:
    federation:
      enabled: true
      hostSuffix: global
      serviceSelector:
      - workspace: reviews
        labels:
          app: reviews

```


# Phase 2.3 Exposing a service 


In this step, we're going to expose the `productpage` service through the Ingress Gateway using Gloo Mesh.

The Gateway team must create a `VirtualGateway` to configure the Istio Ingress Gateway in cluster1 to listen to incoming requests, add the following resource to the mgmt mesh-config.

```bash
apiVersion: networking.gloo.solo.io/v2
kind: VirtualGateway
metadata:
  name: north-south-gw
  namespace: istio-gateways
spec:
  workloads:
    - selector:
        labels:
          istio: ingressgateway
        cluster: cluster1
  listeners: 
    - http: {}
      port:
        number: 80
      allowedRouteTables:
        - host: '*'
```

Then, the Bookinfo team can create a `RouteTable` to determine how they want to handle the traffic.
Add the following to the mgmt mesh-config dir: 

```bash
apiVersion: networking.gloo.solo.io/v2
kind: RouteTable
metadata:
  name: productpage
  namespace: productpage
  labels:
    expose: "true"
spec:
  hosts:
    - '*'
  virtualGateways:
    - name: north-south-gw
      namespace: istio-gateways
      cluster: cluster1
  workloadSelectors: []
  http:
    - name: productpage
      matchers:
      - uri:
          prefix: /
      forwardTo:
        destinations:
          - ref:
              name: productpage
              namespace: productpage
            port:
              number: 9080

```

You should now be able to access the `productpage` application through the browser on the cluster 1 cluster ingress gateway.

# Federation and multi cluster routing

In the following section we will explore the multi cluster traffic capabilities of Gloo Mesh, first we will need to unify the trust between all the clusters so we can establish a secure connection from end to end, we will use a RootTrust Policy for this: 

```bash

apiVersion: admin.gloo.solo.io/v2
kind: RootTrustPolicy
metadata:
  name: root-trust-policy
  namespace: gloo-mesh
spec:
  config:
    mgmtServerCa:
      generated: {}
    autoRestartPods: true
```


At this point we should be able to connect to the second cluster from cluster1. 

## Multi cluster service discovery

For Multi cluster discovery to work we will need to turn on federation on the workspace settings, the goal here is to allow the product page to connect to the detail service on cluster 2, we already have defined the federation in the workspace settings of the details app: 


```
apiVersion: admin.gloo.solo.io/v2
kind: WorkspaceSettings
metadata:
  name: details
  namespace: details
spec:
  importFrom:
  - workspaces:
    - name: gateways 
  exportTo:
  - workspaces:
    - name: productpage
  options:
    federation:
      enabled: true
      serviceSelector:
      - workspace: details
        labels:
          app: details    

```


Now we have the configuration needed to start routing traffic to cluster 2 from cluster1, let's create the following Route table to enable the traffic to the detail service: 

```
apiVersion: networking.gloo.solo.io/v2
kind: RouteTable
metadata:
  name: details
  namespace: productpage
spec:
  hosts:
    - 'details.details.svc.cluster.local'
  workloadSelectors: []
  http:
    - name: details
      matchers:
      - uri:
          prefix: /
      forwardTo:
        destinations:
          - ref:
              name: details
              namespace: details
              cluster: cluster2
            port:
              number: 9080
```

Now if you check the UI you should see the details section on the UI. 


## Virtual Destination 

Virtual destination is a powerful concept, where we can define a global accessible DNS name for a service across all the cluster, let's define one for the review service: 

```
apiVersion: networking.gloo.solo.io/v2
kind: VirtualDestination
metadata:
  name: reviews
  namespace: reviews
spec:
  hosts:
  - reviews.global
  services:
  - namespace: reviews
    labels:
      app: reviews
  ports:
    - number: 9080
      protocol: HTTP
```

Now using reviews.global we can reach the review service from any cluster, let's use it for the routing: 

```
apiVersion: networking.gloo.solo.io/v2
kind: RouteTable
metadata:
  name: reviews
  namespace: productpage
spec:
  hosts:
    - 'reviews.reviews.svc.cluster.local'
  workloadSelectors: []
  http:
    - name: reviews
      matchers:
      - uri:
          prefix: /
      forwardTo:
        destinations:
          - ref:
              name: reviews
              namespace: reviews
            kind: VIRTUAL_DESTINATION
            port:
              number: 9080
```

if you check the UI you will see now that the review service is accessible from the UI, even if the reviews service is not deployed on cluster1. 


# Policies 


Gloo Mesh allow us to use policies to affect the traffic, let's take an example of the failover policy and outlierDetection policy. 


Create the following policies: 

```
apiVersion: resilience.policy.gloo.solo.io/v2
kind: FailoverPolicy
metadata:
  name: failover
  namespace: productpage
spec:
  applyToDestinations:
  - kind: VIRTUAL_DESTINATION
    selector:
      labels:
        failover: "true"
  config:
    localityMappings: []
```


```apiVersion: resilience.policy.gloo.solo.io/v2
kind: OutlierDetectionPolicy
metadata:
  name: outlier-detection
  namespace: productpage
spec:
  applyToDestinations:
  - kind: VIRTUAL_DESTINATION
    selector:
      labels:
        failover: "true"
  config:
    consecutiveErrors: 2
    interval: 5s
    baseEjectionTime: 30s
    maxEjectionPercent: 100
```

Now to attach the following policies we will just need to label our Virtual Destination configuration with failover=true: 

```
apiVersion: networking.gloo.solo.io/v2
kind: VirtualDestination
metadata:
  name: reviews
  namespace: reviews
  labels:
    failover: "true"  
spec:
  hosts:
  - reviews.global
  services:
  - namespace: reviews
    labels:
      app: reviews
  ports:
    - number: 9080
      protocol: HTTP
```