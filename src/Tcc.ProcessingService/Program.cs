using Microsoft.AspNetCore.Server.Kestrel.Core;
using OpenTelemetry.Resources;
using OpenTelemetry.Trace;
using Tcc.ProcessingService.Services;
using Tcc.Shared.Dtos;

var builder = WebApplication.CreateBuilder(args);

builder.WebHost.ConfigureKestrel(options =>
{
    // HTTP/1.1 for REST
    options.ListenAnyIP(8080, o => o.Protocols = HttpProtocols.Http1AndHttp2);
    // HTTP/2 for gRPC (unencrypted)
    options.ListenAnyIP(50051, o => o.Protocols = HttpProtocols.Http2);
});

builder.Services.AddGrpc();
builder.Services.AddHostedService<RabbitMqConsumerService>();

// OpenTelemetry Distributed Tracing
var otlpEndpoint = builder.Configuration["Otlp:Endpoint"] ?? "http://localhost:4317";
builder.Services.AddOpenTelemetry()
    .ConfigureResource(resource => resource.AddService("Tcc.ProcessingService"))
    .WithTracing(tracing => tracing
        .AddAspNetCoreInstrumentation()
        .AddHttpClientInstrumentation()
        .AddOtlpExporter(options =>
        {
            options.Endpoint = new Uri(otlpEndpoint);
            options.Protocol = OpenTelemetry.Exporter.OtlpExportProtocol.Grpc;
        }));

var app = builder.Build();

// REST endpoint
app.MapPost("/api/orders", async (OrderRequest order) =>
{
    await Task.Delay(10);
    return Results.Ok(new { Success = true, Message = $"Order {order.Id} processed via REST" });
});

// gRPC service
app.MapGrpcService<GrpcOrderService>();

app.Run();
