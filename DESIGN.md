---
name: Gallformers
description: Pointer to the Gallformers design system in docs/design-system/; that system, not this file, is the visual authority.
---

# Design System: Gallformers

This file is a pointer. The Gallformers design system lives in **[docs/design-system/](docs/design-system/README.md)** and owns every visual and component decision. Read it before designing or changing any UI. Don't copy its tokens, rules or components into this file: a second copy drifts. When the system changes, it changes there.

## Overview

Start with [docs/design-system/README.md](docs/design-system/README.md): what each document holds, the five rules, where things live in the code, how to replace or add a component, and the conformance ratchet. The living reference is the style guide at `/dev/design-system` (development only), which renders every token and built component in light and dark.

## Colors

Principles, the semantic color tokens and their roles: [foundations.md](docs/design-system/foundations.md#color). Values, light and dark: `assets/css/system/tokens.css`.

## Typography

Typefaces, the semantic type scale and the two densities (Reading for public, Working for admin): [foundations.md](docs/design-system/foundations.md#typography), [spacing and density](docs/design-system/foundations.md#spacing-and-density). Font faces: `assets/css/system/fonts.css`.

## Layout

Layout: [foundations.md](docs/design-system/foundations.md#layout). Page templates (detail, browse, admin list, admin edit, review step): [patterns.md](docs/design-system/patterns.md).

## Elevation & Depth

Radius and elevation: [foundations.md](docs/design-system/foundations.md#radius-and-elevation).

## Components

The catalog, with each component's status (Proposed, Approved, Built, Retiring): [components.md](docs/design-system/components.md). Code: `lib/gallformers_web/components/`. What a replacement must preserve: [inventory/](docs/design-system/inventory/). A new component, pattern or token needs approval before it is built.

## Do's and Don'ts

The five rules: [README.md](docs/design-system/README.md#five-rules). Words on screen: [content.md](docs/design-system/content.md). Mockups: [mockups.md](docs/design-system/mockups.md). `test/gallformers_web/design_system/conformance_test.exs` fails on off-system styling; fix the code, never raise the baseline.
