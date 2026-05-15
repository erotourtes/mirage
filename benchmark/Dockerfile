FROM node:20-bookworm-slim

RUN apt-get update \
  && apt-get install -y --no-install-recommends ca-certificates git \
  && rm -rf /var/lib/apt/lists/*

WORKDIR /work

COPY benchmark/scripts ./benchmark/scripts
COPY benchmark/mirage ./benchmark/mirage

RUN chmod +x ./benchmark/scripts/*.sh

CMD ["benchmark/scripts/run-crdt-benchmarks.sh"]
