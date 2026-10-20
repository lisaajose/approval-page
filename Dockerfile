# ==============================================================================
# Multi-Stage Dockerfile for ASP.NET Core MVC Approval Workflow
# Target Framework: .NET 8.0 LTS
# Compatible with Render, Azure SQL, and Linux Container Environments
# ==============================================================================

# Stage 1: Build & Restore
FROM mcr.microsoft.com/dotnet/sdk:8.0 AS build
WORKDIR /src

# Copy project definition and restore dependencies (optimizes Docker layer caching)
COPY ["ApprovalWorkflow.csproj", "./"]
RUN dotnet restore "ApprovalWorkflow.csproj"

# Copy all application source code
COPY . .

# Build application in Release configuration
RUN dotnet build "ApprovalWorkflow.csproj" -c Release -o /app/build

# Stage 2: Publish
FROM build AS publish
RUN dotnet publish "ApprovalWorkflow.csproj" -c Release -o /app/publish /p:UseAppHost=false

# Stage 3: Runtime
FROM mcr.microsoft.com/dotnet/aspnet:8.0 AS final
WORKDIR /app

# Non-root security (default non-root app user in .NET 8)
USER $APP_UID

# Copy published binaries and static assets
COPY --from=publish /app/publish .

# Default container listening configuration
ENV ASPNETCORE_HTTP_PORTS=8080
EXPOSE 8080

# Dynamic port binding: Render injects $PORT at container runtime.
# If $PORT is unset (e.g. local Docker runs), it gracefully falls back to port 8080.
ENTRYPOINT ["sh", "-c", "dotnet ApprovalWorkflow.dll --urls http://0.0.0.0:${PORT:-8080}"]
