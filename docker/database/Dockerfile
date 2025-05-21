FROM postgres:14-alpine

# Custom PostgreSQL configuration could be added here
# COPY postgresql.conf /etc/postgresql/postgresql.conf

# Add any initialization scripts
COPY init.sql /docker-entrypoint-initdb.d/

# Container metadata
LABEL maintainer="Your Name <your.email@example.com>"
LABEL description="Database service for multi-container application"
LABEL version="1.0"

# Health check
HEALTHCHECK --interval=30s --timeout=5s --start-period=30s --retries=3 \
  CMD pg_isready -U postgres || exit 1

# Expose port
EXPOSE 5432

# Default command is inherited from the postgres image