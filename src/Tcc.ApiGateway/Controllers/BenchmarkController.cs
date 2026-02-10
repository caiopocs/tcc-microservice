using System.Text;
using System.Text.Json;
using Microsoft.AspNetCore.Mvc;
using RabbitMQ.Client;
using Tcc.Shared.Dtos;
using Tcc.Shared.Protos;

namespace Tcc.ApiGateway.Controllers;

[ApiController]
[Route("api/benchmark")]
public class BenchmarkController(
    IHttpClientFactory httpClientFactory,
    OrderProcessing.OrderProcessingClient grpcClient,
    IConnection rabbitConnection) : ControllerBase
{
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

    [HttpPost("rabbitmq")]
    public IActionResult RabbitMq()
    {
        var order = new OrderRequest(Guid.NewGuid(), "customer-1", 99.99m);

        using var channel = rabbitConnection.CreateModel();
        channel.QueueDeclare(queue: "orders-queue", durable: false, exclusive: false, autoDelete: false);

        var body = Encoding.UTF8.GetBytes(JsonSerializer.Serialize(order));
        channel.BasicPublish(exchange: "", routingKey: "orders-queue", basicProperties: null, body: body);

        return Accepted(new { Success = true, Message = $"Order {order.Id} published to queue" });
    }
}
