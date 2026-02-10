FROM mcr.microsoft.com/dotnet/sdk:8.0 AS build
WORKDIR /src
COPY src/Tcc.Shared/Tcc.Shared.csproj Tcc.Shared/
COPY src/Tcc.ProcessingService/Tcc.ProcessingService.csproj Tcc.ProcessingService/
RUN dotnet restore Tcc.ProcessingService/Tcc.ProcessingService.csproj
COPY src/Tcc.Shared/ Tcc.Shared/
COPY src/Tcc.ProcessingService/ Tcc.ProcessingService/
RUN dotnet publish Tcc.ProcessingService/Tcc.ProcessingService.csproj -c Release -o /app/publish

FROM mcr.microsoft.com/dotnet/aspnet:8.0
WORKDIR /app
COPY --from=build /app/publish .
ENTRYPOINT ["dotnet", "Tcc.ProcessingService.dll"]
