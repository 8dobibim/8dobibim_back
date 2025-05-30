# 🔄 CI/CD 파이프라인 가이드

> **⏱️ 예상 소요시간**: 60-90분  
> **💡 난이도**: 중급-고급  
> **📋 목표**: GitHub Actions를 사용하여 완전한 CI/CD 파이프라인을 구축합니다.

---

## 📋 설정 완료 체크리스트

- [ ] GitHub Actions 워크플로우 설정
- [ ] Docker 이미지 빌드 자동화
- [ ] Terraform 인프라 파이프라인
- [ ] Kubernetes 배포 자동화
- [ ] 시크릿 및 환경 변수 설정
- [ ] 배포 승인 프로세스

---

## 🗂️ 1. GitHub Actions 기본 설정

### 리포지토리 구조
```
.github/
└── workflows/
    ├── ci.yml                 # 코드 테스트 및 빌드
    ├── terraform.yml          # 인프라 배포
    ├── deploy-dev.yml          # 개발환경 배포
    └── deploy-prod.yml         # 운영환경 배포
```

### GitHub Secrets 설정
```bash
# GitHub 리포지토리 설정 > Secrets and variables > Actions

# AWS 자격증명
AWS_ACCESS_KEY_ID: AKIA...
AWS_SECRET_ACCESS_KEY: ...
AWS_REGION: ap-northeast-2

# Docker Hub (선택사항)
DOCKER_USERNAME: your-username
DOCKER_PASSWORD: your-token

# Kubernetes
KUBE_CONFIG_DATA: base64로 인코딩된 kubeconfig

# 애플리케이션
OPENAI_API_KEY: sk-...
ANTHROPIC_API_KEY: ...
POSTGRES_PASSWORD: secure-password
```

### kubeconfig 인코딩
```bash
# kubeconfig를 base64로 인코딩하여 GitHub Secrets에 저장
cat ~/.kube/config | base64 | tr -d '\n'
```

---

## 🏗️ 2. CI 워크플로우 (코드 테스트 및 빌드)

### .github/workflows/ci.yml
```yaml
name: CI Pipeline

on:
  push:
    branches: [ main, develop ]
  pull_request:
    branches: [ main ]

env:
  REGISTRY: ghcr.io
  IMAGE_NAME: ${{ github.repository }}

jobs:
  # 코드 품질 검사
  code-quality:
    runs-on: ubuntu-latest
    steps:
    - uses: actions/checkout@v4
    
    - name: Setup Python
      uses: actions/setup-python@v4
      with:
        python-version: '3.11'
    
    - name: Install dependencies
      run: |
        pip install flake8 black isort pytest
    
    - name: Code formatting check
      run: |
        black --check .
        isort --check-only .
    
    - name: Lint code
      run: flake8 .
    
    - name: Run tests
      run: pytest tests/

  # Docker 이미지 빌드 및 푸시
  build-and-push:
    needs: code-quality
    runs-on: ubuntu-latest
    permissions:
      contents: read
      packages: write
    
    steps:
    - uses: actions/checkout@v4
    
    - name: Log in to Container Registry
      uses: docker/login-action@v3
      with:
        registry: ${{ env.REGISTRY }}
        username: ${{ github.actor }}
        password: ${{ secrets.GITHUB_TOKEN }}
    
    - name: Extract metadata
      id: meta
      uses: docker/metadata-action@v5
      with:
        images: ${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}
        tags: |
          type=ref,event=branch
          type=ref,event=pr
          type=sha,prefix={{branch}}-
    
    - name: Build and push Docker image
      uses: docker/build-push-action@v5
      with:
        context: .
        file: ./Dockerfile
        push: true
        tags: ${{ steps.meta.outputs.tags }}
        labels: ${{ steps.meta.outputs.labels }}
        cache-from: type=gha
        cache-to: type=gha,mode=max

  # 보안 스캔
  security-scan:
    needs: build-and-push
    runs-on: ubuntu-latest
    steps:
    - name: Run Trivy vulnerability scanner
      uses: aquasecurity/trivy-action@master
      with:
        image-ref: ${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}:${{ github.sha }}
        format: 'sarif'
        output: 'trivy-results.sarif'
    
    - name: Upload Trivy scan results
      uses: github/codeql-action/upload-sarif@v2
      with:
        sarif_file: 'trivy-results.sarif'
```

---

## 🏗️ 3. Terraform 인프라 파이프라인

### .github/workflows/terraform.yml
```yaml
name: Terraform Infrastructure

on:
  push:
    branches: [ main ]
    paths: [ 'terraform/**' ]
  pull_request:
    branches: [ main ]
    paths: [ 'terraform/**' ]
  workflow_dispatch:
    inputs:
      environment:
        description: 'Environment to deploy'
        required: true
        default: 'dev'
        type: choice
        options: [ 'dev', 'prod' ]
      action:
        description: 'Terraform action'
        required: true
        default: 'plan'
        type: choice
        options: [ 'plan', 'apply', 'destroy' ]

env:
  TF_VERSION: '1.5'
  AWS_REGION: ap-northeast-2

jobs:
  terraform:
    runs-on: ubuntu-latest
    environment: ${{ github.event.inputs.environment || 'dev' }}
    
    defaults:
      run:
        working-directory: terraform/environments/${{ github.event.inputs.environment || 'dev' }}
    
    steps:
    - uses: actions/checkout@v4
    
    - name: Setup Terraform
      uses: hashicorp/setup-terraform@v3
      with:
        terraform_version: ${{ env.TF_VERSION }}
    
    - name: Configure AWS credentials
      uses: aws-actions/configure-aws-credentials@v4
      with:
        aws-access-key-id: ${{ secrets.AWS_ACCESS_KEY_ID }}
        aws-secret-access-key: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
        aws-region: ${{ env.AWS_REGION }}
    
    - name: Terraform Init
      run: terraform init
    
    - name: Terraform Validate
      run: terraform validate
    
    - name: Terraform Plan
      id: plan
      run: |
        terraform plan -var-file="terraform.tfvars" -out=tfplan
        terraform show -no-color tfplan > plan.txt
    
    - name: Comment PR with Plan
      if: github.event_name == 'pull_request'
      uses: actions/github-script@v7
      with:
        script: |
          const fs = require('fs');
          const plan = fs.readFileSync('terraform/environments/${{ github.event.inputs.environment || 'dev' }}/plan.txt', 'utf8');
          const maxGitHubBodyCharacters = 65536;
          
          function chunkSubstr(str, size) {
            const numChunks = Math.ceil(str.length / size)
            const chunks = new Array(numChunks)
            for (let i = 0, o = 0; i < numChunks; ++i, o += size) {
              chunks[i] = str.substr(o, size)
            }
            return chunks
          }
          
          const body = plan.length > maxGitHubBodyCharacters ? 
            `$\{plan.substring(0, maxGitHubBodyCharacters)}\n...` : plan;
          
          github.rest.issues.createComment({
            issue_number: context.issue.number,
            owner: context.repo.owner,
            repo: context.repo.repo,
            body: `## Terraform Plan\n\`\`\`\n${body}\n\`\`\``
          });
    
    - name: Terraform Apply
      if: |
        (github.ref == 'refs/heads/main' && github.event_name == 'push') ||
        (github.event.inputs.action == 'apply')
      run: terraform apply -auto-approve tfplan
    
    - name: Terraform Destroy
      if: github.event.inputs.action == 'destroy'
      run: terraform destroy -var-file="terraform.tfvars" -auto-approve
```

---

## 🐳 4. Docker 워크플로우

### 멀티 스테이지 Dockerfile
```dockerfile
# Dockerfile
# 빌드 스테이지
FROM node:18-alpine AS builder
WORKDIR /app
COPY package*.json ./
RUN npm ci --only=production

# 운영 스테이지
FROM node:18-alpine AS production
WORKDIR /app

# 보안: 비root 사용자 생성
RUN addgroup -g 1001 -S nodejs && \
    adduser -S openwebui -u 1001

# 종속성 복사
COPY --from=builder --chown=openwebui:nodejs /app/node_modules ./node_modules
COPY --chown=openwebui:nodejs . .

# 포트 노출
EXPOSE 8080

# 사용자 전환
USER openwebui

# 헬스체크
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD curl -f http://localhost:8080/health || exit 1

# 애플리케이션 실행
CMD ["npm", "start"]
```

### Docker 빌드 최적화 스크립트
```yaml
# Docker 빌드 최적화 (CI 워크플로우 내 추가 설정)
- name: Set up Docker Buildx
  uses: docker/setup-buildx-action@v3

- name: Build and push with cache
  uses: docker/build-push-action@v5
  with:
    context: .
    platforms: linux/amd64,linux/arm64  # 멀티 아키텍처
    push: true
    tags: ${{ steps.meta.outputs.tags }}
    cache-from: type=gha
    cache-to: type=gha,mode=max
    build-args: |
      BUILDKIT_INLINE_CACHE=1
```

---

## ☸️ 5. Kubernetes 배포 파이프라인

### 개발환경 배포: .github/workflows/deploy-dev.yml
```yaml
name: Deploy to Development

on:
  push:
    branches: [ develop ]
  workflow_dispatch:

env:
  AWS_REGION: ap-northeast-2
  EKS_CLUSTER_NAME: openwebui-eks-dev

jobs:
  deploy:
    runs-on: ubuntu-latest
    environment: development
    
    steps:
    - uses: actions/checkout@v4
    
    - name: Configure AWS credentials
      uses: aws-actions/configure-aws-credentials@v4
      with:
        aws-access-key-id: ${{ secrets.AWS_ACCESS_KEY_ID }}
        aws-secret-access-key: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
        aws-region: ${{ env.AWS_REGION }}
    
    - name: Setup kubectl
      uses: azure/setup-kubectl@v3
      with:
        version: 'v1.28.0'
    
    - name: Update kubeconfig
      run: |
        aws eks update-kubeconfig --region ${{ env.AWS_REGION }} --name ${{ env.EKS_CLUSTER_NAME }}
    
    - name: Create/Update Secrets
      run: |
        kubectl create namespace openwebui --dry-run=client -o yaml | kubectl apply -f -
        kubectl create namespace litellm --dry-run=client -o yaml | kubectl apply -f -
        
        # PostgreSQL 인증정보
        kubectl create secret generic app-secrets \
          --from-literal=POSTGRES_USER=openwebui \
          --from-literal=POSTGRES_PASSWORD=${{ secrets.POSTGRES_PASSWORD }} \
          -n openwebui \
          --dry-run=client -o yaml | kubectl apply -f -
        
        # API 키들
        kubectl create secret generic api-keys \
          --from-literal=OPENAI_API_KEY=${{ secrets.OPENAI_API_KEY }} \
          --from-literal=ANTHROPIC_API_KEY=${{ secrets.ANTHROPIC_API_KEY }} \
          --from-literal=LITELLM_MASTER_KEY=${{ secrets.LITELLM_MASTER_KEY }} \
          -n litellm \
          --dry-run=client -o yaml | kubectl apply -f -
    
    - name: Deploy to Kubernetes
      run: |
        # 이미지 태그 업데이트
        export IMAGE_TAG=${{ github.sha }}
        envsubst < kubernetes/base/openwebui/deployment.yaml | kubectl apply -f -
        envsubst < kubernetes/base/litellm/deployment.yaml | kubectl apply -f -
        
        # 나머지 리소스 배포
        kubectl apply -f kubernetes/base/configmaps/
        kubectl apply -f kubernetes/base/postgres/
        kubectl apply -f kubernetes/base/openwebui/
        kubectl apply -f kubernetes/base/litellm/
        kubectl apply -f kubernetes/base/ingress/
    
    - name: Wait for deployment
      run: |
        kubectl rollout status deployment/openwebui -n openwebui --timeout=600s
        kubectl rollout status deployment/litellm -n litellm --timeout=600s
        kubectl rollout status deployment/postgres -n openwebui --timeout=600s
    
    - name: Run smoke tests
      run: |
        # 포트 포워딩으로 헬스체크
        kubectl port-forward svc/openwebui-service 8080:8080 -n openwebui &
        sleep 10
        
        # HTTP 상태 확인
        if curl -f http://localhost:8080/health; then
          echo "✅ Health check passed"
        else
          echo "❌ Health check failed"
          exit 1
        fi
```

### 운영환경 배포: .github/workflows/deploy-prod.yml
```yaml
name: Deploy to Production

on:
  release:
    types: [created]
  workflow_dispatch:
    inputs:
      version:
        description: 'Version to deploy'
        required: true
        default: 'latest'

env:
  AWS_REGION: ap-northeast-2
  EKS_CLUSTER_NAME: openwebui-eks-prod

jobs:
  deploy:
    runs-on: ubuntu-latest
    environment: production  # 수동 승인 필요
    
    steps:
    - uses: actions/checkout@v4
      with:
        ref: ${{ github.event.inputs.version || github.event.release.tag_name }}
    
    # AWS 및 kubectl 설정 (dev와 동일)
    
    - name: Blue-Green Deployment
      run: |
        # 현재 버전 확인
        CURRENT_VERSION=$(kubectl get deployment openwebui -n openwebui -o jsonpath='{.metadata.labels.version}' || echo "none")
        NEW_VERSION=${{ github.event.inputs.version || github.event.release.tag_name }}
        
        # 새 버전 배포 (Blue-Green)
        kubectl patch deployment openwebui -n openwebui -p \
          '{"spec":{"template":{"metadata":{"labels":{"version":"'$NEW_VERSION'"}},"spec":{"containers":[{"name":"openwebui","image":"ghcr.io/${{ github.repository }}:'$NEW_VERSION'"}]}}}}'
        
        # 배포 완료 대기
        kubectl rollout status deployment/openwebui -n openwebui --timeout=600s
    
    - name: Production smoke tests
      run: |
        # 더 엄격한 테스트
        kubectl port-forward svc/openwebui-service 8080:8080 -n openwebui &
        sleep 30
        
        # 헬스체크
        curl -f http://localhost:8080/health
        
        # API 테스트
        curl -f http://localhost:8080/api/v1/models
        
        # 응답시간 테스트 (5초 이내)
        RESPONSE_TIME=$(curl -o /dev/null -s -w '%{time_total}' http://localhost:8080)
        if (( $(echo "$RESPONSE_TIME > 5" | bc -l) )); then
          echo "❌ Response time too slow: ${RESPONSE_TIME}s"
          exit 1
        fi
    
    - name: Rollback on failure
      if: failure()
      run: |
        echo "🔄 Rolling back to previous version"
        kubectl rollout undo deployment/openwebui -n openwebui
        kubectl rollout status deployment/openwebui -n openwebui --timeout=300s
```

---

## 🔒 6. 보안 및 승인 프로세스

### GitHub Environment 보호 규칙
```yaml
# .github/environments/production.yml (GitHub 설정)
protection_rules:
  required_reviewers:
    - team: devops-team
    - user: tech-lead
  wait_timer: 5  # 5분 대기
  
deployment_branch_policy:
  protected_branches: true
  custom_branches: false
```

### 보안 스캔 통합
```yaml
# 보안 스캔 워크플로우 (CI에 추가)
- name: SAST Scan
  uses: github/codeql-action/analyze@v2
  with:
    languages: javascript, python

- name: Container Scan
  uses: aquasecurity/trivy-action@master
  with:
    image-ref: ${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}:${{ github.sha }}

- name: Infrastructure Scan
  uses: aquasecurity/trivy-action@master
  with:
    scan-type: 'config'
    scan-ref: 'terraform/'
```

---

## 📊 7. 모니터링 및 알림

### Slack 통합
```yaml
# 배포 결과 Slack 알림
- name: Notify Slack
  if: always()
  uses: 8398a7/action-slack@v3
  with:
    status: ${{ job.status }}
    channel: '#deployments'
    webhook_url: ${{ secrets.SLACK_WEBHOOK }}
    fields: repo,message,commit,author,action,eventName,ref,workflow
```

### 배포 메트릭 수집
```yaml
- name: Record deployment metrics
  run: |
    # 배포 시간 기록
    echo "deployment_duration_seconds{environment=\"${{ github.event.inputs.environment }}\",version=\"${{ github.sha }}\"} $(date +%s)" | \
    curl -X POST -H 'Content-Type: text/plain' --data-binary @- \
    ${{ secrets.PROMETHEUS_PUSHGATEWAY }}/metrics/job/github-actions
```

---

## 🔄 8. GitOps 워크플로우 (선택사항)

### ArgoCD 연동
```yaml
# GitOps 스타일 배포
- name: Update GitOps repository
  run: |
    git clone https://github.com/your-org/k8s-manifests.git
    cd k8s-manifests
    
    # 이미지 태그 업데이트
    yq eval '.spec.template.spec.containers[0].image = "ghcr.io/${{ github.repository }}:${{ github.sha }}"' \
      -i environments/${{ github.event.inputs.environment }}/openwebui/deployment.yaml
    
    # 변경사항 커밋
    git config user.name "GitHub Actions"
    git config user.email "actions@github.com"
    git add .
    git commit -m "Update image to ${{ github.sha }}"
    git push
```

---

## 📈 9. 성능 및 품질 게이트

### 배포 전 품질 검증
```yaml
quality-gate:
  runs-on: ubuntu-latest
  steps:
  - name: Code coverage check
    run: |
      COVERAGE=$(pytest --cov=app tests/ --cov-report=term-missing | grep TOTAL | awk '{print $4}' | sed 's/%//')
      if [ $COVERAGE -lt 80 ]; then
        echo "❌ Code coverage below 80%: ${COVERAGE}%"
        exit 1
      fi
  
  - name: Performance test
    run: |
      # K6 성능 테스트
      k6 run --out json=results.json performance-test.js
      
      # 결과 검증 (평균 응답시간 500ms 이하)
      AVG_RESPONSE=$(jq '.metrics.http_req_duration.values.avg' results.json)
      if (( $(echo "$AVG_RESPONSE > 500" | bc -l) )); then
        echo "❌ Performance test failed: ${AVG_RESPONSE}ms > 500ms"
        exit 1
      fi
```

---

## 🚀 10. 배포 스크립트 실행

### 전체 파이프라인 테스트
```bash
#!/bin/bash
# test-pipeline.sh

echo "🔄 CI/CD 파이프라인 테스트..."

# 1. 코드 변경 시뮬레이션
echo "1. 코드 변경 및 커밋"
git checkout -b feature/test-pipeline
echo "Test change" >> README.md
git add README.md
git commit -m "test: pipeline test"
git push origin feature/test-pipeline

# 2. PR 생성 (GitHub CLI 필요)
gh pr create --title "Test Pipeline" --body "Testing CI/CD pipeline"

# 3. PR 상태 확인
gh pr status

echo "✅ 파이프라인 테스트 완료"
echo "GitHub Actions 탭에서 워크플로우 실행 상태를 확인하세요."
```

### 수동 배포 트리거
```bash
# GitHub CLI로 수동 배포 실행
gh workflow run deploy-dev.yml

# 특정 환경에 배포
gh workflow run terraform.yml -f environment=prod -f action=apply

# 배포 상태 확인
gh run list --workflow=deploy-dev.yml
```

---

## 🎯 **파이프라인 최적화 팁**

### 빌드 시간 단축
- Docker 레이어 캐싱 활용
- 병렬 작업 최대한 활용
- 불필요한 단계 제거

### 보안 강화
- Secrets 스캔 정기 실행
- 최소 권한 원칙 적용
- 감사 로그 유지

### 안정성 향상
- 점진적 배포 (Canary)
- 자동 롤백 메커니즘
- 포괄적인 테스트 커버리지

이제 완전한 CI/CD 파이프라인이 구축되었습니다! 🎉
