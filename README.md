# TccMicroservices

Prova de Conceito (PoC) para benchmarking de padrões de comunicação em Microservices .NET 8: **REST (HTTP/1.1)**, **gRPC (HTTP/2)** e **RabbitMQ (Mensageria Assíncrona)**.

---

## Pré-requisitos

- [Docker Desktop](https://docs.docker.com/get-docker/) (inclui Docker Compose)
- [PowerShell 5.1+](https://docs.microsoft.com/pt-br/powershell/) (já incluso no Windows 10/11)
- (Opcional) [.NET 8 SDK](https://dotnet.microsoft.com/download/dotnet/8.0) — apenas para desenvolvimento local sem Docker

---

## Estrutura do Projeto

```
TccMicroservices/
├── src/
│   ├── Tcc.Shared/                       # DTOs e definições Protobuf (.proto)
│   │   ├── Dtos/
│   │   │   └── OrderRequest.cs
│   │   ├── Protos/
│   │   │   └── order.proto
│   │   └── Tcc.Shared.csproj
│   ├── Tcc.ProcessingService/            # Serviço backend (REST + gRPC + Consumer RabbitMQ)
│   │   ├── Services/
│   │   │   ├── GrpcOrderService.cs
│   │   │   └── RabbitMqConsumerService.cs
│   │   ├── Dockerfile
│   │   ├── Program.cs
│   │   └── Tcc.ProcessingService.csproj
│   └── Tcc.ApiGateway/                   # API Gateway com BenchmarkController
│       ├── Controllers/
│       │   └── BenchmarkController.cs
│       ├── Services/
│       │   └── RabbitMqProducer.cs       # Singleton producer (connection + channel reuse)
│       ├── Dockerfile
│       ├── Program.cs
│       └── Tcc.ApiGateway.csproj
├── docker-compose.yml                    # Infraestrutura (RabbitMQ, Jaeger, serviços, JMeter)
├── tcc_benchmark.jmx                     # Plano de testes JMeter
├── run_benchmark.ps1                     # Script de automação (Windows / PowerShell)
├── run_benchmark.sh                      # Script de automação (Linux / macOS / Bash)
├── TccMicroservices.sln
├── .gitignore
└── README.md
```

---

## Quick Start — Rodar tudo em um comando

**Windows (PowerShell):**

```powershell
.\run_benchmark.ps1
```

**Linux / macOS (Bash):**

```bash
chmod +x run_benchmark.sh   # apenas na primeira vez
./run_benchmark.sh
```

Isso executa automaticamente:

1. Limpa resultados anteriores
2. Builda e sobe os containers (RabbitMQ, Jaeger, ProcessingService, ApiGateway)
3. Aguarda todos os serviços ficarem prontos (health check via HTTP)
4. Executa o JMeter com 50 threads por 60s em cada padrão (REST, gRPC, RabbitMQ)
5. Abre o relatório HTML no navegador

---

## Passo a Passo Detalhado

### 1. Clonar e acessar o projeto

```powershell
cd C:\caminho\para\TccMicroservices
```

### 2. Subir a infraestrutura

```powershell
docker-compose up --build -d
```

Aguarde todos os containers ficarem healthy:

```powershell
docker-compose ps
```

| Container                  | Porta(s)                          | Função                              |
|----------------------------|-----------------------------------|-------------------------------------|
| **tcc-rabbitmq**           | `5672` (AMQP), `15672` (UI)       | Message Broker                      |
| **tcc-jaeger**             | `16686` (UI), `4317`/`4318` (OTLP)| Distributed Tracing (Jaeger)        |
| **tcc-processing-service** | `8080` (REST), `50051` (gRPC)     | Serviço backend que processa ordens |
| **tcc-api-gateway**        | `5000` (HTTP)                     | API Gateway / Entrypoint            |

### 3. Verificar se os serviços estão rodando

- **Swagger UI:** http://localhost:5000/swagger
- **RabbitMQ Management:** http://localhost:15672 (usuário: `guest`, senha: `guest`)
- **Jaeger UI:** http://localhost:16686

### 4. Testar os endpoints manualmente

```powershell
# REST (Síncrono - HTTP/1.1 JSON) → espera 200 OK
curl -X POST http://localhost:5000/api/benchmark/rest

# gRPC (Síncrono - HTTP/2 Protobuf) → espera 200 OK
curl -X POST http://localhost:5000/api/benchmark/grpc

# RabbitMQ (Assíncrono - Fire-and-Forget) → espera 202 Accepted
curl -X POST http://localhost:5000/api/benchmark/rabbitmq
```

### 5. Rodar o benchmark

#### Opção A — Script automatizado (recomendado)

**Windows (PowerShell):**

```powershell
# Execução padrão (50 threads, 10s ramp-up, 60s por grupo)
.\run_benchmark.ps1

# Customizando a carga
.\run_benchmark.ps1 -Threads 100 -RampUp 15 -Duration 120
```

**Linux / macOS (Bash):**

```bash
# Dar permissão de execução (apenas na primeira vez)
chmod +x run_benchmark.sh

# Execução padrão
./run_benchmark.sh

# Customizando a carga (argumentos posicionais: threads rampup duration)
./run_benchmark.sh 100 15 120
```

| Parâmetro        | Default | Descrição                              |
|------------------|---------|----------------------------------------|
| Threads (1o arg) | 50      | Número de usuários virtuais simultâneos |
| RampUp (2o arg)  | 10      | Tempo (s) para subir todas as threads   |
| Duration (3o arg)| 60      | Duração (s) de cada grupo de teste      |

O tempo total do benchmark é aproximadamente `Duration x 3` (REST + gRPC + RabbitMQ executados sequencialmente).

#### Opção B — Execução manual passo a passo

```powershell
# 1. Limpar resultados anteriores (obrigatório — JMeter falha se a pasta não estiver vazia)
Remove-Item results -Recurse -Force -ErrorAction SilentlyContinue
mkdir results

# 2. Subir a infraestrutura (se ainda não estiver rodando)
docker-compose up --build -d

# 3. Executar o JMeter via Docker
docker-compose --profile benchmark run --rm jmeter

# 4. Abrir o relatório
Start-Process results\html_report\index.html
```

#### Opção C — JMeter instalado localmente

```bash
# CLI mode (gera relatório HTML automaticamente)
jmeter -n -t tcc_benchmark.jmx -l results/raw_results.jtl -e -o results/html_report

# GUI mode (para depuração do plano de testes)
jmeter -t tcc_benchmark.jmx
```

### 6. Analisar os resultados

Após a execução, a pasta `results/` contém:

```
results/
├── raw_results.jtl          # Dados brutos de cada request (CSV)
└── html_report/
    └── index.html           # Dashboard com gráficos de latência e throughput
```

O relatório HTML inclui:
- **Summary** — Avg/Min/Max/P90/P95/P99 por endpoint
- **Response Times Over Time** — Gráfico de latência ao longo do teste
- **Transactions Per Second** — Throughput comparativo
- **Response Times vs Threads** — Comportamento sob carga crescente

---

## Distributed Tracing (Jaeger)

Ambos os serviços exportam traces via OpenTelemetry (OTLP/gRPC) para o Jaeger, que sobe automaticamente com o `docker-compose up`.

### Visualizar traces

1. Acesse o Jaeger UI: http://localhost:16686
2. No dropdown **Service**, selecione `Tcc.ApiGateway` ou `Tcc.ProcessingService`
3. Clique em **Find Traces**

### O que você verá

- **REST:** `Tcc.ApiGateway` → HTTP POST → `Tcc.ProcessingService` (dois spans correlacionados)
- **gRPC:** `Tcc.ApiGateway` → gRPC SubmitOrder → `Tcc.ProcessingService` (dois spans correlacionados)
- **RabbitMQ:** Apenas o span do `Tcc.ApiGateway` (publish é fire-and-forget, sem propagação automática de contexto)

Cada trace mostra a latência end-to-end decomposta por serviço — ideal para os gráficos da tese.

---

## Stack Tecnológica

| Tecnologia               | Versão  | Uso                                    |
|--------------------------|---------|----------------------------------------|
| .NET                     | 8.0     | Runtime / SDK                          |
| Grpc.AspNetCore          | 2.59.0  | Servidor gRPC (ProcessingService)      |
| Grpc.Net.Client          | 2.59.0  | Cliente gRPC (ApiGateway)              |
| RabbitMQ.Client          | 6.8.1   | Cliente AMQP                           |
| OpenTelemetry            | 1.9.0   | Distributed Tracing (OTLP exporter)   |
| Swashbuckle.AspNetCore   | 6.5.0   | Swagger UI                             |
| RabbitMQ                 | 3.x     | Message Broker (Docker)                |
| Jaeger                   | latest  | Tracing backend (Docker)               |
| JMeter                   | 5.5     | Ferramenta de benchmark (Docker)       |

---

## Parar os containers

```powershell
# Parar e remover containers
docker-compose down

# Parar, remover containers e limpar volumes
docker-compose down -v
```

---

## Arquitetura

```
┌──────────────┐     REST (HTTP/1.1)      ┌────────────────────┐
│              │ ──────────────────────── │                    │
│  ApiGateway  │     gRPC (HTTP/2)        │ ProcessingService  │
│  :5000       │ ──────────────────────── │  :8080 / :50051    │
│              │                          │                    │
│              │     RabbitMQ (AMQP)       │                    │
│              │ ──── orders-queue ──────│                    │
└──────────────┘                          └────────────────────┘
        │                                         │
        │            ┌────────────┐               │
        │            │  RabbitMQ  │ ◄─────────────┘
        │            │  :5672     │   (Consumer BackgroundService)
        │            └────────────┘
        │
        ├──── OTLP/gRPC ────┐
        │                    ▼
        │            ┌────────────┐
        └──────────► │   Jaeger   │
                     │  :16686    │
                     └────────────┘
```
