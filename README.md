# Robotics Wiki

Documentation site for onboarding and internal knowledge around **autonomous systems and drone development** (Ubuntu 24.04, ROS 2 Jazzy, Gazebo, PX4 SITL, and related tooling).

Built with [Astro](https://astro.build/) and [Starlight](https://starlight.astro.build/).

## What’s in the site

| Area | Purpose |
|------|--------|
| **[Onboarding](src/content/docs/onboarding/)** | Ordered path: platform → ROS 2 → verify → demo → PX4 SITL → first contribution, plus troubleshooting and AI-assisted coding notes. |
| **[Milestones](src/content/docs/milestones/)** | Practical track (T0+); completion criteria aligned with the onboarding steps. |
| **[install/](install/)** | Modular bash installer (`bootstrap.sh` for `curl \| bash`, `main.sh` for local runs). See [install/README.md](install/README.md). |
| `guides/`, `reference/` | Reserved for future Diátaxis-style guides and reference; starter examples are not linked from the sidebar until real content lands. |

The published home page is the Starlight splash at `/`; primary entry for new members is **`/onboarding/`**.

## Prerequisites

- Node.js 18+ (see Astro’s [environment docs](https://docs.astro.build/en/install-and-setup/))
- npm (or another compatible package manager)

## Commands

From this directory:

| Command | Action |
|--------|--------|
| `npm install` | Install dependencies |
| `npm run dev` | Dev server (default [localhost:4321](http://localhost:4321)) |
| `npm run build` | Production build to `dist/` |
| `npm run preview` | Preview the production build locally |

## Project layout

```
.
├── public/                 # Static assets (favicon, etc.)
├── install/                # Modular robotics stack installer (bash)
├── src/
│   ├── assets/             # Images used from MDX/Markdown
│   └── content/docs/       # All wiki pages (routes follow file paths)
├── robotics-setup.sh       # Wrapper → install/main.sh
├── astro.config.mjs        # Site title, sidebar, Starlight options
├── src/content.config.ts   # Content collections
└── package.json
```

## Source repository

https://github.com/2vyy/robotics-docs

## Contributing to the docs

Editorial goals: concise, task-oriented, human-maintained pages (see internal notes under `docs/superpowers/specs/` if present). For how to submit changes, see the wiki page **[Onboarding → Contribute](src/content/docs/onboarding/contribute.mdx)** once the site is running, or open that file in the repo.
