# ⚙️ EKS 클러스터 배포 가이드

> **⏱️ 예상 소요시간**: 30-45분  
> **💡 난이도**: 중급  
> **📋 목표**: Terraform으로 생성된 EKS 클러스터에 필수 컴포넌트를 설치하고 설정합니다.

---

## 📋 배포 완료 체크리스트

- [ ] kubectl 클러스터 연결 설정
- [ ] AWS Load Balancer Controller 설치
- [ ] EBS CSI Driver 설정
- [ ] Cluster Autoscaler 설치
- [ ] Metrics Server 설치
- [ ] 네임스페이스 생성
- [ ] RBAC 설정

---

## 🔗 1단계: 클러스터 연결 설정

### kubectl 설정
```bash
# EKS 클러스터에 연결
aws eks update-kubeconfig --region ap-northeast-2 --name openwebui-eks-dev

# 클러스터 연결 확인
kubectl cluster-info
kubectl get nodes
```

**예상 출력:**
```
NAME                                        STATUS   ROLES    AGE   VERSION
ip-10-0-10-xxx.ap-northeast-2.compute.internal   Ready    <none>   5m    v1.28.x
ip-10-0-20-xxx.ap-northeast-2.compute.internal   Ready    <none>   5m    v1.28.x
```

### 클러스터 정보 확인
```bash
# 클러스터 상세 정보
kubectl get nodes -o wide

# 네임스페이스 확인
kubectl get namespaces

# 기본 파드 상태 확인
kubectl get pods -n kube-system
```

---

## 🌐 2단계: AWS Load Balancer Controller 설치

### IAM 역할 생성
```bash
# OIDC 제공자 URL 확인
aws eks describe-cluster --name openwebui-eks-dev --query "cluster.identity.oidc.issuer" --output text

# IAM OIDC 제공자 생성
eksctl utils associate-iam-oidc-provider --cluster=openwebui-eks-dev --approve

# Load Balancer Controller용 IAM 정책 다운로드
curl -o iam_policy.json https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/v2.7.2/docs/install/iam_policy.json

# IAM 정책 생성
aws iam create-policy \
    --policy-name AWSLoadBalancerControllerIAMPolicy \
    --policy-document file://iam_policy.json

# 서비스 어카운트 생성
eksctl create iamserviceaccount \
  --cluster=openwebui-eks-dev \
  --namespace=kube-system \
  --name=aws-load-balancer-controller \
  --role-name AmazonEKSLoadBalancerControllerRole \
  --attach-policy-arn=arn:aws:iam::$(aws sts get-caller-identity --query Account --output text):policy/AWSLoadBalancerControllerIAMPolicy \
  --approve
```

### Helm으로 설치
```bash
# Helm 저장소 추가
helm repo add eks https://aws.github.io/eks-charts
helm repo update

# AWS Load Balancer Controller 설치
helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n kube-system \
  --set clusterName=openwebui-eks-dev \
  --set serviceAccount.create=false \
  --set serviceAccount.name=aws-load-balancer-controller

# 설치 확인
kubectl get deployment -n kube-system aws-load-balancer-controller
```

---

## 💾 3단계: EBS CSI Driver 설정

### IAM 역할 생성
```bash
# EBS CSI Driver용 서비스 어카운트 생성
eksctl create iamserviceaccount \
  --name ebs-csi-controller-sa \
  --namespace kube-system \
  --cluster openwebui-eks-dev \
  --role-name AmazonEKS_EBS_CSI_DriverRole \
  --attach-policy-arn arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy \
  --approve
```

### Add-on 활성화
```bash
# EBS CSI Driver Add-on 설치
aws eks create-addon \
  --cluster-name openwebui-eks-dev \
  --addon-name aws-ebs-csi-driver \
  --service-account-role-arn arn:aws:iam::$(aws sts get-caller-identity --query Account --output text):role/AmazonEKS_EBS_CSI_DriverRole

# 설치 확인
kubectl get pods -n kube-system -l app=ebs-csi-controller
```

### StorageClass 생성
```yaml
# storage-class.yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: gp3-encrypted
  annotations:
    storageclass.kubernetes.io/is-default-class: "true"
provisioner: ebs.csi.aws.com
parameters:
  type: gp3
  encrypted: "true"
  fsType: ext4
volumeBindingMode: WaitForFirstConsumer
allowVolumeExpansion: true
```

```bash
# 기본 StorageClass 제거
kubectl patch storageclass gp2 -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"false"}}}'

# 새 StorageClass 적용
kubectl apply -f storage-class.yaml

# 확인
kubectl get storageclass
```

---

## 📈 4단계: Cluster Autoscaler 설치

### cluster-autoscaler.yaml
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: cluster-autoscaler
  namespace: kube-system
  labels:
    app: cluster-autoscaler
spec:
  selector:
    matchLabels:
      app: cluster-autoscaler
  template:
    metadata:
      labels:
        app: cluster-autoscaler
    spec:
      serviceAccountName: cluster-autoscaler
      containers:
      - image: registry.k8s.io/autoscaling/cluster-autoscaler:v1.28.2
        name: cluster-autoscaler
        resources:
          limits:
            cpu: 100m
            memory: 600Mi
          requests:
            cpu: 100m
            memory: 600Mi
        command:
        - ./cluster-autoscaler
        - --v=4
        - --stderrthreshold=info
        - --cloud-provider=aws
        - --skip-nodes-with-local-storage=false
        - --expander=least-waste
        - --node-group-auto-discovery=asg:tag=k8s.io/cluster-autoscaler/enabled,k8s.io/cluster-autoscaler/openwebui-eks-dev
        - --balance-similar-node-groups
        - --skip-nodes-with-system-pods=false
        env:
        - name: AWS_REGION
          value: ap-northeast-2
        volumeMounts:
        - name: ssl-certs
          mountPath: /etc/ssl/certs/ca-certificates.crt
          readOnly: true
      volumes:
      - name: ssl-certs
        hostPath:
          path: "/etc/ssl/certs/ca-certificates.crt"
---
apiVersion: v1
kind: ServiceAccount
metadata:
  labels:
    k8s-addon: cluster-autoscaler.addons.k8s.io
    k8s-app: cluster-autoscaler
  name: cluster-autoscaler
  namespace: kube-system
  annotations:
    eks.amazonaws.com/role-arn: arn:aws:iam::$(aws sts get-caller-identity --query Account --output text):role/AmazonEKSClusterAutoscalerRole
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: cluster-autoscaler
  labels:
    k8s-addon: cluster-autoscaler.addons.k8s.io
    k8s-app: cluster-autoscaler
rules:
- apiGroups: [""]
  resources: ["events", "endpoints"]
  verbs: ["create", "patch"]
- apiGroups: [""]
  resources: ["pods/eviction"]
  verbs: ["create"]
- apiGroups: [""]
  resources: ["pods/status"]
  verbs: ["update"]
- apiGroups: [""]
  resources: ["endpoints"]
  resourceNames: ["cluster-autoscaler"]
  verbs: ["get", "update"]
- apiGroups: [""]
  resources: ["nodes"]
  verbs: ["watch", "list", "get", "update"]
- apiGroups: [""]
  resources: ["namespaces", "pods", "services", "replicationcontrollers", "persistentvolumeclaims", "persistentvolumes"]
  verbs: ["watch", "list", "get"]
- apiGroups: ["extensions"]
  resources: ["replicasets", "daemonsets"]
  verbs: ["watch", "list", "get"]
- apiGroups: ["policy"]
  resources: ["poddisruptionbudgets"]
  verbs: ["watch", "list"]
- apiGroups: ["apps"]
  resources: ["statefulsets", "replicasets", "daemonsets"]
  verbs: ["watch", "list", "get"]
- apiGroups: ["storage.k8s.io"]
  resources: ["storageclasses", "csinodes", "csidrivers", "csistoragecapacities"]
  verbs: ["watch", "list", "get"]
- apiGroups: ["batch", "extensions"]
  resources: ["jobs"]
  verbs: ["get", "list", "watch", "patch"]
- apiGroups: ["coordination.k8s.io"]
  resources: ["leases"]
  verbs: ["create"]
- apiGroups: ["coordination.k8s.io"]
  resourceNames: ["cluster-autoscaler"]
  resources: ["leases"]
  verbs: ["get", "update"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: cluster-autoscaler
  labels:
    k8s-addon: cluster-autoscaler.addons.k8s.io
    k8s-app: cluster-autoscaler
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: cluster-autoscaler
subjects:
- kind: ServiceAccount
  name: cluster-autoscaler
  namespace: kube-system
```

### IAM 역할 생성 및 배포
```bash
# Cluster Autoscaler용 IAM 정책 생성
cat > cluster-autoscaler-policy.json << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Action": [
                "autoscaling:DescribeAutoScalingGroups",
                "autoscaling:DescribeAutoScalingInstances",
                "autoscaling:DescribeLaunchConfigurations",
                "autoscaling:DescribeTags",
                "autoscaling:SetDesiredCapacity",
                "autoscaling:TerminateInstanceInAutoScalingGroup",
                "ec2:DescribeLaunchTemplateVersions"
            ],
            "Resource": "*",
            "Effect": "Allow"
        }
    ]
}
EOF

# IAM 정책 생성
aws iam create-policy \
    --policy-name AmazonEKSClusterAutoscalerPolicy \
    --policy-document file://cluster-autoscaler-policy.json

# 서비스 어카운트 생성
eksctl create iamserviceaccount \
  --cluster=openwebui-eks-dev \
  --namespace=kube-system \
  --name=cluster-autoscaler \
  --attach-policy-arn=arn:aws:iam::$(aws sts get-caller-identity --query Account --output text):policy/AmazonEKSClusterAutoscalerPolicy \
  --override-existing-serviceaccounts \
  --approve

# Cluster Autoscaler 배포
kubectl apply -f cluster-autoscaler.yaml

# 확인
kubectl get pods -n kube-system -l app=cluster-autoscaler
```

---

## 📊 5단계: Metrics Server 설치

```bash
# Metrics Server 설치
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml

# 확인
kubectl get deployment metrics-server -n kube-system
kubectl top nodes
```

---

## 🗂️ 6단계: 네임스페이스 및 RBAC 설정

### 네임스페이스 생성
```yaml
# namespaces.yaml
apiVersion: v1
kind: Namespace
metadata:
  name: openwebui
  labels:
    name: openwebui
---
apiVersion: v1
kind: Namespace
metadata:
  name: litellm
  labels:
    name: litellm
---
apiVersion: v1
kind: Namespace
metadata:
  name: monitoring
  labels:
    name: monitoring
```

```bash
kubectl apply -f namespaces.yaml
kubectl get namespaces
```

### RBAC 설정
```yaml
# rbac.yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: openwebui-sa
  namespace: openwebui
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: openwebui-role
rules:
- apiGroups: [""]
  resources: ["pods", "services", "configmaps", "secrets"]
  verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
- apiGroups: ["apps"]
  resources: ["deployments", "replicasets"]
  verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: openwebui-binding
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: openwebui-role
subjects:
- kind: ServiceAccount
  name: openwebui-sa
  namespace: openwebui
```

```bash
kubectl apply -f rbac.yaml
```

---

## 🔧 7단계: 클러스터 설정 검증

### 전체 상태 확인 스크립트
```bash
#!/bin/bash
# verify-cluster.sh

echo "🔍 EKS 클러스터 검증 시작..."

echo "📋 1. 노드 상태 확인"
kubectl get nodes -o wide

echo "📋 2. 시스템 파드 상태 확인"
kubectl get pods -n kube-system

echo "📋 3. StorageClass 확인"
kubectl get storageclass

echo "📋 4. 네임스페이스 확인"
kubectl get namespaces

echo "📋 5. Load Balancer Controller 확인"
kubectl get deployment -n kube-system aws-load-balancer-controller

echo "📋 6. Cluster Autoscaler 확인"
kubectl get pods -n kube-system -l app=cluster-autoscaler

echo "📋 7. Metrics Server 확인"
kubectl top nodes

echo "✅ 클러스터 검증 완료!"
```

```bash
chmod +x verify-cluster.sh
./verify-cluster.sh
```

---

## 🚨 문제 해결

### 자주 발생하는 문제

#### 1. Load Balancer Controller 설치 실패
```bash
# OIDC 제공자 확인
aws eks describe-cluster --name openwebui-eks-dev --query "cluster.identity.oidc.issuer" --output text

# 서비스 어카운트 재생성
eksctl delete iamserviceaccount --cluster=openwebui-eks-dev --name=aws-load-balancer-controller --namespace=kube-system
# 다시 생성...
```

#### 2. 노드 그룹이 Ready 상태가 아닌 경우
```bash
# 노드 상세 정보 확인
kubectl describe nodes

# 로그 확인
kubectl logs -n kube-system -l k8s-app=aws-node
```

#### 3. Metrics Server 오류
```bash
# Metrics Server 로그 확인
kubectl logs -n kube-system -l k8s-app=metrics-server

# 재설치
kubectl delete -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
```

---

## ⏭️ 다음 단계

EKS 클러스터 설정이 완료되었다면:
- **[05-application-deployment.md]** - OpenWebUI 애플리케이션 배포
- **[06-verification.md]** - 배포 검증 및 테스트
