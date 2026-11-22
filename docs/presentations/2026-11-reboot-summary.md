# Gallformers Reimagined: A Summary

*Jeff Clark and Adam Kranz, November 2026*

This is a short write-up of the "Gallformers Reimagined" presentation we gave to curators on November 17, 2026. It covers the same ideas as the slides, plus a brief outline of the live demo at the end. To see the new site in action, watch the demo in the recording.

Everything described here is under active development. None of it is complete, and the final version may look different from what is described below.

## Why we are rethinking Gallformers

Gallformers' primary objective is to document the world of plant gall communities: not just the gall inducer, but the host, the inquilines, the parasitoids, the herbivores and everything else that lives in and around a gall.

Looking at what we have today:

- Gallformers has **931 sources**, but only **25%** of them are complete.
- Just **5 sources** are responsible for **51%** of the species.
- **641 galls** are backed only by Gallformers' own data, and **603** of those are undescribed.
- **53 sources** are not linked to a single species.

Four questions that come up that are hard to answer today:

1. How much have we drifted from the current state of knowledge?
2. How can we even know?
3. How would we fix it all?
4. How do we maintain it over time?

## Two decisions

**We document galls, not lookalikes.** Because our purpose is to document gall communities, we will no longer work to catalog non-galls or gall lookalikes. We fully acknowledge that the exact definition of a gall is imprecise, and that is OK.

**Every fact traces back to its source.** Every piece of information in the system about a gall community will be traceable to the source it came from.

## A better data model

Today, a gall *is* a species. That made it hard to describe anything beyond the simple case of one inducer making one gall. This is why we have so many, frankly ridiculous, naming rules to capture things like multi-generational gall wasps and the like.

In the new model, the **gall is the hub**. A gall has typed relationships to zero or more species: its inducer, its host, its parasitoids, its inquilines and so on. Two galls can be linked to each other too, for example as the alternate generations of the same inducer. This lets us describe a gall community the way it actually exists.

The full taxonomy can also be expressed. We no longer have to stop at family.

## Facts and sources

The core concept in the new system is the **Fact**. Every piece of data about a gall and about gall taxonomy must be backed by a Fact, and every Fact must be backed by a **Source**.

- **Facts are never edited or deleted.** A new Fact can override an older one, but the older one stays in the record. If a newer paper says something different from an older paper, the newer paper's Fact "wins" and is the one shown.
- **Gallformers is itself a source.** If you want to make an edit based on your own knowledge or observation, you make it under the authority of the Gallformers source.
- **Errors are corrected with new facts.** If an error turns up a curator adds a new Fact that corrects it, under the authority of the original source.

The result is a site where anyone can see where each piece of information came from and how it has changed over time.

## The hard part: getting facts out of sources

Pulling every Fact out of a paper at this level of detail is a lot of work. None of the sources we have today have been extracted this thoroughly, and doing it by hand would take thousands of hours.

The current admin tools make this worse. They are screen after screen of granular editing forms, and they would be nearly impossible to use with a Fact-based system. We need a complete rethink of how data gets into Gallformers, and that rethink includes the use of AI.

## Humans, code and AI

We think about the work as split between three kinds of worker, each doing what it is good at:

- **Humans** work however they work best. They are supported by the tools, and they remain responsible for what goes into the site.
- **Code** is deterministic. It does exactly what it is told. If we had unlimited resources (time, money, etc) code can solve just about any problem. If we were to solely write code to solve this issue of ingestion it would end up looking like an LLM.
- **Large language models (LLMs)** are probabilistic. They are not deterministic, and they need guardrails, but they are very good at a certain class of problems. The issue of reading and extracting Facts from a paper written in natural language is exactly the kind of problem they are very good at. In the author's opinion most of what LLMs are used for in the world today are silly or harmful.

## The LLM pipeline

Given a source you want to bring into Gallformers, you hand it to an LLM along with a package of instructions that Jeff has written. The LLM produces a structured data package that includes:

- **Taxonomic changes:** new species, splits, merges and renames.
- **Galls:** traits, ranges, hosts and so on.
- **Relationships:** inquilines, parasitoids, alternate generations and so on.

As it stands today, processing one source looks like this:

1. **Get the document.** A curator picks a source and finds its PDF or web page.
2. **Convert it.** The document is turned into clean text the model can read. Scanned papers are run through OCR (text recognition) again, and the better result is kept.
3. **Extract the taxonomy.** The LLM reads the instructions and the document and writes out the names: new species, splits, merges and renames.
4. **Extract the galls.** A second LLM pass writes out the galls, their traits, relationships and ranges. Every claim carries a quote from the source that supports it, and the model notes the judgement calls it made.
5. **Validate.** Code checks the output against the rules in the instructions. Nothing moves on until it passes.
6. **Check.** Two independent LLM checkers, using different models, review the extraction and object to anything they think is wrong.
7. **Respond.** The original LLM answers each objection, either by fixing the problem or by flagging it as a dispute for a curator to settle.
8. **Review.** The finished package goes into Gallformers, where a curator works through it on the source's page (names, galls, traits and Facts) and then approves or rejects it.

Steps 2 through 7 run unattended and take roughly 5 to 25 minutes per source.

We believe the quality of this pipeline is at least as good as a human pass over the same paper. It is not error-free, and humans still make the decisions. We do not want Gallformers to become an "AI slop" site.

## Ingestion and review

Instead of editing data screen by screen, curation becomes a review process:

| Step | Who |
|---|---|
| Generate a data package from a source with an LLM | LLM |
| Import the package into Gallformers | Code |
| Review it, and decide how to resolve conflicts and ambiguities | Human and code |
| Apply the package | Human |
| All changes land in the system with every Fact assigned to its source | Code |

Nothing changes on the site until a curator reviews the package and chooses to apply it.

## Tools for curators

The goal of the new admin is to make curation much easier, with a tools-first approach. Some examples:

- Taxonomy can be added or updated by importing inline from POWO/WCVP and iNaturalist.
- iNaturalist observations can be imported to add not just images but Facts, such as hosts and places.
- There is a single place to edit any given piece of data.
- Editing happens as close as possible to the public view of the data.
- Most edits are held until you decide you are done, and a single set of edits can span different areas of the data.

## What the demo showed

The presentation ended with a live demo of the work in progress. It covered:

- **A refreshed look:** overall style improvements across the site.
- **New Browse pages:** entirely new views of the data that were not possible before the new data model.
- **An enhanced search palette:** a faster, richer way to find and action anything on the site.
- **Facts on the public pages:** every user can see the Facts behind what a page shows, and the sources they come from.
- **Inline editing:** curators edit data right where it appears on the page.
- **A new admin layout:** the admin is reorganized around the new tools.
- **The import review process:** taking a data package from the LLM pipeline, reviewing it, resolving conflicts and applying it.

## Questions and feedback

Questions and feedback are welcome. Use the link in Discord to share your thoughts and concerns.
