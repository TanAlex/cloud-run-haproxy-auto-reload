FROM haproxy:latest

# Switch to root for file operations
USER root

# Copy configuration and entrypoint script
COPY haproxy.cfg /etc/haproxy/haproxy.cfg
COPY entrypoint.sh /entrypoint.sh

# RUN apt-get update && apt-get install -y vim

# Make the entrypoint executable
RUN chmod +x /entrypoint.sh

# Create a directory for HAProxy runtime files and set ownership
RUN mkdir -p /run/haproxy && chown haproxy:haproxy /run/haproxy
RUN chown haproxy:haproxy /etc/haproxy/haproxy.cfg

# Switch back to the haproxy user for runtime
USER haproxy

# Expose port (informational)
EXPOSE 8080

# Use the entrypoint script instead of CMD directly
CMD ["/entrypoint.sh"]