# Pinned on purpose: LiteLLM ships several releases a week, and a moving tag is
# the difference between a template that works for years and one that breaks
# silently. The -database image carries the Prisma toolchain, so the proxy
# migrates its own schema on first boot instead of needing a separate job.
FROM ghcr.io/berriai/litellm-database:v1.103.2

COPY config.yaml /app/config.yaml

ENTRYPOINT ["docker/prod_entrypoint.sh"]
CMD ["--config", "/app/config.yaml", "--port", "4000"]
