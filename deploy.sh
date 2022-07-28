#!/bin/bash
#set -e

# note that the character '_' is an invalid value if you are replacing the defaults below
cluster1_context="cluster1"
cluster2_context="cluster2"
cluster3_context="cluster3"

mgmt_context="mgmt"
gloo_mesh_version="2.0.9"

# check to see if defined contexts exist
if [[ $(kubectl config get-contexts | grep ${mgmt_context}) == "" ]] || [[ $(kubectl config get-contexts | grep ${cluster1_context}) == "" ]]; then
  echo "Check Failed: Either mgmt, cluster1, and cluster2 contexts do not exist. Please check to see if you have three clusters available"
  echo "Run 'kubectl config get-contexts' to see currently available contexts. If the clusters are available, please make sure that they are named correctly. Default is mgmt, cluster1, and cluster2"
  exit 1;
fi

# install argocd on ${mgmt_context}, ${cluster1_context}, and ${cluster2_context}
cd bootstrap-argocd
./install-argocd.sh insecure-rootpath ${mgmt_context}
./install-argocd.sh insecure-rootpath ${cluster1_context}
./install-argocd.sh insecure-rootpath ${cluster2_context}

cd ..

# wait for argo cluster rollout
./tools/wait-for-rollout.sh deployment argocd-server argocd 20 ${mgmt_context}
./tools/wait-for-rollout.sh deployment argocd-server argocd 20 ${cluster1_context}
./tools/wait-for-rollout.sh deployment argocd-server argocd 20 ${cluster2_context}


# deploy mgmt, cluster1, and cluster2, cluster3 cluster config aoa
kubectl apply -f platform-owners/mgmt/mgmt-cluster-config.yaml --context ${mgmt_context}
kubectl apply -f platform-owners/cluster1/cluster1-cluster-config.yaml --context ${cluster1_context}
kubectl apply -f platform-owners/cluster2/cluster2-cluster-config.yaml --context ${cluster2_context}


# deploy mgmt, cluster1, and cluster2, cluster3 environment infra app-of-apps
kubectl apply -f platform-owners/mgmt/mgmt-infra.yaml --context ${mgmt_context}
kubectl apply -f platform-owners/cluster1/cluster1-infra.yaml --context ${cluster1_context}
kubectl apply -f platform-owners/cluster2/cluster2-infra.yaml --context ${cluster2_context}


# wait for completion of gloo-mesh install
./tools/wait-for-rollout.sh deployment gloo-mesh-mgmt-server gloo-mesh 10 ${mgmt_context}

# register clusters to gloo mesh with helm

until [ "${SVC}" != "" ]; do
  SVC=$(kubectl --context ${mgmt_context} -n gloo-mesh get svc gloo-mesh-mgmt-server -o jsonpath='{.status.loadBalancer.ingress[0].*}')
  echo waiting for gloo mesh management server LoadBalancer IP to be detected
  sleep 2
done


kubectl apply --context ${cluster1_context} -f- <<EOF
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: gm-enterprise-agent-${cluster1_context}
  namespace: argocd
spec:
  destination:
    server: https://kubernetes.default.svc
    namespace: gloo-mesh
  source:
    repoURL: 'https://storage.googleapis.com/gloo-mesh-enterprise/gloo-mesh-agent'
    targetRevision: ${gloo_mesh_version}
    chart: gloo-mesh-agent
    helm:
      valueFiles:
        - values.yaml
      parameters:
        - name: cluster
          value: '${cluster1_context}'
        - name: relay.serverAddress
          value: '${SVC}:9900'
        - name: relay.authority
          value: 'gloo-mesh-mgmt-server.gloo-mesh'
        - name: relay.clientTlsSecret.name
          value: 'gloo-mesh-agent-cluster1-tls-cert'
        - name: relay.clientTlsSecret.namespace
          value: 'gloo-mesh'
        - name: relay.rootTlsSecret.name
          value: 'relay-root-tls-secret'
        - name: relay.rootTlsSecret.namespace
          value: 'gloo-mesh'
        - name: rate-limiter.enabled
          value: 'false'
        - name: ext-auth-service.enabled
          value: 'false'
        # enabled for future vault integration
        - name: istiodSidecar.createRoleBinding
          value: 'true'
  syncPolicy:
    automated:
      prune: false
      selfHeal: false
    syncOptions:
    - Replace=true
    - ApplyOutOfSyncOnly=true
  project: default
EOF

kubectl apply --context ${cluster2_context} -f- <<EOF
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: gm-enterprise-agent-${cluster2_context}
  namespace: argocd
spec:
  destination:
    server: https://kubernetes.default.svc
    namespace: gloo-mesh
  source:
    repoURL: 'https://storage.googleapis.com/gloo-mesh-enterprise/gloo-mesh-agent'
    targetRevision: ${gloo_mesh_version}
    chart: gloo-mesh-agent
    helm:
      valueFiles:
        - values.yaml
      parameters:
        - name: cluster
          value: '${cluster2_context}'
        - name: relay.serverAddress
          value: '${SVC}:9900'
        - name: relay.authority
          value: 'gloo-mesh-mgmt-server.gloo-mesh'
        - name: relay.clientTlsSecret.name
          value: 'gloo-mesh-agent-cluster2-tls-cert'
        - name: relay.clientTlsSecret.namespace
          value: 'gloo-mesh'
        - name: relay.rootTlsSecret.name
          value: 'relay-root-tls-secret'
        - name: relay.rootTlsSecret.namespace
          value: 'gloo-mesh'
        - name: rate-limiter.enabled
          value: 'false'
        - name: ext-auth-service.enabled
          value: 'false'
        # enabled for future vault integration
        - name: istiodSidecar.createRoleBinding
          value: 'true'
  syncPolicy:
    automated:
      prune: false
      selfHeal: false
    syncOptions:
    - Replace=true
    - ApplyOutOfSyncOnly=true
  project: default
EOF




# deploy cluster1, and cluster2, cluster3 environment apps aoa
kubectl apply -f platform-owners/cluster1/cluster1-apps.yaml --context ${cluster1_context}
kubectl apply -f platform-owners/cluster2/cluster2-apps.yaml --context ${cluster2_context}


# wait for completion of bookinfo install
./tools/wait-for-rollout.sh deployment productpage-v1 bookinfo-frontends 10 ${cluster1_context}
./tools/wait-for-rollout.sh deployment productpage-v1 bookinfo-frontends 10 ${cluster2_context}

# deploy mesh config aoa
kubectl apply -f platform-owners/mgmt/mgmt-mesh-config.yaml --context ${mgmt_context}
kubectl apply -f platform-owners/cluster1/cluster1-mesh-config.yaml --context ${cluster1_context}

# echo port-forward commands
echo
echo "access gloo mesh dashboard:"
echo "kubectl port-forward -n gloo-mesh svc/gloo-mesh-ui 8090 --context ${mgmt_context}"
echo 
echo "access argocd dashboard:"
echo "kubectl port-forward svc/argocd-server -n argocd 9999:443 --context ${mgmt_context}"

echo "You can connect now to argo using the following path: http://localhost:9999/argo, using the username/password admin/solo.io"