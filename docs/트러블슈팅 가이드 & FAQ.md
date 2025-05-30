# 🚨 트러블슈팅 가이드 & FAQ



---

## 🔍 빠른 문제 진단

### 1단계: 기본 상태 확인 (30초)
```bash
# 한 번에 전체 상태 확인
kubectl get nodes,pods -A | grep -E "(NotReady|Error|CrashLoop|Pending)"

# 최근 이벤트 확인
kubectl get events -A --sort-by='.lastTimestamp' | tail -10
```

### 2단계: 애플리케이션별 상태 (1분)
```bash
# OpenWebUI 상태
kubectl get pods -n openwebui -o wide

# LiteLLM 상태  
kubectl get pods -n litellm -o wide

# 데이터베이스 상태
kubectl get pods -n openwebui -l app=postgres
```

### 3단계: 리소스 사용량 (30초)
```bash
# 노드 리소스
kubectl top nodes

# 파드 리소스
kubectl top pods -A --sort-by=cpu
```

---

## 🔧 인프라 관련 문제

### ❌ 노드가 NotReady 상태

**증상:**
```
NAME       STATUS     ROLES    AGE   VERSION
node-1     NotReady   <none>   1d    v1.28.0
```

**원인 분석:**
```bash
# 노드 상세 정보 확인
kubectl describe node node-1

# 노드 로그 확인 (SSH 접속 필요)
sudo journalctl -u kubelet -f
```

**해결 방법:**
```bash
# 1. kubelet 재시작
sudo systemctl restart kubelet

# 2. 노드 재부팅 (심각한 경우)
sudo reboot

# 3. 노드 교체 (복구 불가능한 경우)
kubectl drain node-1 --ignore-daemonsets --delete-emptydir-data
kubectl delete node node-1
# AWS 콘솔에서 인스턴스 종료 (Auto Scaling이 새 노드 생성)
```

### ❌ 파드가 Pending 상태

**증상:**
```
NAME                         READY   STATUS    RESTARTS   AGE
openwebui-5f7b8d6c9d-xyz     0/1     Pending   0          5m
```

**원인 분석:**
```bash
kubectl describe pod openwebui-5f7b8d6c9d-xyz -n openwebui
```

**일반적인 원인과 해결:**

1. **리소스 부족**
```bash
# 원인: Insufficient cpu/memory
# 해결: 리소스 요청량 조정 또는 노드 추가
kubectl patch deployment openwebui -n openwebui -p \
  '{"spec":{"template":{"spec":{"containers":[{"name":"openwebui","resources":{"requests":{"cpu":"100m","memory":"256Mi"}}}]}}}}'
```

2. **PVC 마운트 실패**
```bash
# 원인: PVC not found or pending
# PVC 상태 확인
kubectl get pvc -n openwebui

# StorageClass 확인
kubectl get storageclass

# 해결: PVC 재생성
kubectl delete pvc openwebui-pvc -n openwebui
kubectl apply -f kubernetes/base/openwebui/pvc.yaml
```

3. **노드 셀렉터 문제**
```bash
# 원인: No nodes match nodeSelector
# 노드 레이블 확인
kubectl get nodes --show-labels

# 해결: nodeSelector 제거 또는 레이블 추가
kubectl label nodes node-1 environment=dev
```

### ❌ 이미지 Pull 실패

**증상:**
```
Failed to pull image "ghcr.io/openwebui:latest": rpc error: code = Unknown desc = failed to pull and unpack image
```

**해결 방법:**
```bash
# 1. 이미지 태그 확인
docker pull ghcr.io/openwebui:latest

# 2. 레지스트리 접근 권한 확인
kubectl get secret -n openwebui | grep docker

# 3. 이미지 태그 수정
kubectl set image deployment/openwebui openwebui=ghcr.io/openwebui:v1.0.0 -n openwebui

# 4. 대체 이미지 사용
kubectl set image deployment/openwebui openwebui=nginx:latest -n openwebui
```

---

## 🌐 네트워킹 문제

### ❌ 서비스 연결 실패

**증상:**
```bash
curl: (7) Failed to connect to service-name port 80: Connection refused
```

**진단 순서:**
```bash
# 1. 서비스 확인
kubectl get svc -n openwebui

# 2. 엔드포인트 확인
kubectl get endpoints -n openwebui

# 3. 파드 라벨 확인
kubectl get pods -n openwebui --show-labels

# 4. 서비스 셀렉터 확인
kubectl get svc openwebui-service -n openwebui -o yaml | grep -A 5 selector
```

**해결 방법:**
```bash
# 서비스와 파드 라벨 매칭 확인
kubectl patch svc openwebui-service -n openwebui -p \
  '{"spec":{"selector":{"app":"openwebui"}}}'

# 파드 재시작
kubectl rollout restart deployment/openwebui -n openwebui
```

### ❌ Ingress 접근 불가

**증상:**
```bash
curl: (52) Empty reply from server
```

**진단:**
```bash
# Ingress 상태 확인
kubectl get ingress -n openwebui -o wide

# Ingress Controller 상태
kubectl get pods -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller

# ALB 상태 확인 (AWS)
aws elbv2 describe-load-balancers
```

**해결 방법:**
```bash
# 1. Ingress 재생성
kubectl delete ingress openwebui-ingress -n openwebui
kubectl apply -f kubernetes/base/ingress/ingress.yaml

# 2. 서비스 타입을 LoadBalancer로 임시 변경
kubectl patch svc openwebui-service -n openwebui -p \
  '{"spec":{"type":"LoadBalancer"}}'

# 3. 포트 포워딩으로 임시 접근
kubectl port-forward svc/openwebui-service 8080:8080 -n openwebui
```

### ❌ DNS 해석 실패

**증상:**
```bash
nslookup: can't resolve 'service-name.namespace.svc.cluster.local'
```

**진단 및 해결:**
```bash
# CoreDNS 상태 확인
kubectl get pods -n kube-system -l k8s-app=kube-dns

# DNS 설정 확인
kubectl get configmap coredns -n kube-system -o yaml

# DNS 테스트
kubectl run debug --image=busybox -it --rm -- nslookup kubernetes.default.svc.cluster.local

# CoreDNS 재시작
kubectl rollout restart deployment/coredns -n kube-system
```

---

## 🗃️ 데이터베이스 문제

### ❌ PostgreSQL 연결 실패

**증상:**
```
psql: FATAL: password authentication failed for user "openwebui"
```

**진단:**
```bash
# 파드 상태 확인
kubectl get pods -l app=postgres -n openwebui

# 로그 확인
kubectl logs deployment/postgres -n openwebui

# 시크릿 확인
kubectl get secret app-secrets -n openwebui -o yaml
```

**해결 방법:**
```bash
# 1. 시크릿 재생성
kubectl delete secret app-secrets -n openwebui
kubectl create secret generic app-secrets \
  --from-literal=POSTGRES_USER=openwebui \
  --from-literal=POSTGRES_PASSWORD=newpassword \
  -n openwebui

# 2. 데이터베이스 재시작
kubectl rollout restart deployment/postgres -n openwebui

# 3. 직접 연결 테스트
kubectl exec -it deployment/postgres -n openwebui -- \
  psql -U openwebui -d openwebui -c "SELECT 1;"
```

### ❌ 데이터베이스 디스크 부족

**증상:**
```
ERROR: could not extend file "base/16384/16439": No space left on device
```

**해결 방법:**
```bash
# 1. PVC 크기 확장
kubectl patch pvc postgres-pvc -n openwebui -p \
  '{"spec":{"resources":{"requests":{"storage":"20Gi"}}}}'

# 2. 불필요한 데이터 정리
kubectl exec deployment/postgres -n openwebui -- \
  psql -U openwebui -d openwebui -c "VACUUM FULL;"

# 3. 백업 후 데이터베이스 재생성
# 백업 실행
kubectl exec deployment/postgres -n openwebui -- \
  pg_dump -U openwebui openwebui > backup.sql

# PVC 삭제 및 재생성
kubectl delete pvc postgres-pvc -n openwebui
kubectl apply -f kubernetes/base/postgres/pvc.yaml

# 복원
kubectl exec -i deployment/postgres -n openwebui -- \
  psql -U openwebui openwebui < backup.sql
```

---

## 🤖 애플리케이션 문제

### ❌ OpenWebUI 500 에러

**증상:**
```
HTTP 500 Internal Server Error
```

**진단:**
```bash
# 애플리케이션 로그 확인
kubectl logs deployment/openwebui -n openwebui --tail=100

# 환경 변수 확인
kubectl exec deployment/openwebui -n openwebui -- env | grep -E "(DATABASE|SECRET)"

# 헬스체크 확인
kubectl exec deployment/openwebui -n openwebui -- \
  curl -f http://localhost:8080/health
```

**해결 방법:**
```bash
# 1. 애플리케이션 재시작
kubectl rollout restart deployment/openwebui -n openwebui

# 2. 환경 변수 확인 및 수정
kubectl patch deployment openwebui -n openwebui -p \
  '{"spec":{"template":{"spec":{"containers":[{"name":"openwebui","env":[{"name":"DEBUG","value":"true"}]}]}}}}'

# 3. 이전 버전으로 롤백
kubectl rollout undo deployment/openwebui -n openwebui

# 4. 데이터베이스 연결 확인
kubectl exec deployment/openwebui -n openwebui -- \
  nc -zv postgres-service 5432
```

### ❌ LiteLLM API 응답 없음

**증상:**
```bash
curl: (7) Failed to connect to litellm-service port 4000
```

**진단 및 해결:**
```bash
# 파드 상태 확인
kubectl get pods -l app=litellm -n litellm

# API 키 확인
kubectl get secret api-keys -n litellm -o yaml

# 설정 파일 확인
kubectl get configmap litellm-config -n litellm -o yaml

# 직접 API 테스트
kubectl exec deployment/litellm -n litellm -- \
  curl -s http://localhost:4000/health

# 재시작
kubectl rollout restart deployment/litellm -n litellm
```

### ❌ 메모리 부족 (OOMKilled)

**증상:**
```
Last State: Terminated
Reason: OOMKilled
```

**해결 방법:**
```bash
# 1. 메모리 리미트 증가
kubectl patch deployment openwebui -n openwebui -p \
  '{"spec":{"template":{"spec":{"containers":[{"name":"openwebui","resources":{"limits":{"memory":"2Gi"}}}]}}}}'

# 2. 메모리 사용량 확인
kubectl top pods -n openwebui --containers

# 3. 메모리 요청량 조정
kubectl patch deployment openwebui -n openwebui -p \
  '{"spec":{"template":{"spec":{"containers":[{"name":"openwebui","resources":{"requests":{"memory":"512Mi"}}}]}}}}'
```

---

## 📊 성능 문제

### ❌ 느린 응답 시간

**진단:**
```bash
# 응답 시간 측정
kubectl exec deployment/openwebui -n openwebui -- \
  curl -w "Total time: %{time_total}s\n" -o /dev/null -s http://localhost:8080

# 리소스 사용량 확인
kubectl top pods -n openwebui --containers

# 데이터베이스 쿼리 성능 확인
kubectl exec deployment/postgres -n openwebui -- \
  psql -U openwebui -d openwebui -c \
  "SELECT query, mean_exec_time FROM pg_stat_statements ORDER BY mean_exec_time DESC LIMIT 5;"
```

**해결 방법:**
```bash
# 1. HPA 스케일링 확인
kubectl get hpa -n openwebui

# 2. 수동 스케일링
kubectl scale deployment openwebui --replicas=4 -n openwebui

# 3. 리소스 증량
kubectl patch deployment openwebui -n openwebui -p \
  '{"spec":{"template":{"spec":{"containers":[{"name":"openwebui","resources":{"requests":{"cpu":"500m","memory":"1Gi"}}}]}}}}'
```

### ❌ 높은 CPU 사용률

**해결 방법:**
```bash
# CPU 사용률 확인
kubectl top pods -n openwebui --sort-by=cpu

# 프로파일링 (가능한 경우)
kubectl exec deployment/openwebui -n openwebui -- \
  curl -s http://localhost:8080/debug/pprof/profile > cpu.prof

# 수평 스케일링
kubectl patch hpa openwebui-hpa -n openwebui -p \
  '{"spec":{"targetCPUUtilizationPercentage":50}}'
```

---

## 🔒 보안 문제

### ❌ 이미지 취약점

**진단:**
```bash
# 이미지 스캔
trivy image ghcr.io/openwebui:latest

# 실행 중인 이미지 확인
kubectl get pods -n openwebui -o jsonpath='{.items[*].spec.containers[*].image}'
```

**해결 방법:**
```bash
# 1. 최신 이미지 업데이트
kubectl set image deployment/openwebui openwebui=ghcr.io/openwebui:v1.0.1 -n openwebui

# 2. 보안 패치된 베이스 이미지 사용
# Dockerfile 수정 후 재빌드 필요
```

### ❌ 시크릿 노출

**진단:**
```bash
# 시크릿 확인
kubectl get secrets -A

# 파드에서 시크릿 사용 확인
kubectl get pods -n openwebui -o yaml | grep -A 10 secretRef
```

**해결 방법:**
```bash
# 1. 시크릿 로테이션
kubectl delete secret api-keys -n litellm
kubectl create secret generic api-keys \
  --from-literal=OPENAI_API_KEY=new-secure-key \
  -n litellm

# 2. 애플리케이션 재시작
kubectl rollout restart deployment/litellm -n litellm
```

---

## 📋 FAQ (자주 묻는 질문)

### Q1: 파드가 계속 재시작되는 이유는?

**A:** 가장 일반적인 원인들:
```bash
# 1. 헬스체크 실패
kubectl describe pod <pod-name> -n openwebui | grep -A 10 Events

# 2. 메모리 부족 (OOMKilled)
kubectl describe pod <pod-name> -n openwebui | grep OOMKilled

# 3. 애플리케이션 에러
kubectl logs <pod-name> -n openwebui --previous

# 해결: 리소스 증량 또는 헬스체크 조정
```

### Q2: 배포 후 외부에서 접근이 안 돼요

**A:** 단계별 확인:
```bash
# 1. 파드 상태
kubectl get pods -n openwebui

# 2. 서비스 상태  
kubectl get svc -n openwebui

# 3. Ingress 상태
kubectl get ingress -n openwebui

# 4. 로드밸런서 상태 (AWS 콘솔 확인)
aws elbv2 describe-load-balancers

# 임시 해결: 포트 포워딩
kubectl port-forward svc/openwebui-service 8080:8080 -n openwebui
```

### Q3: 데이터가 사라졌어요

**A:** 데이터 복구 방법:
```bash
# 1. PVC 상태 확인
kubectl get pvc -n openwebui

# 2. 백업에서 복원
aws s3 ls s3://openwebui-backups/database/

# 3. 최신 백업으로 복원
./restore-database.sh openwebui_backup_20240301_120000.sql
```

### Q4: API 키가 작동하지 않아요

**A:** API 키 확인 및 업데이트:
```bash
# 1. 현재 시크릿 확인
kubectl get secret api-keys -n litellm -o yaml

# 2. 디코딩해서 확인
kubectl get secret api-keys -n litellm -o jsonpath='{.data.OPENAI_API_KEY}' | base64 -d

# 3. 새 키로 업데이트
kubectl create secret generic api-keys \
  --from-literal=OPENAI_API_KEY=sk-new-key \
  --dry-run=client -o yaml | kubectl apply -f -

# 4. 파드 재시작
kubectl rollout restart deployment/litellm -n litellm
```

### Q5: 비용이 예상보다 많이 나와요

**A:** 비용 최적화 방법:
```bash
# 1. 리소스 사용량 확인
kubectl top nodes
kubectl top pods -A

# 2. Spot 인스턴스 활용
kubectl get nodes -l node.kubernetes.io/instance-type

# 3. 사용하지 않는 리소스 정리
kubectl get pods -A --field-selector=status.phase=Succeeded
kubectl delete pods --field-selector=status.phase=Succeeded -A

# 4. HPA 최적화
kubectl patch hpa openwebui-hpa -n openwebui -p \
  '{"spec":{"minReplicas":1,"targetCPUUtilizationPercentage":70}}'
```

### Q6: 로그를 어디서 확인하나요?

**A:** 로그 확인 방법:
```bash
# 1. 실시간 로그
kubectl logs -f deployment/openwebui -n openwebui

# 2. 특정 시간대 로그
kubectl logs --since=1h deployment/openwebui -n openwebui

# 3. 이전 컨테이너 로그 (재시작된 경우)
kubectl logs deployment/openwebui -n openwebui --previous

# 4. 모든 파드 로그
kubectl logs -l app=openwebui -n openwebui

# 5. 중앙화된 로깅 (Kibana)
# http://kibana.your-domain.com에서 확인
```

### Q7: 성능이 느려졌어요

**A:** 성능 진단 단계:
```bash
# 1. 리소스 사용량 확인
kubectl top pods -n openwebui --containers

# 2. 응답 시간 측정
kubectl exec deployment/openwebui -n openwebui -- \
  curl -w "%{time_total}" -o /dev/null -s http://localhost:8080

# 3. 데이터베이스 성능 확인
kubectl exec deployment/postgres -n openwebui -- \
  psql -U openwebui -d openwebui -c \
  "SELECT * FROM pg_stat_activity WHERE state = 'active';"

# 4. 스케일링 실행
kubectl scale deployment openwebui --replicas=3 -n openwebui
```

### Q8: 업데이트는 어떻게 하나요?

**A:** 안전한 업데이트 방법:
```bash
# 1. 백업 먼저 실행
./backup-database.sh

# 2. 새 버전으로 업데이트
kubectl set image deployment/openwebui openwebui=ghcr.io/openwebui:v1.1.0 -n openwebui

# 3. 롤아웃 상태 확인
kubectl rollout status deployment/openwebui -n openwebui

# 4. 문제 발생 시 롤백
kubectl rollout undo deployment/openwebui -n openwebui
```

---

## 🆘 긴급 상황별 대응

### 🔥 전체 서비스 다운

```bash
# 1. 즉시 상태 확인 (30초)
kubectl get nodes,pods -A | grep -v Running

# 2. 트래픽 차단 (임시 점검 페이지)
kubectl patch ingress openwebui-ingress -n openwebui -p \
  '{"metadata":{"annotations":{"nginx.ingress.kubernetes.io/server-snippet":"return 503 \"Service temporarily unavailable\";"}}}'

# 3. 핵심 서비스부터 복구
kubectl rollout restart deployment/postgres -n openwebui
kubectl rollout restart deployment/litellm -n litellm  
kubectl rollout restart deployment/openwebui -n openwebui

# 4. 상태 확인 후 트래픽 복구
kubectl patch ingress openwebui-ingress -n openwebui -p \
  '{"metadata":{"annotations":{"nginx.ingress.kubernetes.io/server-snippet":null}}}'
```

### 💾 데이터 손실 위험

```bash
# 1. 즉시 백업 실행
kubectl exec deployment/postgres -n openwebui -- \
  pg_dump -U openwebui openwebui > emergency_backup_$(date +%Y%m%d_%H%M%S).sql

# 2. PVC 스냅샷 생성 (AWS EBS)
aws ec2 describe-volumes --filters "Name=tag:kubernetes.io/created-for/pvc/name,Values=postgres-pvc"
aws ec2 create-snapshot --volume-id vol-xxxxxxxxx --description "Emergency snapshot"

# 3. 읽기 전용 모드로 전환 (데이터 보호)
kubectl patch deployment openwebui -n openwebui -p \
  '{"spec":{"replicas":0}}'
```

### 🚨 보안 침해 의심

```bash
# 1. 즉시 네트워크 차단
kubectl delete ingress openwebui-ingress -n openwebui

# 2. 로그 수집 및 보존
kubectl logs deployment/openwebui -n openwebui > security_logs_$(date +%Y%m%d_%H%M%S).log

# 3. 시크릿 로테이션
kubectl delete secret api-keys -n litellm
kubectl delete secret app-secrets -n openwebui

# 4. 포렌식 분석용 파드 이미지 보존
kubectl get pods -n openwebui -o yaml > pods_snapshot_$(date +%Y%m%d_%H%M%S).yaml
```

---


### 문서 개선 요청
- 새로운 문제 발생 시 이 문서에 추가
- 해결책이 효과적이지 않은 경우 피드백
- 더 나은 해결 방법 발견 시 공유

---

## 🔄 문제 해결 체크리스트

문제 발생 시 다음 순서로 진행:

- [ ] 기본 상태 확인 (노드, 파드, 서비스)
- [ ] 로그 확인 (애플리케이션, 시스템)
- [ ] 리소스 사용량 확인
- [ ] 최근 변경사항 확인
- [ ] 네트워크 연결 확인
- [ ] 백업 상태 확인
- [ ] 임시 해결책 적용
- [ ] 근본 원인 분석
- [ ] 영구 해결책 적용
- [ ] 문서 업데이트
