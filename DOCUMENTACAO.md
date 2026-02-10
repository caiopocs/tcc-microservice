# Documentacao Completa — TccMicroservices

> Guia didatico sobre a arquitetura, tecnologias utilizadas, justificativas tecnicas e instrucoes de uso da Prova de Conceito (PoC) para benchmarking de padroes de comunicacao em Microservices .NET 8.

---

## Sumario

1. [O Que e Este Projeto?](#1-o-que-e-este-projeto)
2. [Arquitetura Geral](#2-arquitetura-geral)
3. [Os 3 Padroes de Comunicacao](#3-os-3-padroes-de-comunicacao)
   - 3.1 [REST (HTTP/1.1)](#31-rest-http11)
   - 3.2 [gRPC (HTTP/2)](#32-grpc-http2)
   - 3.3 [RabbitMQ (Mensageria Assincrona)](#33-rabbitmq-mensageria-assincrona)
4. [Estrutura do Projeto — Arquivo por Arquivo](#4-estrutura-do-projeto--arquivo-por-arquivo)
5. [Tecnologias Utilizadas e Justificativas](#5-tecnologias-utilizadas-e-justificativas)
6. [Como o Codigo Funciona (Fluxo Passo a Passo)](#6-como-o-codigo-funciona-fluxo-passo-a-passo)
7. [Infraestrutura com Docker](#7-infraestrutura-com-docker)
8. [Observabilidade — OpenTelemetry e Jaeger](#8-observabilidade--opentelemetry-e-jaeger)
9. [Benchmark com JMeter](#9-benchmark-com-jmeter)
10. [Como Utilizar](#10-como-utilizar)
11. [Glossario de Termos](#11-glossario-de-termos)

---

## 1. O Que e Este Projeto?

Este projeto e uma **Prova de Conceito (PoC)** desenvolvida para um Trabalho de Conclusao de Curso (TCC) que compara **tres padroes de comunicacao entre microservices**:

| Padrao    | Protocolo  | Tipo          | Analogia do dia a dia                        |
|-----------|------------|---------------|----------------------------------------------|
| REST      | HTTP/1.1   | Sincrono      | Telefonema — voce liga e espera a resposta   |
| gRPC      | HTTP/2     | Sincrono      | Walkie-talkie digital — mais rapido e compacto |
| RabbitMQ  | AMQP       | Assincrono    | Correio — voce envia e nao espera resposta   |

A ideia e medir **latencia**, **throughput** e **comportamento sob carga** de cada padrao, gerando dados quantitativos para a tese.

### Por que comparar esses tres?

- **REST** e o padrao mais utilizado na industria (APIs web, mobile, etc.)
- **gRPC** e o padrao de alta performance usado por Google, Netflix, etc.
- **RabbitMQ** representa a comunicacao assincrona via mensageria, muito usada em sistemas event-driven

Comparar os tres permite avaliar trade-offs reais entre **simplicidade** (REST), **performance** (gRPC) e **desacoplamento** (RabbitMQ).

---

## 2. Arquitetura Geral

```
                         ┌─────────────────────┐
                         │     JMeter           │
                         │  (Gerador de Carga)  │
                         └──────────┬───────────┘
                                    │ HTTP POST x N threads
                                    ▼
┌───────────────────────────────────────────────────────────┐
│                      API Gateway (:5000)                   │
│                                                           │
│  POST /api/benchmark/rest     → REST (HTTP/1.1 JSON)      │
│  POST /api/benchmark/grpc     → gRPC (HTTP/2 Protobuf)    │
│  POST /api/benchmark/rabbitmq → RabbitMQ (AMQP Publish)   │
└─────┬──────────────┬──────────────────┬───────────────────┘
      │              │                  │
      │ HTTP/1.1     │ HTTP/2           │ AMQP
      │ JSON         │ Protobuf         │ JSON
      ▼              ▼                  ▼
┌──────────────────────────────┐  ┌──────────┐
│   Processing Service         │  │ RabbitMQ │
│   :8080 (REST)               │  │  :5672   │
│   :50051 (gRPC)              │  └────┬─────┘
│                              │       │ Consumer
│   - Recebe via REST          │ ◄─────┘
│   - Recebe via gRPC          │
│   - Consome fila RabbitMQ    │
└──────────────┬───────────────┘
               │
               │ OTLP/gRPC (traces)
               ▼
        ┌─────────────┐
        │   Jaeger     │
        │   :16686     │
        └─────────────┘
```

### Explicacao do fluxo:

1. O **JMeter** simula N usuarios simultaneos fazendo requisicoes HTTP POST para o API Gateway
2. O **API Gateway** recebe a requisicao e a encaminha usando o padrao especificado (REST, gRPC ou RabbitMQ)
3. O **Processing Service** recebe e processa a "ordem" (simula um processamento com `Task.Delay(10ms)`)
4. O **Jaeger** coleta traces de ambos os servicos para visualizacao da latencia end-to-end

### Por que dois servicos separados?

Porque o objetivo e medir a **comunicacao entre servicos**. Se tudo estivesse em um unico processo, nao haveria comunicacao de rede para medir. Separando em:

- **API Gateway** = ponto de entrada (quem faz a chamada)
- **Processing Service** = backend (quem recebe e processa)

...conseguimos medir o custo real de cada protocolo de comunicacao.

---

## 3. Os 3 Padroes de Comunicacao

### 3.1 REST (HTTP/1.1)

```
API Gateway                    Processing Service
     │                              │
     │  POST /api/orders            │
     │  Content-Type: application/json
     │  {"Id":"abc","Customer":"x"} │
     │ ────────────────────────────►│
     │                              │ processa...
     │  200 OK                      │
     │  {"Success":true}            │
     │ ◄────────────────────────────│
     │                              │
```

**O que e:** REST (Representational State Transfer) usa HTTP/1.1 com payloads em JSON. E o padrao mais comum para APIs web.

**Como funciona no codigo:**

- O **API Gateway** serializa um `OrderRequest` em JSON e faz `POST /api/orders` via `HttpClient`
- O **Processing Service** recebe via Minimal API (`app.MapPost("/api/orders", ...)`)
- A resposta volta como JSON no corpo do HTTP 200

**Vantagens:**
- Universal — qualquer linguagem/plataforma suporta
- Facil de depurar (cURL, Postman, navegador)
- Ecosistema maduro (Swagger, OpenAPI)

**Desvantagens:**
- Overhead de texto (JSON e verboso, headers HTTP sao grandes)
- HTTP/1.1 usa uma conexao por request (sem multiplexing)
- Serializacao/deserializacao JSON e mais lenta que binario

### 3.2 gRPC (HTTP/2)

```
API Gateway                    Processing Service
     │                              │
     │  HTTP/2 HEADERS frame        │
     │  :method = POST              │
     │  :path = /orders.OrderProcessing/SubmitOrder
     │  content-type: application/grpc
     │                              │
     │  DATA frame (Protobuf binary)│
     │  [bytes compactos]           │
     │ ────────────────────────────►│
     │                              │ processa...
     │  HEADERS + DATA (Protobuf)   │
     │  [bytes compactos]           │
     │ ◄────────────────────────────│
     │                              │
```

**O que e:** gRPC (Google Remote Procedure Call) usa HTTP/2 com serializacao binaria via Protocol Buffers (Protobuf). E o padrao usado internamente pelo Google.

**Como funciona no codigo:**

- O contrato e definido em `order.proto` (linguagem neutra)
- O `Grpc.Tools` gera automaticamente as classes C# (`OrderProcessing.OrderProcessingClient` e `OrderProcessing.OrderProcessingBase`)
- O **API Gateway** usa o client gerado para chamar `SubmitOrderAsync()`
- O **Processing Service** implementa o server herdando `OrderProcessingBase`

**Arquivo `order.proto`:**
```protobuf
service OrderProcessing {
  rpc SubmitOrder (OrderRequestMessage) returns (OrderReplyMessage);
}

message OrderRequestMessage {
  string id = 1;
  string customer_id = 2;
  double value = 3;
}
```

**Vantagens:**
- Serializacao binaria (Protobuf) — 5-10x menor que JSON
- HTTP/2 — multiplexing de requests na mesma conexao TCP
- Contrato tipado — o `.proto` garante compatibilidade entre servicos
- Streaming bidirecional nativo

**Desvantagens:**
- Nao e legivel por humanos (binario)
- Requer ferramentas especificas (nao funciona com cURL comum)
- Exige HTTP/2, o que pode complicar proxies/load balancers

### 3.3 RabbitMQ (Mensageria Assincrona)

```
API Gateway                 RabbitMQ              Processing Service
     │                        │                         │
     │  BasicPublish           │                         │
     │  queue: orders-queue    │                         │
     │  body: JSON bytes       │                         │
     │ ──────────────────────► │                         │
     │                         │                         │
     │  (retorna 202 imediatamente — fire-and-forget)    │
     │                         │                         │
     │                         │  Deliver message        │
     │                         │ ──────────────────────► │
     │                         │                         │ processa...
     │                         │  BasicAck               │
     │                         │ ◄────────────────────── │
```

**O que e:** RabbitMQ e um message broker que implementa o protocolo AMQP. A comunicacao e **assincrona**: o remetente publica uma mensagem na fila e continua sem esperar resposta.

**Como funciona no codigo:**

- O **API Gateway** publica uma mensagem JSON na fila `orders-queue` via `BasicPublish`
- Retorna **202 Accepted** imediatamente (nao espera o processamento)
- O **Processing Service** roda um `BackgroundService` (`RabbitMqConsumerService`) que:
  - Conecta ao RabbitMQ com retry automatico
  - Consome mensagens da fila com `EventingBasicConsumer`
  - Processa cada mensagem e envia `BasicAck` (confirmacao manual)

**Vantagens:**
- Desacoplamento total — produtor e consumidor nao precisam estar online ao mesmo tempo
- O broker garante entrega (persistencia, retry, dead-letter queues)
- Ideal para picos de carga — a fila absorve o excesso

**Desvantagens:**
- Nao e sincrono — o cliente nao recebe o resultado do processamento
- Adiciona um componente extra de infraestrutura (o broker)
- Complexidade operacional (monitoramento de filas, mensagens stuck, etc.)

### Tabela Comparativa

| Caracteristica         | REST            | gRPC               | RabbitMQ           |
|------------------------|-----------------|---------------------|--------------------|
| **Protocolo**          | HTTP/1.1        | HTTP/2              | AMQP               |
| **Formato dos dados**  | JSON (texto)    | Protobuf (binario)  | JSON (texto)       |
| **Tipo de comunicacao**| Sincrono        | Sincrono            | Assincrono         |
| **Resposta ao cliente**| Resultado real  | Resultado real      | Apenas confirmacao |
| **Latencia esperada**  | Media           | Baixa               | Muito baixa*       |
| **Throughput esperado**| Medio           | Alto                | Muito alto*        |
| **Complexidade**       | Baixa           | Media               | Media-Alta         |

> *A latencia e throughput do RabbitMQ sao medidos do ponto de vista do **produtor** (fire-and-forget). O processamento real acontece depois.

---

## 4. Estrutura do Projeto — Arquivo por Arquivo

```
TccMicroservices/
├── src/
│   ├── Tcc.Shared/                          # Biblioteca compartilhada
│   │   ├── Dtos/
│   │   │   └── OrderRequest.cs              # Record com Id, CustomerId, Value
│   │   ├── Protos/
│   │   │   └── order.proto                  # Contrato gRPC (Protobuf)
│   │   └── Tcc.Shared.csproj               # Gera classes C# a partir do .proto
│   │
│   ├── Tcc.ProcessingService/               # Servico backend
│   │   ├── Services/
│   │   │   ├── GrpcOrderService.cs          # Implementacao do server gRPC
│   │   │   └── RabbitMqConsumerService.cs   # Consumer da fila (BackgroundService)
│   │   ├── Program.cs                       # Configura Kestrel (8080 + 50051), REST endpoint
│   │   ├── Dockerfile                       # Build multi-stage .NET 8
│   │   └── Tcc.ProcessingService.csproj
│   │
│   └── Tcc.ApiGateway/                      # API Gateway (ponto de entrada)
│       ├── Controllers/
│       │   └── BenchmarkController.cs       # 3 endpoints: /rest, /grpc, /rabbitmq
│       ├── Program.cs                       # Configura DI, Swagger, OpenTelemetry
│       ├── Dockerfile                       # Build multi-stage .NET 8
│       └── Tcc.ApiGateway.csproj
│
├── docker-compose.yml                       # Orquestra todos os containers
├── tcc_benchmark.jmx                        # Plano de testes do JMeter
├── run_benchmark.ps1                        # Automacao Windows (PowerShell)
├── run_benchmark.sh                         # Automacao Linux/macOS (Bash)
├── TccMicroservices.sln                     # Solution .NET
├── .gitignore
└── README.md
```

### O que cada arquivo faz:

| Arquivo | Responsabilidade |
|---------|-----------------|
| `OrderRequest.cs` | Define o DTO (Data Transfer Object) como um `record` imutavel: `OrderRequest(Guid Id, string CustomerId, decimal Value)` |
| `order.proto` | Define o contrato gRPC em linguagem neutra. O build do .NET gera automaticamente as classes `OrderProcessingClient` e `OrderProcessingBase` |
| `GrpcOrderService.cs` | Implementa o server gRPC. Herda de `OrderProcessingBase` (classe gerada) e implementa o metodo `SubmitOrder` |
| `RabbitMqConsumerService.cs` | Background service que roda continuamente consumindo mensagens da fila `orders-queue`. Usa retry loop para conexao e `BasicAck` manual |
| `ProcessingService/Program.cs` | Configura o Kestrel com duas portas (8080 para REST, 50051 para gRPC), registra o gRPC e o consumer RabbitMQ, configura OpenTelemetry |
| `BenchmarkController.cs` | Controller com 3 actions: `POST /rest` (HttpClient), `POST /grpc` (gRPC client), `POST /rabbitmq` (BasicPublish) |
| `ApiGateway/Program.cs` | Configura Swagger, HttpClient factory, gRPC client singleton, conexao RabbitMQ singleton, OpenTelemetry |
| `docker-compose.yml` | Define e orquestra 5 servicos: RabbitMQ, Jaeger, ProcessingService, ApiGateway, JMeter |
| `tcc_benchmark.jmx` | Plano JMeter com 3 Thread Groups sequenciais (REST, gRPC, RabbitMQ), cada um com N threads por D segundos |
| `run_benchmark.ps1` / `.sh` | Scripts que automatizam: limpeza, build, health check, execucao do JMeter, abertura do relatorio |

---

## 5. Tecnologias Utilizadas e Justificativas

### 5.1 .NET 8

| | |
|---|---|
| **O que e** | Framework multiplataforma da Microsoft para desenvolvimento de aplicacoes web, APIs e microservices |
| **Versao** | .NET 8 (LTS — Long Term Support) |
| **Por que foi usado** | Runtime de alto desempenho com suporte nativo a gRPC, Minimal APIs, e Kestrel (servidor HTTP ultra-rapido). Ideal para benchmarks por ser uma das plataformas mais performaticas |

**Recursos do C# 12 utilizados:**
- `record` — tipo imutavel para DTOs (ex: `OrderRequest`)
- Primary Constructors — construtor direto na declaracao da classe (ex: `public class GrpcOrderService(ILogger<...> logger)`)
- File-scoped namespaces — `namespace X;` ao inves de `namespace X { ... }`

### 5.2 Kestrel (Servidor HTTP)

| | |
|---|---|
| **O que e** | Servidor web embutido no .NET, usado como servidor HTTP de producao |
| **Por que foi usado** | Permite configurar **multiplas portas com protocolos diferentes** no mesmo processo |

```csharp
builder.WebHost.ConfigureKestrel(options =>
{
    options.ListenAnyIP(8080, o => o.Protocols = HttpProtocols.Http1AndHttp2); // REST
    options.ListenAnyIP(50051, o => o.Protocols = HttpProtocols.Http2);        // gRPC
});
```

Isso permite que o ProcessingService atenda **REST na porta 8080** e **gRPC na porta 50051** simultaneamente.

### 5.3 gRPC + Protocol Buffers

| | |
|---|---|
| **O que e** | Framework RPC de alto desempenho do Google, com serializacao binaria via Protobuf |
| **Pacotes NuGet** | `Grpc.AspNetCore` (server), `Grpc.Net.Client` (client), `Google.Protobuf`, `Grpc.Tools` (code-gen) |
| **Por que foi usado** | Representa o padrao de comunicacao sincrona de **alta performance** — comparacao direta com REST |

**Fluxo de code generation:**
```
order.proto  ──[Grpc.Tools]──►  Order.cs + OrderGrpc.cs (classes C# geradas automaticamente no build)
```

### 5.4 RabbitMQ

| | |
|---|---|
| **O que e** | Message broker open-source que implementa AMQP (Advanced Message Queuing Protocol) |
| **Imagem Docker** | `rabbitmq:3-management` (inclui painel web na porta 15672) |
| **Pacote NuGet** | `RabbitMQ.Client 6.8.1` |
| **Por que foi usado** | Padrao mais popular de mensageria. Representa a comunicacao **assincrona**, onde produtor e consumidor sao desacoplados |

**Conceitos-chave:**
- **Queue (`orders-queue`)** — fila onde as mensagens ficam ate serem consumidas
- **BasicPublish** — envia mensagem para a fila
- **EventingBasicConsumer** — recebe mensagens via callback
- **BasicAck** — confirma manualmente que a mensagem foi processada (evita perda)

### 5.5 Docker e Docker Compose

| | |
|---|---|
| **O que e** | Plataforma de containerizacao que empacota aplicacoes com todas as suas dependencias |
| **Por que foi usado** | Garante que o ambiente e **identico** em qualquer maquina. Um comando (`docker-compose up`) sobe toda a infraestrutura |

**Dockerfile (multi-stage build):**
```dockerfile
# Estagio 1: Build — usa SDK completo (pesado, ~700MB)
FROM mcr.microsoft.com/dotnet/sdk:8.0 AS build
WORKDIR /src
COPY ... .
RUN dotnet publish -c Release -o /app/publish

# Estagio 2: Runtime — usa imagem minima (leve, ~100MB)
FROM mcr.microsoft.com/dotnet/aspnet:8.0
COPY --from=build /app/publish .
ENTRYPOINT ["dotnet", "Tcc.ProcessingService.dll"]
```

A imagem final contem **apenas** o runtime + binarios publicados, sem SDK, fontes ou pacotes NuGet.

### 5.6 OpenTelemetry

| | |
|---|---|
| **O que e** | Padrao aberto e vendor-neutral para coleta de telemetria (traces, metricas, logs) |
| **Pacotes NuGet** | `OpenTelemetry.Extensions.Hosting`, `.Instrumentation.AspNetCore`, `.Instrumentation.Http`, `.Instrumentation.GrpcNetClient`, `.Exporter.OpenTelemetryProtocol` |
| **Por que foi usado** | Permite visualizar a latencia **decomposta por servico** — essencial para entender onde o tempo e gasto em cada padrao de comunicacao |

### 5.7 Jaeger

| | |
|---|---|
| **O que e** | Plataforma de distributed tracing criada pela Uber |
| **Imagem Docker** | `jaegertracing/all-in-one:latest` |
| **Por que foi usado** | Recebe traces via OTLP, armazena e disponibiliza uma UI web para visualizacao. Excelente para gerar **graficos de latencia** para a tese |

### 5.8 Apache JMeter

| | |
|---|---|
| **O que e** | Ferramenta open-source para testes de carga e performance |
| **Imagem Docker** | `justb4/jmeter:5.5` |
| **Por que foi usado** | Gera carga controlada (N threads, ramp-up, duracao) e produz relatorios com P90, P95, P99, throughput, etc. — exatamente as metricas necessarias para a tese |

### 5.9 Swagger (Swashbuckle)

| | |
|---|---|
| **O que e** | Ferramenta que gera documentacao interativa para APIs REST |
| **Pacote NuGet** | `Swashbuckle.AspNetCore 6.5.0` |
| **Por que foi usado** | Permite testar os endpoints visualmente pelo navegador em `http://localhost:5000/swagger` |

---

## 6. Como o Codigo Funciona (Fluxo Passo a Passo)

### 6.1 Fluxo REST

```
1. JMeter → POST http://api-gateway:5000/api/benchmark/rest
2. BenchmarkController.Rest() é chamado
3. Cria um OrderRequest com GUID aleatorio
4. Serializa para JSON: {"Id":"...","CustomerId":"customer-1","Value":99.99}
5. HttpClient faz POST http://processing-service:8080/api/orders
6. ProcessingService recebe via Minimal API (MapPost)
7. Simula processamento (Task.Delay 10ms)
8. Retorna 200 OK com JSON
9. ApiGateway repassa o resultado para o JMeter
```

**Codigo relevante — ApiGateway (quem chama):**
```csharp
[HttpPost("rest")]
public async Task<IActionResult> Rest()
{
    var order = new OrderRequest(Guid.NewGuid(), "customer-1", 99.99m);
    var client = httpClientFactory.CreateClient("ProcessingService");
    var json = JsonSerializer.Serialize(order);
    var content = new StringContent(json, Encoding.UTF8, "application/json");
    var response = await client.PostAsync("/api/orders", content);
    response.EnsureSuccessStatusCode();
    var body = await response.Content.ReadAsStringAsync();
    return Ok(body);
}
```

**Codigo relevante — ProcessingService (quem recebe):**
```csharp
app.MapPost("/api/orders", async (OrderRequest order) =>
{
    await Task.Delay(10); // simula processamento
    return Results.Ok(new { Success = true, Message = $"Order {order.Id} processed via REST" });
});
```

### 6.2 Fluxo gRPC

```
1. JMeter → POST http://api-gateway:5000/api/benchmark/grpc
2. BenchmarkController.Grpc() é chamado
3. Chama grpcClient.SubmitOrderAsync() com OrderRequestMessage (Protobuf)
4. Dados sao serializados em binario e enviados via HTTP/2
5. GrpcOrderService.SubmitOrder() recebe no ProcessingService
6. Simula processamento (Task.Delay 10ms)
7. Retorna OrderReplyMessage (Protobuf binario)
8. ApiGateway converte para JSON e retorna ao JMeter
```

**Codigo relevante — ApiGateway:**
```csharp
[HttpPost("grpc")]
public async Task<IActionResult> Grpc()
{
    var reply = await grpcClient.SubmitOrderAsync(new OrderRequestMessage
    {
        Id = Guid.NewGuid().ToString(),
        CustomerId = "customer-1",
        Value = 99.99
    });
    return Ok(new { reply.Success, reply.Message });
}
```

**Codigo relevante — ProcessingService:**
```csharp
public class GrpcOrderService : OrderProcessing.OrderProcessingBase
{
    public override async Task<OrderReplyMessage> SubmitOrder(
        OrderRequestMessage request, ServerCallContext context)
    {
        await Task.Delay(10);
        return new OrderReplyMessage
        {
            Success = true,
            Message = $"Order {request.Id} processed via gRPC"
        };
    }
}
```

### 6.3 Fluxo RabbitMQ

```
1. JMeter → POST http://api-gateway:5000/api/benchmark/rabbitmq
2. BenchmarkController.RabbitMq() é chamado
3. Serializa OrderRequest para JSON bytes
4. Publica na fila "orders-queue" via BasicPublish
5. Retorna 202 Accepted IMEDIATAMENTE (sem esperar processamento)
6. [Assincrono] RabbitMQ entrega a mensagem ao Consumer
7. RabbitMqConsumerService recebe via EventingBasicConsumer
8. Simula processamento (Task.Delay 10ms)
9. Envia BasicAck confirmando o processamento
```

**Codigo relevante — ApiGateway (produtor):**
```csharp
[HttpPost("rabbitmq")]
public IActionResult RabbitMq()
{
    var order = new OrderRequest(Guid.NewGuid(), "customer-1", 99.99m);
    using var channel = rabbitConnection.CreateModel();
    channel.QueueDeclare(queue: "orders-queue", durable: false,
                         exclusive: false, autoDelete: false);
    var body = Encoding.UTF8.GetBytes(JsonSerializer.Serialize(order));
    channel.BasicPublish(exchange: "", routingKey: "orders-queue",
                         basicProperties: null, body: body);
    return Accepted(new { Success = true, Message = $"Order {order.Id} published to queue" });
}
```

**Codigo relevante — ProcessingService (consumidor):**
```csharp
var consumer = new EventingBasicConsumer(_channel);
consumer.Received += async (_, ea) =>
{
    var body = Encoding.UTF8.GetString(ea.Body.ToArray());
    var order = JsonSerializer.Deserialize<OrderRequest>(body);
    await Task.Delay(10); // simula processamento
    _channel.BasicAck(ea.DeliveryTag, multiple: false); // confirma
};
_channel.BasicConsume(queue: "orders-queue", autoAck: false, consumer: consumer);
```

> **Nota importante:** O `autoAck: false` significa que a mensagem so e removida da fila apos o `BasicAck` explicito. Se o servico morrer antes do ack, a mensagem volta para a fila automaticamente.

---

## 7. Infraestrutura com Docker

### docker-compose.yml — Os 5 Servicos

```
┌─────────────────────────────────────────────────────────┐
│                    Docker Compose                        │
│                                                         │
│  ┌─────────────┐  ┌─────────────┐  ┌────────────────┐  │
│  │  RabbitMQ    │  │   Jaeger    │  │    JMeter      │  │
│  │  :5672/15672 │  │  :16686     │  │  (profile:     │  │
│  │  (broker)    │  │  :4317/4318 │  │   benchmark)   │  │
│  └──────┬───────┘  └──────┬──────┘  └───────┬────────┘  │
│         │                 │                 │            │
│  ┌──────┴─────────────────┴─────────────────┴────────┐  │
│  │              Processing Service                    │  │
│  │              :8080 (REST) / :50051 (gRPC)         │  │
│  └──────────────────────┬────────────────────────────┘  │
│                         │                                │
│  ┌──────────────────────┴────────────────────────────┐  │
│  │              API Gateway                           │  │
│  │              :5000 (HTTP)                          │  │
│  └───────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────┘
```

### Ordem de inicializacao (depends_on)

```
1. RabbitMQ (com healthcheck — espera ficar pronto)
2. Jaeger (sem healthcheck — inicia rapido)
3. Processing Service (depende de RabbitMQ healthy + Jaeger started)
4. API Gateway (depende de Processing Service)
5. JMeter (so roda com --profile benchmark)
```

### Variaveis de ambiente importantes

| Variavel | Servico | O que faz |
|----------|---------|-----------|
| `RabbitMq__Host=rabbitmq` | Ambos | Aponta para o hostname do container RabbitMQ (DNS interno do Docker) |
| `Otlp__Endpoint=http://jaeger:4317` | Ambos | Endpoint OTLP do Jaeger para envio de traces |
| `ProcessingService__RestUrl=http://processing-service:8080` | ApiGateway | URL base para chamadas REST |
| `ProcessingService__GrpcUrl=http://processing-service:50051` | ApiGateway | URL base para chamadas gRPC |
| `ASPNETCORE_URLS=http://+:5000` | ApiGateway | Porta HTTP do Kestrel |

> **Nota:** O separador `__` (duplo underscore) e a convencao do .NET para configuracao hierarquica via variavel de ambiente. `RabbitMq__Host` equivale a `{ "RabbitMq": { "Host": "..." } }` no `appsettings.json`.

---

## 8. Observabilidade — OpenTelemetry e Jaeger

### O que e Distributed Tracing?

Quando uma requisicao passa por **multiplos servicos**, e dificil saber onde o tempo foi gasto. O distributed tracing resolve isso criando um **trace** (rastro) que conecta todos os "spans" (trechos) da requisicao.

```
Trace: "POST /api/benchmark/rest"
├── Span 1: ApiGateway → recebe request (2ms)
├── Span 2: ApiGateway → envia HTTP para ProcessingService (15ms)
│   └── Span 3: ProcessingService → processa a ordem (12ms)
└── Total: 29ms
```

### Como funciona neste projeto

```csharp
// Ambos os servicos configuram o OpenTelemetry assim:
builder.Services.AddOpenTelemetry()
    .ConfigureResource(resource => resource.AddService("Tcc.ApiGateway"))
    .WithTracing(tracing => tracing
        .AddAspNetCoreInstrumentation()    // Captura requests HTTP recebidos
        .AddHttpClientInstrumentation()     // Captura requests HTTP enviados
        .AddGrpcClientInstrumentation()     // Captura chamadas gRPC (so no Gateway)
        .AddOtlpExporter(options =>          // Envia para o Jaeger via OTLP/gRPC
        {
            options.Endpoint = new Uri("http://jaeger:4317");
        }));
```

### O que cada instrumentacao captura

| Instrumentacao | Servico | O que captura |
|---------------|---------|---------------|
| `AddAspNetCoreInstrumentation()` | Ambos | Requests HTTP/gRPC **recebidos** pelo servico |
| `AddHttpClientInstrumentation()` | Ambos | Requests HTTP **enviados** via `HttpClient` (REST) |
| `AddGrpcClientInstrumentation()` | ApiGateway | Chamadas gRPC **enviadas** para o ProcessingService |
| `AddOtlpExporter()` | Ambos | Exporta os traces coletados para o Jaeger via protocolo OTLP |

### Como visualizar no Jaeger

1. Acesse http://localhost:16686
2. Selecione o servico `Tcc.ApiGateway` no dropdown
3. Clique em **Find Traces**
4. Cada trace mostra a cadeia completa: Gateway → ProcessingService

---

## 9. Benchmark com JMeter

### Como o JMeter funciona nesta PoC

O arquivo `tcc_benchmark.jmx` define **3 Thread Groups** que rodam **sequencialmente**:

```
Thread Group 1: REST Benchmark
  → N threads fazendo POST /api/benchmark/rest por D segundos

Thread Group 2: gRPC Benchmark
  → N threads fazendo POST /api/benchmark/grpc por D segundos

Thread Group 3: RabbitMQ Benchmark
  → N threads fazendo POST /api/benchmark/rabbitmq por D segundos
```

### Parametros configuraveis

Os parametros usam `${__P(VAR,default)}` do JMeter, permitindo override pela linha de comando:

| Parametro JMeter | Flag CLI | Default | Descricao |
|-------------------|----------|---------|-----------|
| `THREADS` | `-JTHREADS=N` | 50 | Usuarios virtuais simultaneos |
| `RAMP_UP` | `-JRAMP_UP=N` | 10 | Segundos para atingir todas as threads |
| `DURATION` | `-JDURATION=N` | 60 | Duracao de cada grupo em segundos |
| `BASE_HOST` | `-JBASE_HOST=X` | localhost | Host do API Gateway |
| `BASE_PORT` | `-JBASE_PORT=N` | 5000 | Porta do API Gateway |

### Metricas geradas

O relatorio HTML (`results/html_report/index.html`) contem:

| Metrica | O que significa |
|---------|----------------|
| **Average** | Latencia media de todas as requests |
| **Min / Max** | Menor e maior latencia observadas |
| **P90** | 90% das requests completaram em ate X ms |
| **P95** | 95% das requests completaram em ate X ms |
| **P99** | 99% das requests completaram em ate X ms |
| **Throughput** | Requests por segundo (req/s) |
| **Error %** | Percentual de requests com falha |

> **Para a tese:** Os valores mais relevantes sao **P95**, **P99** e **Throughput**. Medias podem ser enganosas porque nao mostram outliers.

---

## 10. Como Utilizar

### Pre-requisitos

1. [Docker Desktop](https://docs.docker.com/get-docker/) instalado e rodando
2. PowerShell (Windows) ou Bash (Linux/macOS)

### Execucao Rapida (1 comando)

**Windows:**
```powershell
.\run_benchmark.ps1
```

**Linux/macOS:**
```bash
chmod +x run_benchmark.sh
./run_benchmark.sh
```

### Execucao com parametros customizados

**Windows:**
```powershell
.\run_benchmark.ps1 -Threads 100 -RampUp 15 -Duration 120
```

**Linux/macOS:**
```bash
./run_benchmark.sh 100 15 120
```

### O que o script faz (5 etapas)

```
[1/5] Limpando resultados anteriores...
      → Remove a pasta results/ (JMeter exige pasta vazia)

[2/5] Subindo infraestrutura Docker...
      → docker-compose up --build -d
      → Builda as imagens e sobe: RabbitMQ, Jaeger, ProcessingService, ApiGateway

[3/5] Aguardando servicos ficarem prontos...
      → Faz polling em http://localhost:5000/swagger/index.html
      → Tenta ate 30 vezes com 3s de intervalo

[4/5] Executando JMeter...
      → docker-compose --profile benchmark run --rm jmeter
      → Roda os 3 Thread Groups sequencialmente

[5/5] Abrindo relatorio...
      → Abre results/html_report/index.html no navegador
```

### Verificacao manual dos endpoints

```bash
# Testar REST
curl -X POST http://localhost:5000/api/benchmark/rest
# Esperado: 200 OK {"Success":true,"Message":"Order ... processed via REST"}

# Testar gRPC
curl -X POST http://localhost:5000/api/benchmark/grpc
# Esperado: 200 OK {"success":true,"message":"Order ... processed via gRPC"}

# Testar RabbitMQ
curl -X POST http://localhost:5000/api/benchmark/rabbitmq
# Esperado: 202 Accepted {"Success":true,"Message":"Order ... published to queue"}
```

### Interfaces web disponiveis

| Interface | URL | Descricao |
|-----------|-----|-----------|
| Swagger UI | http://localhost:5000/swagger | Documentacao interativa dos endpoints |
| RabbitMQ Management | http://localhost:15672 | Painel do broker (user: `guest`, pass: `guest`) |
| Jaeger UI | http://localhost:16686 | Visualizacao de traces distribuidos |

### Parar tudo

```powershell
# Parar containers (mantem volumes)
docker-compose down

# Parar e limpar tudo (volumes inclusos)
docker-compose down -v
```

---

## 11. Glossario de Termos

| Termo | Definicao |
|-------|-----------|
| **Microservice** | Servico independente e pequeno que faz uma coisa bem feita, comunicando-se com outros servicos via rede |
| **API Gateway** | Ponto de entrada unico que roteia requisicoes para os microservices internos |
| **REST** | Estilo arquitetural que usa HTTP + JSON para comunicacao entre sistemas |
| **gRPC** | Framework RPC (Remote Procedure Call) do Google, usa HTTP/2 + Protobuf |
| **Protobuf** | Formato de serializacao binaria do Google — menor e mais rapido que JSON |
| **RabbitMQ** | Message broker que intermedia comunicacao assincrona entre servicos |
| **AMQP** | Protocolo padrao de mensageria usado pelo RabbitMQ |
| **Queue** | Fila de mensagens — produtor publica, consumidor consome |
| **Sincrono** | O cliente envia a requisicao e **espera** a resposta |
| **Assincrono** | O cliente envia a mensagem e **nao espera** — continua imediatamente |
| **Fire-and-Forget** | Padrao onde o produtor envia e esquece — nao recebe confirmacao de processamento |
| **Throughput** | Quantidade de operacoes por segundo (req/s) |
| **Latencia** | Tempo entre o envio da requisicao e o recebimento da resposta |
| **P95 / P99** | Percentil 95/99 — "95% (ou 99%) das requests completaram em ate X ms" |
| **Distributed Tracing** | Tecnica para rastrear uma requisicao atraves de multiplos servicos |
| **Span** | Trecho individual de um trace (ex: "chamada HTTP de A para B") |
| **OpenTelemetry** | Padrao aberto para coleta de traces, metricas e logs |
| **OTLP** | OpenTelemetry Protocol — protocolo de transporte dos dados de telemetria |
| **Docker Compose** | Ferramenta para definir e rodar aplicacoes multi-container |
| **Multi-stage Build** | Tecnica de Dockerfile que separa build (SDK pesado) de runtime (imagem leve) |
| **Kestrel** | Servidor web embutido no .NET, de alta performance |
| **Minimal API** | Estilo simplificado de definir endpoints no .NET (sem Controllers) |
| **BackgroundService** | Classe .NET para rodar tarefas em background (ex: consumer RabbitMQ) |
| **Healthcheck** | Verificacao periodica da saude de um container |
| **JMeter** | Ferramenta de teste de carga da Apache Foundation |
| **Thread Group** | Grupo de "usuarios virtuais" no JMeter que executam requests simultaneamente |
