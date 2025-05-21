FROM nginx:alpine

# Copy custom nginx config if needed
# COPY nginx.conf /etc/nginx/conf.d/default.conf

# Copy static files
COPY index.html /usr/share/nginx/html/

# Create data directory for shared volume
RUN mkdir -p /usr/share/nginx/html/data

# Container metadata
LABEL maintainer="Your Name <your.email@example.com>"
LABEL description="Frontend service for multi-container application"
LABEL version="1.0"

# Health check
HEALTHCHECK --interval=30s --timeout=5s --start-period=5s --retries=3 \
  CMD wget --quiet --tries=1 --spider http://localhost:80/ || exit 1

# Expose port
EXPOSE 80

# Run nginx in foreground
CMD ["nginx", "-g", "daemon off;"]