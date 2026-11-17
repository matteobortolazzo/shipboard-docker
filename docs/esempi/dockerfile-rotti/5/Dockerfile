# syntax=docker/dockerfile:1
FROM mcr.microsoft.com/dotnet/sdk:10.0 AS build
WORKDIR /src
COPY ShipBoard.Api.csproj ./
RUN dotnet restore ShipBoard.Api.csproj
COPY . ./
RUN dotnet publish ShipBoard.Api.csproj -c Release -o /app --no-restore

FROM mcr.microsoft.com/dotnet/aspnet:10.0-noble-chiseled
WORKDIR /app
COPY --from=build /app ./
EXPOSE 8080
USER root
ENTRYPOINT ["dotnet", "ShipBoard.Api.dll"]
