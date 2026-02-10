using Grpc.Core;
using Tcc.Shared.Protos;

namespace Tcc.ProcessingService.Services;

public class GrpcOrderService(ILogger<GrpcOrderService> logger) : OrderProcessing.OrderProcessingBase
{
    public override async Task<OrderReplyMessage> SubmitOrder(OrderRequestMessage request, ServerCallContext context)
    {
        logger.LogInformation("gRPC order received: {OrderId}", request.Id);
        await Task.Delay(10);
        return new OrderReplyMessage
        {
            Success = true,
            Message = $"Order {request.Id} processed via gRPC"
        };
    }
}
