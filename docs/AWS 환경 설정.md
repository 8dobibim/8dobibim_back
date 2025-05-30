# 🏗️ AWS 환경 설정 가이드

> **⏱️ 예상 소요시간**: 약 30-45분 (설계 및 계획)  
> **💡 난이도**: 초급-중급  
> **📋 목표**: OpenWebUI 배포를 위한 AWS 인프라 설계 및 구성 계획을 수립합니다.

---

## 📋 설정 완료 체크리스트

- [ ] 네트워크 아키텍처 설계 완료
- [ ] 리소스 명명 규칙 정의
- [ ] 보안 그룹 계획 수립
- [ ] EKS 클러스터 구성 계획
- [ ] 비용 계산 및 예산 설정
- [ ] 백업 및 재해 복구 계획

---

## 🎯 전체 아키텍처 개요

### 시스템 구성도

```
┌─────────────────────────────────────────────────────────────┐
│                        AWS Cloud                           │
│  ┌─────────────────────────────────────────────────────────┐│
│  │                  VPC (10.0.0.0/16)                     ││
│  │  ┌─────────────────────┐  ┌─────────────────────────────┐││
│  │  │   Public Subnet A   │  │    Public Subnet B         │││
│  │  │   (10.0.1.0/24)     │  │    (10.0.2.0/24)          │││
│  │  │  ┌─────────────────┐│  │  ┌─────────────────────────┐│││
│  │  │  │  NAT Gateway A  ││  │  │   NAT Gateway B         ││││
│  │  │  └─────────────────┘│  │  └─────────────────────────┘│││
│  │  │  ┌─────────────────┐│  │  ┌─────────────────────────┐│││
│  │  │  │ Internet Gateway││  │  │   Load Balancer         ││││
│  │  │  └─────────────────┘│  │  └─────────────────────────┘│││
│  │  └─────────────────────┘  └─────────────────────────────┘││
│  │  ┌─────────────────────┐  ┌─────────────────────────────┐││
│  │  │  Private Subnet A   │  │   Private Subnet B          │││
│  │  │   (10.0.10.0/24)    │  │   (10.0.20.0/24)           │││
│  │  │  ┌─────────────────┐│  │  ┌─────────────────────────┐│││
│  │  │  │ EKS Node Group A││  │  │  EKS Node Group B       ││││
│  │  │  │                 ││  │  │                         ││││
│  │  │  │ OpenWebUI Pods  ││  │  │   LiteLLM Pods          ││││
│  │  │  │ Monitoring Pods ││  │  │   Database Pods         ││││
│  │  │  └─────────────────┘│  │  └─────────────────────────┘│││
│  │  └─────────────────────┘  └─────────────────────────────┘││
│  │                                                         ││
│  │  ┌─────────────────────────────────────────────────────┐││
│  │  │                  EKS Control Plane                  ││
│  │  │                 (AWS Managed)                       ││
│  │  └─────────────────────────────────────────────────────┘││
│  └─────────────────────────────────────────────────────────┘│
└─────────────────────────────────────────────────────────────┘

외부 연결:
- ECR (컨테이너 이미지 저장소)
- S3 (Terraform State, 백업)
- DynamoDB (Terraform Lock)
- CloudWatch (로깅 및 모니터링)
```

### 주요 구성 요소 설명

| 구성 요소 | 목적 | 위치 |
|-----------|------|------|
| **VPC** | 격리된 네트워크 환경 | ap-northeast-2 |
| **Public Subnet** | 인터넷 게이트웨이, 로드밸런서 | 2개 AZ |
| **Private Subnet** | EKS 워커 노드, 애플리케이션 | 2개 AZ |
| **EKS Cluster** | Kubernetes 관리형 서비스 | Multi-AZ |
| **Node Groups** | EC2 인스턴스 그룹 | Private Subnet |
| **ALB** | 애플리케이션 로드밸런서 | Public Subnet |

---

## 🌐 네트워크 설계

### VPC 및 서브넷 구성

#### 기본 네트워크 설정
```yaml
VPC 설정:
  CIDR: 10.0.0.0/16
  Region: ap-northeast-2 (서울)
  DNS Resolution: Enabled
  DNS Hostnames: Enabled

가용 영역:
  - ap-northeast-2a
  - ap-northeast-2c
```

#### 서브넷 설계
```yaml
Public Subnets:
  Public-A:
    CIDR: 10.0.1.0/24
    AZ: ap-northeast-2a
    용도: NAT Gateway, Load Balancer
    
  Public-B:
    CIDR: 10.0.2.0/24
    AZ: ap-northeast-2c
    용도: NAT Gateway, Load Balancer

Private Subnets:
  Private-A:
    CIDR: 10.0.10.0/24
    AZ: ap-northeast-2a
    용도: EKS Worker Nodes
    
  Private-B:
    CIDR: 10.0.20.0/24
    AZ: ap-northeast-2c
    용도: EKS Worker Nodes
```

### 라우팅 테이블 설계

#### Public Route Table
```yaml
대상: 0.0.0.0/0
게이트웨이: Internet Gateway

연결된 서브넷:
- Public Subnet A
- Public Subnet B
```

#### Private Route Tables
```yaml
Private Route Table A:
  대상: 0.0.0.0/0
  게이트웨이: NAT Gateway A
  연결 서브넷: Private Subnet A

Private Route Table B:
  대상: 0.0.0.0/0
  게이트웨이: NAT Gateway B
  연결 서브넷: Private Subnet B
```

---

## 🔒 보안 그룹 설계

### EKS 클러스터 보안 그룹

#### Control Plane Security Group
```yaml
이름: openwebui-eks-control-plane-sg
설명: EKS Control Plane 보안 그룹

Inbound Rules:
  - Type: HTTPS
    Port: 443
    Source: Worker Node Security Group
    설명: Worker 노드에서 API 서버 접근

Outbound Rules:
  - Type: All Traffic
    Port: All
    Destination: 0.0.0.0/0
    설명: 모든 아웃바운드 트래픽 허용
```

#### Worker Node Security Group
```yaml
이름: openwebui-eks-worker-sg
설명: EKS Worker Node 보안 그룹

Inbound Rules:
  - Type: All Traffic
    Port: All
    Source: Same Security Group
    설명: 워커 노드간 통신
    
  - Type: Custom TCP
    Port: 1025-65535
    Source: Control Plane Security Group
    설명: Control Plane에서 kubelet 통신
    
  - Type: HTTP
    Port: 80
    Source: ALB Security Group
    설명: 로드밸런서에서 애플리케이션 접근
    
  - Type: Custom TCP
    Port: 30000-32767
    Source: ALB Security Group
    설명: NodePort 서비스 접근

Outbound Rules:
  - Type: All Traffic
    Port: All
    Destination: 0.0.0.0/0
    설명: 모든 아웃바운드 트래픽 허용
```

#### Application Load Balancer Security Group
```yaml
이름: openwebui-alb-sg
설명: ALB 보안 그룹

Inbound Rules:
  - Type: HTTP
    Port: 80
    Source: 0.0.0.0/0
    설명: 인터넷에서 HTTP 접근
    
  - Type: HTTPS
    Port: 443
    Source: 0.0.0.0/0
    설명: 인터넷에서 HTTPS 접근

Outbound Rules:
  - Type: Custom TCP
    Port: 80
    Destination: Worker Node Security Group
    설명: 워커 노드로 트래픽 전달
    
  - Type: Custom TCP
    Port: 30000-32767
    Destination: Worker Node Security Group
    설명: NodePort 서비스 접근
```

---

## ⚙️ EKS 클러스터 설계

### 클러스터 기본 설정

```yaml
클러스터 설정:
  이름: openwebui-eks-dev
  버전: 1.28
  엔드포인트 액세스:
    Public: true
    Private: true
  로깅:
    - api
    - audit
    - authenticator
    - controllerManager
    - scheduler
```

### Node Group 설계

#### Primary Node Group
```yaml
이름: openwebui-primary-nodes
인스턴스 타입: t3.medium
스케일링:
  최소: 2
  최대: 4
  원하는 용량: 2
  
디스크:
  크기: 20GB
  타입: gp3
  
레이블:
  environment: dev
  nodegroup: primary
  
Taints: 없음
```

#### Spot Instance Node Group (비용 절약용)
```yaml
이름: openwebui-spot-nodes
인스턴스 타입: 
  - t3.medium
  - t3.large
  - m5.large
구매 옵션: Spot Instance
스케일링:
  최소: 0
  최대: 3
  원하는 용량: 1
  
레이블:
  environment: dev
  nodegroup: spot
  
Taints:
  - Key: spot
    Value: "true"
    Effect: NoSchedule
```

### Add-ons 설정

```yaml
필수 Add-ons:
  - vpc-cni (네트워킹)
  - coredns (DNS)
  - kube-proxy (네트워크 프록시)
  
추가 Add-ons:
  - aws-load-balancer-controller
  - ebs-csi-driver
  - cluster-autoscaler
```

---

## 🏷️ 리소스 명명 규칙

### 명명 규칙 표준

```yaml
형식: {project}-{resource-type}-{environment}-{optional-suffix}

예시:
  VPC: openwebui-vpc-dev
  Subnet: openwebui-public-subnet-dev-a
  Security Group: openwebui-eks-sg-dev
  EKS Cluster: openwebui-eks-dev
  Node Group: openwebui-primary-nodes-dev
  Load Balancer: openwebui-alb-dev
```

### 태그 전략

```yaml
모든 리소스 공통 태그:
  Project: openwebui
  Environment: dev
  Owner: team-name
  ManagedBy: terraform
  
리소스별 추가 태그:
  EKS Cluster:
    kubernetes.io/cluster/openwebui-eks-dev: owned
  
  Subnet:
    kubernetes.io/role/elb: 1 (public subnet)
    kubernetes.io/role/internal-elb: 1 (private subnet)
```

---

## 💰 비용 계산 및 최적화

### 예상 월 비용 (서울 리전 기준)

#### 기본 구성
| 서비스 | 스펙 | 월 예상 비용 | 설명 |
|--------|------|-------------|------|
| **EKS Control Plane** | 관리형 서비스 | $72 | 클러스터당 고정 비용 |
| **EC2 인스턴스** | 2x t3.medium | $60 | 워커 노드 (on-demand) |
| **EBS 볼륨** | 40GB gp3 | $4 | 워커 노드 스토리지 |
| **NAT Gateway** | 2개 AZ | $64 | 각 AZ당 $32 |
| **Load Balancer** | ALB | $22 | 기본 요금 + 트래픽 |
| **데이터 전송** | 예상 10GB | $1 | 아웃바운드 트래픽 |
| **기타 서비스** | ECR, CloudWatch | $5 | 로그, 이미지 저장 |

**총 예상 비용: 월 $228**

#### 비용 최적화 구성
| 서비스 | 최적화 방법 | 절약 비용 | 비고 |
|--------|-------------|----------|------|
| **EC2 인스턴스** | Spot Instance 사용 | -$42 | 70% 할인 |
| **NAT Gateway** | 단일 AZ 사용 | -$32 | 고가용성 일부 포기 |
| **EBS 볼륨** | gp2 → gp3 전환 | -$1 | 이미 적용됨 |

**최적화된 비용: 월 $153**

### 비용 알림 설정

#### CloudWatch 예산 설정
```yaml
예산 이름: openwebui-monthly-budget
예산 금액: $200
알림 설정:
  - 80% 도달 시 이메일 알림
  - 100% 도달 시 이메일 + SMS 알림
  - 120% 예상 시 긴급 알림
```

#### 비용 태그 전략
```yaml
비용 추적 태그:
  CostCenter: openwebui-project
  Department: engineering
  Team: devops
  Environment: dev
```

---

## 🔄 백업 및 재해 복구 계획

### 백업 전략

#### Terraform State 백업
```yaml
S3 버킷 설정:
  이름: openwebui-terraform-state-{random-suffix}
  버전 관리: 활성화
  암호화: AES-256
  생명주기 정책:
    - 90일 후 IA로 전환
    - 365일 후 Glacier로 전환
    
DynamoDB 락 테이블:
  이름: terraform-lock
  Primary Key: LockID
```

#### 애플리케이션 데이터 백업
```yaml
EBS 스냅샷:
  자동 스냅샷: 매일 오전 3시
  보존 기간: 7일
  
데이터베이스 백업:
  RDS 자동 백업: 활성화 (향후 사용 시)
  백업 보존: 7일
```

### 재해 복구 계획

#### RTO/RPO 목표
```yaml
RTO (Recovery Time Objective): 4시간
RPO (Recovery Point Objective): 1시간

복구 시나리오:
  1. 단일 AZ 장애: 자동 복구 (10분)
  2. 전체 클러스터 장애: 수동 복구 (2시간)
  3. 리전 장애: 타 리전 복구 (4시간)
```

#### 복구 절차
```yaml
1단계: 상황 평가
  - 장애 범위 확인
  - 영향도 평가
  - 복구 전략 결정

2단계: 긴급 조치
  - 트래픽 우회
  - 알림 발송
  - 로그 수집

3단계: 복구 실행
  - Terraform으로 인프라 재생성
  - 애플리케이션 배포
  - 데이터 복구

4단계: 검증
  - 기능 테스트
  - 성능 확인
  - 모니터링 복구
```

---

## 🔍 보안 설계

### IAM 권한 설계

#### EKS Service Role
```yaml
역할 이름: openwebui-eks-service-role
정책:
  - AmazonEKSClusterPolicy
  
신뢰 관계:
  - eks.amazonaws.com
```

#### Node Group Instance Role
```yaml
역할 이름: openwebui-eks-nodegroup-role
정책:
  - AmazonEKSWorkerNodePolicy
  - AmazonEKS_CNI_Policy
  - AmazonEC2ContainerRegistryReadOnly
  
신뢰 관계:
  - ec2.amazonaws.com
```

#### 최소 권한 원칙
```yaml
개발자 권한:
  - EKS 클러스터 읽기 전용
  - ECR 푸시/풀
  - CloudWatch 로그 읽기
  
운영자 권한:
  - EKS 클러스터 전체 관리
  - EC2 인스턴스 관리
  - 모니터링 도구 접근
```

### 네트워크 보안

#### 네트워크 ACL
```yaml
Public Subnet ACL:
  Inbound:
    - HTTP/HTTPS (80, 443) from 0.0.0.0/0
    - SSH (22) from 관리자 IP
  Outbound:
    - All traffic to 0.0.0.0/0

Private Subnet ACL:
  Inbound:
    - All traffic from VPC CIDR
  Outbound:
    - All traffic to 0.0.0.0/0
```

#### VPC Flow Logs
```yaml
설정:
  대상: CloudWatch Logs
  트래픽 타입: ALL
  집계 간격: 1분
  
로그 그룹: /aws/vpc/flowlogs
보존 기간: 30일
```

---

## 📊 모니터링 및 로깅 설계

### CloudWatch 설정

#### 메트릭 수집
```yaml
EKS 메트릭:
  - 클러스터 상태
  - 노드 리소스 사용률
  - 파드 상태

EC2 메트릭:
  - CPU, 메모리, 네트워크
  - 디스크 사용률
  - 시스템 로드
```

#### 로그 수집
```yaml
로그 그룹:
  - /aws/eks/openwebui-eks-dev/cluster
  - /aws/ec2/openwebui
  - /aws/application/openwebui
  
보존 기간: 30일
```

### 알림 설정

#### CloudWatch 알람
```yaml
CPU 사용률:
  임계값: 80%
  평가 기간: 5분
  알림: SNS Topic

메모리 사용률:
  임계값: 85%
  평가 기간: 5분
  알림: SNS Topic

파드 실패:
  임계값: 1개 이상
  평가 기간: 1분
  알림: SNS Topic + Slack
```

---

## ✅ 설계 검증 체크리스트

### 네트워크 설계 검증
- [ ] VPC CIDR가 다른 VPC와 겹치지 않는가?
- [ ] 서브넷이 적절히 분할되어 있는가?
- [ ] NAT Gateway가 각 AZ에 배치되어 있는가?
- [ ] 라우팅 테이블이 올바르게 설정되어 있는가?

### 보안 설계 검증
- [ ] 보안 그룹이 최소 권한으로 설정되어 있는가?
- [ ] IAM 역할이 적절히 분리되어 있는가?
- [ ] 프라이빗 서브넷의 인스턴스가 인터넷에 직접 노출되지 않는가?
- [ ] 로그와 모니터링이 설정되어 있는가?

### 고가용성 검증
- [ ] 리소스가 다중 AZ에 분산되어 있는가?
- [ ] 자동 스케일링이 설정되어 있는가?
- [ ] 백업 전략이 수립되어 있는가?
- [ ] 장애 복구 절차가 문서화되어 있는가?

### 비용 최적화 검증
- [ ] 불필요한 리소스가 제거되어 있는가?
- [ ] Spot 인스턴스 사용을 고려했는가?
- [ ] 비용 알림이 설정되어 있는가?
- [ ] 리소스 태그가 적절히 설정되어 있는가?

---

## 🚨 주의사항 및 제한사항

### 개발 환경 제한사항
```yaml
인스턴스 제한:
  - 최대 10개 EC2 인스턴스
  - 프리티어 혜택 활용
  
네트워크 제한:
  - 단일 리전 사용
  - 최소한의 NAT Gateway
  
스토리지 제한:
  - 기본 EBS 볼륨만 사용
  - 백업 보존 기간 단축
```

### 운영 환경 고려사항
```yaml
확장성:
  - Auto Scaling 그룹 설정
  - 로드 밸런서 확장 준비
  
보안:
  - WAF 설정 고려
  - VPN 연결 고려
  
모니터링:
  - 상세 메트릭 수집
  - 알림 채널 확장
```

---

## 📚 참고 자료

- [AWS VPC 설계 모범 사례](https://docs.aws.amazon.com/vpc/latest/userguide/VPC_Scenario2.html)
- [Amazon EKS 보안 그룹](https://docs.aws.amazon.com/eks/latest/userguide/sec-group-reqs.html)
- [EKS 네트워킹](https://docs.aws.amazon.com/eks/latest/userguide/network_reqs.html)
- [AWS 비용 최적화](https://aws.amazon.com/aws-cost-management/)

---

## ⏭️ 다음 단계

환경 설계가 완료되었다면 다음 문서로 진행하세요:
- **[03-terraform-configuration.md]** - Terraform으로 인프라 구현
- **[04-eks-deployment.md]** - EKS 클러스터 배포
- **[05-application-deployment.md]** - 애플리케이션 배포

---

> **💡 팁**: 이 설계 문서는 실제 구현 전에 팀원들과 검토하고 승인받으세요. 한 번 배포된 후에는 변경이 어려운 부분들이 있습니다!
