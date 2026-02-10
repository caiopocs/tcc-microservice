FROM mcr.microsoft.com/dotnet/sdk:8.0 AS build
WORKDIR /src
COPY src/Tcc.Shared/Tcc.Shared.csproj Tcc.Shared/
COPY src/Tcc.ApiGateway/Tcc.ApiGateway.csproj Tcc.ApiGateway/
RUN dotnet restore Tcc.ApiGateway/Tcc.ApiGateway.csproj
COPY src/Tcc.Shared/ Tcc.Shared/
COPY src/Tcc.ApiGateway/ Tcc.ApiGateway/
RUN dotnet publish Tcc.ApiGateway/Tcc.ApiGateway.csproj -c Release -o /app/publish

FROM mcr.microsoft.com/dotnet/aspnet:8.0
WORKDIR /app
COPY --from=build /app/publish .
ENTRYPOINT ["dotnet", "Tcc.ApiGateway.dll"]
