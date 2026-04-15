# v2-modular

This repository contains the **v2-modular bootstrap system**, designed to configure a **Fedora 43 + Sway (Wayland)** workstation. It follows a declarative, modular, and idempotent architecture using YAML manifests and INI profiles for configuration.

For an in-depth view of the architecture and module specifications, please read [ARCH.md](ARCH.md).
For the detailed implementation plan, see [PLAN.md](PLAN.md).

## Current Status

The repository is currently in its initial planning and documentation phase. Core documentation files have been created, outlining the structural design, module contracts, state sync mechanisms, and the planned phases of execution.

## Branches

Below is a list of existing branches and their designated purposes:

*   **`main`**: The primary branch. It holds the current state of the architecture documentation (`ARCH.md`), implementation planning (`PLAN.md`), and this README.
*   **`add-plan-md-8811978431622922469`**: Dedicated to adding implementation plans (`PLAN.md`) and detailing documentation tasks.
*   **`nextcloud-docker-deploy-1065420269271942081`**: Used for developing and deploying a Nextcloud Docker Compose stack complete with Traefik, PostgreSQL, and Redis.
