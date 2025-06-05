# 🚀 AWS EKS CI/CD 파이프라인 구축 가이드

> **⏱️ 예상 소요시간**: 45-60분  
> **💡 난이도**: 중급  
> **📋 목표**: GitHub Actions를 사용하여 AWS EKS에 OpenWebUI 애플리케이션을 자동 배포하는 CI/CD 파이프라인 구축  
> **📁 전체 코드**: [GitHub에서 확인하기](https://github.com/8dobibim/combined/blob/main/8dobibim_back/.github/workflows/cicd.yml)

---

## 📋 전체 구조 개요

### 파이프라인 단계별 흐름
```
1. GitHub Push 트리거
2. AWS 인증 및 환경 설정
3. Terraform으로 인프라 구축
4. EKS 클러스터 설정
5. 필수 컴포넌트 설치
6. ArgoCD 설치 및 설정
7. 애플리케이션 배포
8. 헬스체크 및 롤백
```

---

## 🔐 Step 1: GitHub Secrets 및 기본 설정

### 필요한 Secrets 목록
```yaml
# GitHub 리포지토리 → Settings → Secrets and variables → Actions

# AWS 인증
AWS_ACCESS_KEY_ID
AWS_SECRET_ACCESS_KEY

# API 키들
GEMINI_API_KEY
AZURE_API_KEY
AZURE_API_BASE
AZURE_API_VERSION

# 데이터베이스
POSTGRES_DB
POSTGRES_USER
POSTGRES_PASSWORD
DATABASE_URL

# LiteLLM
LITELLM_MASTER_KEY
LITELLM_SALT_KEY
```

### 워크플로우 기본 설정
```yaml
name: Deploy to AWS EKS

on:
  push:
    branches:
      - main  # main 브랜치에 푸시될 때만 실행

jobs:
  deploy:
    runs-on: ubuntu-latest  # Ubuntu 최신 버전 사용
    
    env:
      # Terraform 작업 디렉토리
      TF_WORKING_DIR: ./terraform-related/AWS_terraform_grafana
      # ArgoCD 초기 비밀번호 해시 (admin)
      ARGOCD_PASSWORD_HASH: $2a$10$8K9jKpK7a9c6xL8zFiZ65uHpYz9ROzAyl3PzGp6u2Fj0CeLccL5tK
```

**🔍 설명**:
- `on.push.branches`: 특정 브랜치에 코드가 푸시될 때만 파이프라인 실행
- `env`: 워크플로우 전체에서 사용할 환경 변수 정의
- `ARGOCD_PASSWORD_HASH`: bcrypt로 해시된 ArgoCD admin 비밀번호

---

## 🏗️ Step 2: Terraform 인프라 구축

### 2-1. 기본 설정 단계
```yaml
steps:
  # 코드 체크아웃
  - name: Checkout code
    uses: actions/checkout@v4

  # Terraform CLI 설치
  - name: Setup Terraform
    uses: hashicorp/setup-terraform@v2

  # AWS 인증 설정
  - name: Configure AWS Credentials
    uses: aws-actions/configure-aws-credentials@v4
    with:
      aws-access-key-id: ${{ secrets.AWS_ACCESS_KEY_ID }}
      aws-secret-access-key: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
      aws-region: ${{ vars.AWS_REGION || 'ap-northeast-2' }}
```

**🔍 설명**:
- `actions/checkout@v4`: 리포지토리 코드를 가져옴
- `hashicorp/setup-terraform@v2`: Terraform CLI 설치
- AWS 인증 정보는 GitHub Secrets에서 가져옴
- 리전은 Variables 또는 기본값(서울) 사용

### 2-2. Terraform 변수 설정
```yaml
  - name: Set Secrets as Environment Variables
    run: |
      # Terraform 변수로 사용할 환경 변수 설정
      echo "TF_VAR_gemini_api_key=${{ secrets.GEMINI_API_KEY }}" >> $GITHUB_ENV
      echo "TF_VAR_azure_api_key=${{ secrets.AZURE_API_KEY }}" >> $GITHUB_ENV
      echo "TF_VAR_azure_api_base=${{ secrets.AZURE_API_BASE }}" >> $GITHUB_ENV
      echo "TF_VAR_azure_api_version=${{ secrets.AZURE_API_VERSION }}" >> $GITHUB_ENV
      echo "TF_VAR_postgres_db=${{ secrets.POSTGRES_DB }}" >> $GITHUB_ENV
      echo "TF_VAR_postgres_user=${{ secrets.POSTGRES_USER }}" >> $GITHUB_ENV
      echo "TF_VAR_postgres_password=${{ secrets.POSTGRES_PASSWORD }}" >> $GITHUB_ENV
      echo "TF_VAR_database_url=${{ secrets.DATABASE_URL }}" >> $GITHUB_ENV
      echo "TF_VAR_litellm_master_key=${{ secrets.LITELLM_MASTER_KEY }}" >> $GITHUB_ENV
      echo "TF_VAR_litellm_salt_key=${{ secrets.LITELLM_SALT_KEY }}" >> $GITHUB_ENV
```

**🔍 설명**:
- `TF_VAR_` 접두사: Terraform이 자동으로 변수로 인식
- `$GITHUB_ENV`: 이후 단계에서도 사용 가능한 환경 변수
- 모든 민감한 정보는 GitHub Secrets에서 가져옴

### 2-3. Terraform 실행
```yaml
  # Terraform 초기화
  - name: Terraform Init
    run: terraform init
    working-directory: ${{ env.TF_WORKING_DIR }}

  # 실행 계획 확인
  - name: Terraform Plan
    run: terraform plan -var-file="terraform.tfvars" -input=false
    working-directory: ${{ env.TF_WORKING_DIR }}

  # 인프라 생성/업데이트
  - name: Terraform Apply
    run: terraform apply -auto-approve -var-file="terraform.tfvars" -input=false
    working-directory: ${{ env.TF_WORKING_DIR }}
```

**🔍 설명**:
- `terraform init`: 프로바이더 다운로드 및 백엔드 초기화
- `terraform plan`: 변경사항 미리보기
- `terraform apply`: 실제 인프라 생성
- `-auto-approve`: 대화형 승인 건너뛰기
- `-input=false`: 대화형 입력 비활성화

---

## ☸️ Step 3: EKS 클러스터 설정

### 3-1. Kubeconfig 업데이트
```yaml
  - name: Update Kubeconfig
    run: aws eks update-kubeconfig --region ap-northeast-2 --name openwebui
```

**🔍 설명**:
- EKS 클러스터에 연결하기 위한 kubeconfig 파일 생성
- `--name openwebui`: 클러스터 이름 지정

### 3-2. AWS Auth ConfigMap 설정
```yaml
  - name: Apply aws-auth ConfigMap and wait for node
    run: |
      # 노드그룹의 IAM Role ARN 가져오기
      echo "Getting nodegroup role ARN..."
      NODE_ROLE_ARN=$(aws eks describe-nodegroup \
        --cluster-name openwebui \
        --nodegroup-name openwebui-nodegroup \
        --query 'nodegroup.nodeRole' \
        --output text)

      # aws-auth ConfigMap 생성
      echo "Generating aws-auth ConfigMap with correct ARN: $NODE_ROLE_ARN"
      cat > aws-auth.yaml << EOF
      apiVersion: v1
      kind: ConfigMap
      metadata:
        name: aws-auth
        namespace: kube-system
      data:
        mapRoles: |
          - rolearn: $NODE_ROLE_ARN
            username: system:node:{{EC2PrivateDNSName}}
            groups:
              - system:bootstrappers
              - system:nodes
      EOF

      # ConfigMap 적용
      echo "Applying generated aws-auth ConfigMap..."
      kubectl apply -f aws-auth.yaml -n kube-system

      # 노드가 등록될 때까지 대기 (최대 5분)
      echo "Waiting for EKS node to register (up to 5 minutes)..."
      for i in {1..30}; do
        COUNT=$(kubectl get nodes --no-headers 2>/dev/null | wc -l)
        if [ "$COUNT" -gt 0 ]; then
          echo "✅ EKS node registered!"
          break
        fi
        echo "⏳ Still waiting for node... ($i/30)"
        sleep 10
      done

      # 타임아웃 처리
      if [ "$COUNT" -eq 0 ]; then
        echo "❌ Timeout: No EKS nodes registered after 5 minutes."
        kubectl get pods -n kube-system
        kubectl describe configmap aws-auth -n kube-system
        exit 1
      fi
```

**🔍 설명**:
- `aws-auth` ConfigMap: EC2 노드가 EKS 클러스터에 조인하도록 권한 부여
- 노드 등록 대기: 최대 5분간 10초 간격으로 확인
- 실패 시 디버깅 정보 출력

---

## 🛠️ Step 4: 필수 컴포넌트 설치

### 4-1. Helm 설치
```yaml
  - name: Install Helm
    uses: azure/setup-helm@v3
    with:
      version: 'latest'
```

**🔍 설명**:
- Helm: Kubernetes 패키지 매니저
- 차트를 통해 복잡한 애플리케이션을 쉽게 배포

### 4-2. AWS Load Balancer Controller
```yaml
  - name: Install AWS Load Balancer Controller
    run: |
      # IAM Policy 다운로드
      curl -O https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/v2.7.0/docs/install/iam_policy.json
      
      # IAM Policy 생성 (이미 있으면 무시)
      aws iam create-policy \
        --policy-name AWSLoadBalancerControllerIAMPolicy-${{ github.run_id }} \
        --policy-document file://iam_policy.json || true
      
      # CRDs 설치
      kubectl apply -k "https://github.com/aws/eks-charts/stable/aws-load-balancer-controller/crds?ref=master"
      
      # Helm repo 추가 및 업데이트
      helm repo add eks https://aws.github.io/eks-charts
      helm repo update
      
      # Controller 설치
      helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
        -n kube-system \
        --set clusterName=openwebui \
        --set serviceAccount.create=true
```

**🔍 설명**:
- AWS Load Balancer Controller: ALB/NLB 자동 생성 관리
- IAM Policy: Controller가 AWS 리소스를 관리할 권한
- CRDs: Custom Resource Definitions 설치

### 4-3. Metrics Server
```yaml
  - name: Install Metrics Server
    run: |
      kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
```

**🔍 설명**:
- CPU/메모리 사용량 수집
- HPA(Horizontal Pod Autoscaler) 동작에 필요

### 4-4. EBS CSI Driver
```yaml
  - name: Install EBS CSI Driver
    run: |
      # EBS CSI Driver addon 추가
      aws eks create-addon \
        --cluster-name openwebui \
        --addon-name aws-ebs-csi-driver \
        --resolve-conflicts OVERWRITE || true
      
      # Addon이 준비될 때까지 대기
      sleep 60
```

**🔍 설명**:
- EBS CSI Driver: EBS 볼륨을 Kubernetes에서 사용
- EKS Addon으로 설치하여 자동 업데이트 지원

### 4-5. StorageClass 생성
```yaml
  - name: Create StorageClass
    run: |
      cat <<EOF | kubectl apply -f -
      apiVersion: storage.k8s.io/v1
      kind: StorageClass
      metadata:
        name: gp3
      provisioner: ebs.csi.aws.com
      parameters:
        type: gp3
        fsType: ext4
      volumeBindingMode: WaitForFirstConsumer
      allowVolumeExpansion: true
      EOF
```

**🔍 설명**:
- GP3: 최신 EBS 볼륨 타입 (성능/비용 최적화)
- `WaitForFirstConsumer`: Pod가 스케줄링된 AZ에 볼륨 생성
- `allowVolumeExpansion`: 볼륨 크기 확장 허용

---

## 🚢 Step 5: ArgoCD 설치 및 설정

### 5-1. ArgoCD 설치
```yaml
  - name: Install ArgoCD
    run: |
      # ArgoCD 네임스페이스 생성
      kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
      
      # ArgoCD 매니페스트 적용
      kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
```

**🔍 설명**:
- `--dry-run=client`: 이미 존재해도 오류 없이 처리
- ArgoCD: GitOps 기반 지속적 배포 도구

### 5-2. ArgoCD 준비 대기
```yaml
  - name: Wait for ArgoCD to be Ready
    run: |
      echo "Waiting for ArgoCD server pod to be ready..."
      kubectl wait --for=condition=available --timeout=180s deployment/argocd-server -n argocd
```

### 5-3. LoadBalancer 서비스 노출
```yaml
  - name: Expose ArgoCD Server with LoadBalancer
    run: kubectl apply -f argocd/argocd-server-service.yaml
```

### 5-4. ArgoCD Application 생성
```yaml
  - name: Apply ArgoCD Application
    run: kubectl apply -f argocd/argocd-app.yaml
```

---

## 📦 Step 6: 애플리케이션 배포

### 6-1. Kubernetes 매니페스트 적용
```yaml
  - name: Apply Kubernetes Manifests
    run: |
      # 스토리지 관련 리소스
      if [ -d "kubernetes/manifests/storage" ]; then
        kubectl apply -f kubernetes/manifests/storage/
      fi
      
      # 데이터베이스
      if [ -d "kubernetes/manifests/database" ]; then
        kubectl apply -f kubernetes/manifests/database/
      fi
      
      # 기본 매니페스트
      kubectl apply -f kubernetes/manifests/
      
      # 오토스케일링
      if [ -d "kubernetes/manifests/autoscaling" ]; then
        kubectl apply -f kubernetes/manifests/autoscaling/
      fi
      
      # 네트워크 정책
      if [ -d "kubernetes/manifests/network" ]; then
        kubectl apply -f kubernetes/manifests/network/
      fi
      
      # Ingress
      if [ -d "kubernetes/manifests/ingress" ]; then
        kubectl apply -f kubernetes/manifests/ingress/
      fi
      
      # 모니터링
      if [ -d "kubernetes/manifests/monitoring" ]; then
        kubectl apply -f kubernetes/manifests/monitoring/
      fi
```

**🔍 설명**:
- 순서대로 리소스 생성 (의존성 고려)
- 디렉토리가 있는 경우에만 적용

### 6-2. 배포 상태 확인
```yaml
  - name: Wait for Deployments
    run: |
      for DEPLOY in openwebui-v1 openwebui-v2 litellm nginx-ab-proxy; do
        if kubectl get deployment "$DEPLOY" -n default &> /dev/null; then
          echo "Waiting for deployment $DEPLOY to complete..."
          kubectl rollout status deployment/"$DEPLOY" -n default --timeout=300s
        else
          echo "Deployment $DEPLOY not found. Skipping."
        fi
      done
```

**🔍 설명**:
- 각 배포가 완료될 때까지 대기
- 존재하지 않는 배포는 건너뛰기

---

## ✅ Step 7: 헬스체크 및 마무리

### 7-1. 헬스체크
```yaml
  - name: Health Check
    run: |
      echo "Waiting for all pods to be ready..."
      kubectl wait --for=condition=ready pod -l app=openwebui-v1 --timeout=300s || true
      kubectl wait --for=condition=ready pod -l app=litellm --timeout=300s || true
      kubectl wait --for=condition=ready pod -l app=nginx-ab-proxy --timeout=300s || true
```

### 7-2. 실패 시 롤백
```yaml
  - name: Rollback on Failure
    if: failure()
    run: |
      echo "Deployment failed. Rolling back..."
      kubectl rollout undo deployment/openwebui-v1 || true
      kubectl rollout undo deployment/openwebui-v2 || true
      kubectl rollout undo deployment/litellm || true
      kubectl rollout undo deployment/nginx-ab-proxy || true
      exit 1
```

### 7-3. Load Balancer URL 확인
```yaml
  - name: Get Load Balancer URL
    run: |
      echo "Waiting for Load Balancer to be ready..."
      sleep 30
      
      # ArgoCD LoadBalancer URL
      ARGOCD_LB=$(kubectl get svc argocd-server -n argocd -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' || echo "Not ready")
      echo "ArgoCD available at: http://$ARGOCD_LB"
      
      # Application LoadBalancer URL
      if kubectl get ingress openwebui-ingress -n default 2>/dev/null; then
        LB_URL=$(kubectl get ingress openwebui-ingress -n default -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' || echo "Not ready")
        echo "Application available at: http://$LB_URL"
      fi
```

---

## 🎯 트러블슈팅 가이드

### 일반적인 문제 해결

#### 1. Terraform 실패
```bash
# 상태 확인
terraform show

# 특정 리소스만 재생성
terraform apply -replace="aws_eks_cluster.openwebui"
```

#### 2. 노드가 준비되지 않음
```bash
# 노드 상태 확인
kubectl get nodes
kubectl describe nodes

# aws-auth ConfigMap 확인
kubectl get configmap aws-auth -n kube-system -o yaml
```

#### 3. Pod가 시작되지 않음
```bash
# Pod 상태 확인
kubectl get pods -A
kubectl describe pod <pod-name>
kubectl logs <pod-name>
```

#### 4. LoadBalancer가 생성되지 않음
```bash
# AWS Load Balancer Controller 로그 확인
kubectl logs -n kube-system deployment/aws-load-balancer-controller
```

---

## 📈 모니터링 및 로깅

### GitHub Actions 로그
- Actions 탭에서 각 단계별 로그 확인
- 실패한 단계 클릭하여 상세 로그 확인

### kubectl 명령어로 확인
```bash
# 전체 리소스 상태
kubectl get all -A

# 이벤트 확인
kubectl get events -A --sort-by='.lastTimestamp'

# 특정 네임스페이스 리소스
kubectl get all -n argocd
```

---

## 🔄 지속적인 개선

### 파이프라인 최적화
1. **병렬 처리**: 독립적인 작업은 병렬로 실행
2. **캐싱**: Docker 이미지, Terraform 상태 캐싱
3. **조건부 실행**: 변경된 부분만 배포

### 보안 강화
1. **IRSA**: Pod별 IAM 역할 사용
2. **Network Policy**: Pod 간 통신 제한
3. **Secret 관리**: AWS Secrets Manager 활용

이제 완전한 CI/CD 파이프라인이 구축되었습니다! 🎉
