# =============================================================================
# Dockerfile — Multi-stage build
# Stage 1: build and publish
# Stage 2: runtime only (no SDK in final image = smaller attack surface)
# Non-root user: security best practice, required by some compliance frameworks
# =============================================================================

# Stage 1: Build
FROM mcr.microsoft.com/dotnet/sdk:8.0-alpine AS build
WORKDIR /src

# Copy project file first — Docker layer caching
# If .csproj hasn't changed, restore is cached and skipped on rebuild
COPY ["OrderManagement.Api.csproj", "./"]
RUN dotnet restore "OrderManagement.Api.csproj" \
    --runtime linux-musl-x64 \
    --no-cache

# Copy source and publish
COPY . .
RUN dotnet publish "OrderManagement.Api.csproj" \
    --configuration Release \
    --runtime linux-musl-x64 \
    --self-contained true \
    --output /app/publish \
    /p:PublishSingleFile=true \
    /p:PublishTrimmed=true

# Stage 2: Runtime
FROM mcr.microsoft.com/dotnet/runtime-deps:8.0-alpine AS runtime
WORKDIR /app

# Create non-root user — container runs as uid 1000, not root
# This limits blast radius if the container is compromised
RUN addgroup -S appgroup && adduser -S appuser -G appgroup
USER appuser

# Copy published output from build stage
COPY --from=build --chown=appuser:appgroup /app/publish .

# Health check — Docker/Kubernetes can use this to determine container health
HEALTHCHECK --interval=30s --timeout=10s --start-period=30s --retries=3 \
    CMD wget -qO- http://localhost:8080/health || exit 1

EXPOSE 8080
ENV ASPNETCORE_URLS=http://+:8080

ENTRYPOINT ["./OrderManagement.Api"]