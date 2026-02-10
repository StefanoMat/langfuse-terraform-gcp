# Tutorial: Deploy Langfuse no GCP via GitHub Actions

> Guia passo a passo para reproduzir o deploy completo do zero.
> Projeto: langfuse-terraform-gcp (fork: StefanoMat/langfuse-terraform-gcp)

---

## Pre-requisitos

- Conta GCP com billing ativo
- `gcloud` CLI instalado e autenticado (`gcloud auth login`)
- `terraform` CLI instalado (v1.7+)
- Conta GitHub com fork do repo

---

## Parte 1: Habilitar APIs no GCP

Projeto: `langfuse-prd-487000`

Via Console: https://console.cloud.google.com/apis/library?project=langfuse-prd-487000

Ou via CLI:

```bash
gcloud services enable \
  certificatemanager.googleapis.com \
  dns.googleapis.com \
  compute.googleapis.com \
  container.googleapis.com \
  redis.googleapis.com \
  networkconnectivity.googleapis.com \
  servicenetworking.googleapis.com \
  iamcredentials.googleapis.com \
  sqladmin.googleapis.com \
  --project=langfuse-prd-487000
```

APIs necessarias:
- Certificate Manager API
- Cloud DNS API
- Compute Engine API
- Container (Kubernetes Engine) API
- Google Cloud Memorystore for Redis API
- Network Connectivity API
- Service Networking API
- IAM Service Account Credentials API
- Cloud SQL Admin API

---

## Parte 2: Bootstrap (Workload Identity Federation)

O bootstrap cria: bucket GCS para state, Service Account, WIF Pool e Provider.

```bash
cd bootstrap
terraform init
terraform apply \
  -var="project_id=langfuse-prd-487000" \
  -var="github_repo=StefanoMat/langfuse-terraform-gcp"
```

### Outputs esperados

```
terraform_state_bucket = "langfuse-prd-487000-terraform-state"
wif_provider           = "projects/326217082609/locations/global/workloadIdentityPools/github-pool/providers/github-provider"
wif_service_account    = "github-actions-terraform@langfuse-prd-487000.iam.gserviceaccount.com"
```

> Anote esses valores! Serao usados no passo seguinte.

---

## Parte 3: Permissoes do Service Account

O role `Editor` nao e suficiente. Adicione esses roles ao Service Account:

```bash
SA="serviceAccount:github-actions-terraform@langfuse-prd-487000.iam.gserviceaccount.com"
PROJECT="langfuse-prd-487000"

gcloud projects add-iam-policy-binding $PROJECT --member=$SA --role="roles/editor"
gcloud projects add-iam-policy-binding $PROJECT --member=$SA --role="roles/servicenetworking.networksAdmin"
gcloud projects add-iam-policy-binding $PROJECT --member=$SA --role="roles/compute.networkAdmin"
gcloud projects add-iam-policy-binding $PROJECT --member=$SA --role="roles/iam.serviceAccountAdmin"
```

Se aparecerem mais erros de permissao durante o apply, adicione o role correspondente.

Lista completa de roles que podem ser necessarios:
- `roles/editor` (base)
- `roles/servicenetworking.networksAdmin` (VPC peering)
- `roles/compute.networkAdmin` (firewall, VPC)
- `roles/iam.serviceAccountAdmin` (criar/configurar SAs)
- `roles/container.admin` (GKE - se necessario)
- `roles/dns.admin` (DNS - se necessario)

---

## Parte 4: Configurar GitHub Environment

1. Acesse: https://github.com/StefanoMat/langfuse-terraform-gcp/settings/environments
2. Crie o environment: `prd`
3. Adicione estas **Variables** (nao Secrets - nao sao sensiveis):

| Variable            | Valor                                                                                                    |
|---------------------|----------------------------------------------------------------------------------------------------------|
| `WIF_PROVIDER`      | `projects/326217082609/locations/global/workloadIdentityPools/github-pool/providers/github-provider`     |
| `WIF_SERVICE_ACCOUNT` | `github-actions-terraform@langfuse-prd-487000.iam.gserviceaccount.com`                                |
| `GCP_PROJECT`       | `langfuse-prd-487000`                                                                                    |

---

## Parte 5: Push e Deploy

### Primeira execucao (merge direto na main)

A primeira execucao precisa ir direto na main porque o plan falha sem o cluster GKE existindo (bug conhecido do provider kubernetes_manifest).

```bash
git add .
git commit -m "feat: add GitHub Actions CI/CD with WIF"
git push meu-fork main
```

O workflow vai:
1. Criar VPC, subnet, GKE cluster e DNS (target apply, ~15 min)
2. Rodar plan completo
3. Aplicar todo o resto (Postgres, Redis, Helm, etc.)

### Execucoes seguintes (via PR)

```bash
git checkout -b feature/minha-mudanca
# ... faz mudancas ...
git commit -m "feat: descricao"
git push meu-fork feature/minha-mudanca
# Abre PR no GitHub -> plan roda automaticamente e comenta no PR
# Merge na main -> apply roda automaticamente
```

---

## Parte 6: Configurar DNS

Apos o primeiro deploy, configure a delegacao de DNS no seu provedor.

```bash
gcloud dns managed-zones describe langfuse-kaeferdev-com \
  --format="get(nameServers)" \
  --project=langfuse-prd-487000
```

Adicione os nameservers retornados como registros NS no seu provedor de DNS (onde kaeferdev.com esta registrado).

---

## Parte 7: Verificar SSL

O certificado SSL demora ~20 min para provisionar:

```bash
gcloud compute ssl-certificates list --project=langfuse-prd-487000
```

Quando status mudar de `PROVISIONING` para `ACTIVE`, acesse https://langfuse.kaeferdev.com

---

## Troubleshooting

### State lock

Se o terraform travar o state:
```bash
cd kaeferdev
terraform init
terraform force-unlock <LOCK_ID>
```

### Erro "kubernetes_manifest: cannot create REST client"

Isso acontece no plan quando o cluster GKE nao existe ainda. E esperado na primeira execucao. O workflow lida com isso automaticamente ao fazer o apply em duas etapas.

### Erro de permissao (403)

Identifique o role necessario pelo erro e adicione:
```bash
gcloud projects add-iam-policy-binding langfuse-prd-487000 \
  --member="serviceAccount:github-actions-terraform@langfuse-prd-487000.iam.gserviceaccount.com" \
  --role="roles/ROLE_NECESSARIO"
```

### SSL ERR_SSL_VERSION_OR_CIPHER_MISMATCH

Aguarde ~20 min apos o deploy para o certificado ser provisionado.

---

## Estrutura de Arquivos

```
langfuse-terraform-gcp/
├── .github/workflows/terraform.yml  # Pipeline CI/CD
├── bootstrap/main.tf                # Setup WIF (rodar 1x)
├── kaeferdev/                       # Ambiente PRD
│   ├── quickstart.tf                # Configuracao Langfuse
│   └── backend.tf                   # State remoto (GCS)
├── *.tf                             # Modulo Terraform (raiz)
└── docs/
    ├── TUTORIAL.md                  # Este arquivo
    └── AI_AGENT_GUIDE.md            # Guia para agentes de IA
```

---

## Valores de Referencia (este deploy)

| Item                  | Valor                                            |
|-----------------------|--------------------------------------------------|
| GCP Project           | `langfuse-prd-487000`                            |
| GCP Project Number    | `326217082609`                                   |
| GitHub Repo           | `StefanoMat/langfuse-terraform-gcp`              |
| Branch                | `main`                                           |
| Dominio               | `langfuse.kaeferdev.com`                         |
| State Bucket          | `langfuse-prd-487000-terraform-state`            |
| Service Account       | `github-actions-terraform@langfuse-prd-487000.iam.gserviceaccount.com` |
| Terraform Version     | `1.7.0`                                          |
| Langfuse Chart Version| `1.5.14`                                         |
