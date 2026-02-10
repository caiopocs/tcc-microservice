using System.Text;
using System.Text.Json;
using RabbitMQ.Client;
using RabbitMQ.Client.Events;
using Tcc.Shared.Dtos;

namespace Tcc.ProcessingService.Services;

public class RabbitMqConsumerService(IConfiguration configuration, ILogger<RabbitMqConsumerService> logger) : BackgroundService
{
    private IConnection? _connection;
    private IModel? _channel;

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        var host = configuration.GetValue<string>("RabbitMq:Host") ?? "localhost";

        // Wait for RabbitMQ to be ready
        var connected = false;
        while (!connected && !stoppingToken.IsCancellationRequested)
        {
            try
            {
                var factory = new ConnectionFactory { HostName = host };
                _connection = factory.CreateConnection();
                _channel = _connection.CreateModel();
                connected = true;
            }
            catch (Exception ex)
            {
                logger.LogWarning("RabbitMQ not ready, retrying in 3s... {Message}", ex.Message);
                await Task.Delay(3000, stoppingToken);
            }
        }

        if (_channel is null) return;

        _channel.QueueDeclare(queue: "orders-queue", durable: false, exclusive: false, autoDelete: false);

        var consumer = new EventingBasicConsumer(_channel);
        consumer.Received += async (_, ea) =>
        {
            try
            {
                var body = Encoding.UTF8.GetString(ea.Body.ToArray());
                var order = JsonSerializer.Deserialize<OrderRequest>(body);
                logger.LogInformation("RabbitMQ order received: {OrderId}", order?.Id);

                await Task.Delay(10);

                _channel.BasicAck(ea.DeliveryTag, multiple: false);
            }
            catch (Exception ex)
            {
                logger.LogError(ex, "Error processing RabbitMQ message");
                _channel.BasicNack(ea.DeliveryTag, multiple: false, requeue: true);
            }
        };

        _channel.BasicConsume(queue: "orders-queue", autoAck: false, consumer: consumer);

        await Task.Delay(Timeout.Infinite, stoppingToken);
    }

    public override void Dispose()
    {
        _channel?.Close();
        _connection?.Close();
        base.Dispose();
    }
}
