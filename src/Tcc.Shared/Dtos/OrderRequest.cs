namespace Tcc.Shared.Dtos;

public record OrderRequest(Guid Id, string CustomerId, decimal Value, string DataBlob);
