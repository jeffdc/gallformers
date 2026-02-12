# Species Domain Type — Exploration Notes

**Date**: 2026-02-11
**Status**: Early exploration (not ready for implementation)
**Prerequisite**: Taxonomy Lineage type (see `2026-02-11-taxonomy-lineage-design.md`)

## Context

These are rough notes from a design conversation about modeling Species as a proper
domain type. This is a larger undertaking than Lineage and is captured here so the
thinking isn't lost.

## The Core Observation

Today `Species` is an Ecto schema — it maps to the `species` table. It has no domain
behavior; all behavior is spread across contexts (`Galls`, `Plants`, `Taxonomy`) and
utilities (`TaxonName`). The schema IS the domain model, which means the relational
DB structure dictates how the rest of the app thinks about species.

A Species in the domain is richer:
- It has a **name** with internal structure (genus, epithet, qualifier, unknown flag)
- It has a **lineage** (its position in the taxonomy tree)
- It has **behavior** — formatting rules, validation rules, name manipulation
- It comes in **two flavors** (Gall and Plant) with different traits and relationships

## The Two-Type Problem

A Plant IS a Species (`taxoncode = "plant"`). A Gall IS a Species (`taxoncode = "gall"`).
These are **peer concepts**, not a parent-child hierarchy. They share some structure
(name, lineage, aliases, sources) but differ in:

| Concern | Gall | Plant |
|---------|------|-------|
| Traits | morphology, detachability, alignment, walls, cells, color, shape, texture, location, abundance | (none currently — plants are hosts, not the focus) |
| Relationships | has hosts (plants) | has galls |
| Validation | undescribed lock (unknown genus → must be undescribed) | none |
| Creation workflow | undescribed flow, host association | simpler |
| Display | gall-specific detail pages | host-specific detail pages |

## OO Model (for thinking purposes)

```
Species (abstract or protocol)
  name: String
  lineage: Lineage
  behavior: epithet(), unknown_genus?(), italicize?()

Gall extends/implements Species
  traits: GallTraits
  hosts: [Plant]
  undescribed: boolean
  undescribed_locked?: (business rule)

Plant extends/implements Species
  galls: [Gall]
  common_names: [String]
```

## Elixir Translation Options

### Option A: Protocol

Define a `Species` protocol that both `Gall` and `Plant` implement.

```elixir
defprotocol Gallformers.Species do
  @doc "The species' taxonomic lineage"
  def lineage(species)

  @doc "The species' parsed name"
  def parsed_name(species)

  @doc "Is this a placeholder/unknown genus?"
  def unknown_genus?(species)
end

defmodule Gallformers.Galls.Gall do
  defstruct [:id, :name, :lineage, :traits, :hosts, :undescribed, ...]

  defimpl Gallformers.Species do
    def lineage(gall), do: gall.lineage
    def parsed_name(gall), do: TaxonName.parse(gall.name)
    def unknown_genus?(gall), do: Lineage.placeholder_genus?(gall.lineage)
  end
end
```

Pros: Clean polymorphism. Code that works with "any species" uses the protocol.
Cons: Protocols add indirection. May be overkill if few functions are truly polymorphic.

### Option B: Two separate structs, shared functions via module

```elixir
defmodule Gallformers.Galls.Gall do
  defstruct [:id, :name, :lineage, :traits, ...]
end

defmodule Gallformers.Plants.Plant do
  defstruct [:id, :name, :lineage, ...]
end

# Shared behavior lives in a plain module that pattern-matches
defmodule Gallformers.Species do
  def unknown_genus?(%{lineage: lineage}), do: Lineage.placeholder_genus?(lineage)
  def parsed_name(%{name: name}), do: TaxonName.parse(name)
end
```

Pros: Simpler. Duck-typing via map access means any struct with `:name` and `:lineage` works.
Cons: No compile-time enforcement that Gall and Plant satisfy the Species contract.

### Option C: Shared struct embedded in each

```elixir
defmodule Gallformers.Species.Identity do
  @moduledoc "The shared species identity: name + lineage + aliases + sources"
  defstruct [:id, :name, :lineage, :aliases, :sources]
end

defmodule Gallformers.Galls.Gall do
  defstruct [:identity, :traits, :hosts, :undescribed]
  # gall.identity.lineage, gall.identity.name
end
```

Pros: Shared structure is explicit. Easy to extract shared functions.
Cons: Deep nesting (`gall.identity.lineage.family.name`).

## What TaxonName Becomes

In any of these options, TaxonName's **parsing** stays as-is — it's the bootstrapping
step that extracts genus from a raw string before any domain types exist.

TaxonName's **behavior** (unknown_genus?, italicize_rank?, replace_genus, build) would
eventually migrate to become behavior on the Species domain type or on Lineage, since
those are the types callers actually have in hand when they need that behavior.

This migration can happen gradually — TaxonName keeps working, and the Species/Lineage
types delegate to it internally at first.

## Relationship to Ecto Schemas

The Species Ecto schema (`lib/gallformers/species/species.ex`) maps to the `species`
DB table. The domain types (Gall, Plant) would be separate from the Ecto schema.

Context functions become the translation layer:
- `Galls.get_gall(id)` queries the DB, loads the Ecto schema + associations, and
  returns a `%Gall{}` domain struct with a populated `%Lineage{}`
- `Plants.get_plant(id)` does the same for plants

This is the same pattern proposed for Lineage: query functions translate from the
relational model to the domain model.

## Open Questions

1. **How much shared structure?** Galls and Plants share name, lineage, aliases, sources.
   Is that enough to warrant a shared struct (Option C) or is duck-typing sufficient?

2. **Where do aliases and sources go?** They're currently separate contexts
   (`Species.get_aliases_for_species`, `Sources.has_sources?`). Do they become fields
   on the domain type, or stay as separate queries?

3. **Lazy vs eager loading?** A full `%Gall{}` with traits, hosts, lineage, aliases,
   and sources is a lot of data. Should some fields be lazy-loaded? Elixir doesn't
   have lazy fields natively, but Ecto's `%Ecto.Association.NotLoaded{}` pattern
   could be adapted.

4. **Forms vs display?** Admin forms need mutable state (changesets). Public pages
   need read-only display. Do both use the same domain type, or does the form use
   changesets while the public page uses domain structs?

5. **Migration path?** This touches nearly every LiveView and context. What's the
   incremental path? Probably: Lineage first (current work), then one context at a
   time (Galls first since it's the central domain), then Plants.

## Scope Boundary

This is explicitly OUT OF SCOPE for the Lineage work. Lineage is designed to be
neutral on the Species type question — `%Lineage{}` works regardless of whether
Species is one type, two types, or a protocol. Build Lineage first, then revisit
this exploration.
