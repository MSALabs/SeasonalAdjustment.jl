# .devcontainer/Dockerfile
FROM mcr.microsoft.com/devcontainers/base:ubuntu-24.04

USER vscode

# Julia via juliaup, matching TSAnalytics.jl's own devcontainer convention
RUN curl -fsSL https://install.julialang.org | sh -s -- --yes \
    && echo 'export PATH="$HOME/.juliaup/bin:$PATH"' >> /home/vscode/.bashrc
ENV PATH="/home/vscode/.juliaup/bin:${PATH}"

# R and Python -- R specifically for cross-checking wrapper-level output
# against R's own seasonal/x13binary packages (both call the SAME
# x13prebuilt binary this project wraps directly -- see
# development-sequence.md's verification-philosophy note for Part 1 vs
# Part 2's genuinely different testing standards), Python for the
# equivalent statsmodels.tsa.x13 cross-check and for Part 2's native
# engine dual-verification once that track starts
USER root
RUN apt-get update && apt-get install -y --no-install-recommends \
    r-base-core \
    python3 python3-pip \
    unzip \
    && rm -rf /var/lib/apt/lists/*
USER vscode

WORKDIR /workspace
