# ============================================================
# Stage 1: DEPENDENCY INSTALLATION
# Uses node:22-alpine to satisfy modern Vite engine requirements
# ============================================================
FROM node:22-alpine AS deps

WORKDIR /app

# Copy only package files first (leverages Docker layer cache)
COPY package.json package-lock.json* ./

# Install all dependencies for the build stage (includes devDependencies)
RUN npm ci && npm cache clean --force


# ============================================================
# Stage 2: BUILD
# Full devDependencies needed for React build
# ============================================================
FROM node:22-alpine AS builder

WORKDIR /app

# Copy dependencies from previous stage
COPY --from=deps /app/node_modules ./node_modules

# Copy source files
COPY . .

# Build-time environment variables (passed via --build-arg)
ARG REACT_APP_API_URL
ARG REACT_APP_VERSION
ARG NODE_ENV=production

ENV REACT_APP_API_URL=$REACT_APP_API_URL
ENV REACT_APP_VERSION=$REACT_APP_VERSION
ENV NODE_ENV=$NODE_ENV

# Create optimized production build
RUN npm run build


# ============================================================
# Stage 3: PRODUCTION (Final image)
# Only Nginx + static files — NO Node.js runtime
# Final image size: ~25MB vs ~350MB if using Node
# ============================================================
FROM nginx:1.25-alpine AS production

# Security: run nginx as non-root user
RUN addgroup -g 1001 -S nginx-app \
    && adduser -S -D -H -u 1001 -h /var/cache/nginx -s /sbin/nologin \
    -G nginx-app -g nginx-app nginx-app

# Remove default nginx config
RUN rm /etc/nginx/conf.d/default.conf

# Copy our custom nginx config
COPY nginx/nginx.conf /etc/nginx/conf.d/app.conf

# Copy compiled React app from builder stage
COPY --from=builder /app/dist /usr/share/nginx/html

# Runtime environment variable injection script
# (Replaces __ENV_VAR__ placeholders at container start)
COPY nginx/env.sh /docker-entrypoint.d/40-env-inject.sh
RUN chmod +x /docker-entrypoint.d/40-env-inject.sh

# Fix permissions for non-root
RUN chown -R nginx-app:nginx-app /usr/share/nginx/html \
    && chown -R nginx-app:nginx-app /var/cache/nginx \
    && chown -R nginx-app:nginx-app /var/log/nginx \
    && touch /var/run/nginx.pid \
    && chown nginx-app:nginx-app /var/run/nginx.pid

# Expose port (non-privileged)
EXPOSE 8080

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD wget --no-verbose --tries=1 --spider http://localhost:8080/health || exit 1

# Labels for metadata
LABEL maintainer="your-team@example.com" \
      org.opencontainers.image.title="React App" \
      org.opencontainers.image.description="Production React application" \
      org.opencontainers.image.vendor="Your Organization"

USER nginx-app

CMD ["nginx", "-g", "daemon off;"]
