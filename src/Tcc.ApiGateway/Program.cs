using OpenTelemetry.Resources;
using OpenTelemetry.Trace;
using Tcc.ApiGateway.Services;
using Tcc.Shared.Protos;

AppContext.SetSwitch("System.Net.Http.SocketsHttpHandler.Http2UnencryptedSupport", true);

var builder = WebApplication.CreateBuilder(args);

builder.Services.AddControllers();
builder.Services.AddEndpointsApiExplorer();
builder.Services.AddSwaggerGen(c =>
{
    c.SwaggerDoc("v1", new Microsoft.OpenApi.Models.OpenApiInfo
    {
        Title = "TCC Benchmark API",
        Version = "v1",
        Description = "API Gateway for benchmarking REST, gRPC, and RabbitMQ communication patterns"
    });
});

// OpenTelemetry Distributed Tracing
var otlpEndpoint = builder.Configuration["Otlp:Endpoint"] ?? "http://localhost:4317";
builder.Services.AddOpenTelemetry()
    .ConfigureResource(resource => resource.AddService("Tcc.ApiGateway"))
    .WithTracing(tracing => tracing
        .AddAspNetCoreInstrumentation()
        .AddHttpClientInstrumentation()
        .AddGrpcClientInstrumentation()
        .AddOtlpExporter(options =>
        {
            options.Endpoint = new Uri(otlpEndpoint);
            options.Protocol = OpenTelemetry.Exporter.OtlpExportProtocol.Grpc;
        }));

// HTTP client for REST calls
builder.Services.AddHttpClient("ProcessingService", client =>
{
    var url = builder.Configuration["ProcessingService:RestUrl"] ?? "http://localhost:8080";
    client.BaseAddress = new Uri(url);
});

// gRPC client
var grpcUrl = builder.Configuration["ProcessingService:GrpcUrl"] ?? "http://localhost:50051";
builder.Services.AddSingleton(_ =>
{
    var channel = Grpc.Net.Client.GrpcChannel.ForAddress(grpcUrl);
    return new OrderProcessing.OrderProcessingClient(channel);
});

// RabbitMQ singleton producer (single connection + channel, thread-safe via lock)
builder.Services.AddSingleton<RabbitMqProducer>();

var app = builder.Build();

app.UseSwagger();
app.UseSwaggerUI();

app.MapControllers();

app.Run();
