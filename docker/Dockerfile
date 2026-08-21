# Skarb ships as a single image: the API serves the SPA out of its own wwwroot
# (see vite.config.ts and MapFallbackToFile in Program.cs), so there is no
# separate frontend container.

# --- SPA build ---
FROM node:22-slim AS spa-build
WORKDIR /src/frontend

COPY frontend/package.json frontend/package-lock.json ./
RUN npm ci

COPY frontend ./
# vite.config.ts writes the bundle to ../backend/Skarb.Api/wwwroot.
RUN npm run build

# --- API build ---
FROM mcr.microsoft.com/dotnet/sdk:10.0 AS api-build
WORKDIR /src

COPY backend/Skarb.Api/Skarb.Api.csproj backend/Skarb.Api/
RUN dotnet restore backend/Skarb.Api/Skarb.Api.csproj

COPY backend/Skarb.Api backend/Skarb.Api
# SkipSpa: the SPA is built in its own stage above with node available.
RUN dotnet publish backend/Skarb.Api/Skarb.Api.csproj -c Release -o /app/publish /p:UseAppHost=false /p:SkipSpa=true

# --- runtime ---
FROM mcr.microsoft.com/dotnet/aspnet:10.0 AS runtime
WORKDIR /app

RUN apt-get update && apt-get install -y --no-install-recommends curl && rm -rf /var/lib/apt/lists/*

COPY --from=api-build /app/publish .
COPY --from=spa-build /src/backend/Skarb.Api/wwwroot ./wwwroot

ENV ASPNETCORE_URLS=http://+:8080
EXPOSE 8080

# "/" is the SPA shell served by static files — anonymous and rate-limit free, so the
# probe never trips the per-IP limiter on the auth endpoints. The generous start period
# covers first-boot EF migrations on a small droplet.
HEALTHCHECK --interval=30s --timeout=5s --start-period=60s --retries=5 \
  CMD curl -sf http://localhost:8080/ > /dev/null || exit 1

CMD ["dotnet", "Skarb.Api.dll"]
