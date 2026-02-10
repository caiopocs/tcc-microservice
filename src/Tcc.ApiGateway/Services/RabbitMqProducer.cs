using System.Text;
using System.Text.Json;
using RabbitMQ.Client;
using Tcc.Shared.Dtos;

namespace Tcc.ApiGateway.Services;

public class RabbitMqProducer : IDisposable
{
    private readonly IConnection _connection;
    private readonly IModel _channel;
    private readonly object _lock = new();

    public RabbitMqProducer(IConfiguration configuration)
    {
        var host = configuration["RabbitMq:Host"] ?? "localhost";
        var factory = new ConnectionFactory { HostName = host };
        _connection = factory.CreateConnection();
        _channel = _connection.CreateModel();
        _channel.QueueDeclare(queue: "orders-queue", durable: false, exclusive: false, autoDelete: false);
    }

    public void Publish(OrderRequest order)
    {
        var body = Encoding.UTF8.GetBytes(JsonSerializer.Serialize(order));
        lock (_lock)
        {
            _channel.BasicPublish(exchange: "", routingKey: "orders-queue", basicProperties: null, body: body);
        }
    }

    public void Dispose()
    {
        _channel?.Close();
        _connection?.Close();
    }
}
