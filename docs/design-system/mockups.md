# Mockups

A mockup should be made of the system it proposes, so that what is agreed can be built as drawn. Two ways, depending on who needs to see it.

## In the app: `/dev/mockups`

A mockup is a LiveView under `dev/gallformers_web/dev/mockups/` (the `dev/` directory compiles only in the dev environment), routed in the router's dev-only `/dev` scope as `/dev/mockups/<page>`. Add a `live` route for it in the `:dev_mockups` live_session. It uses the real components with real data, read through the existing read models, so it renders exactly as the built page would. To try a new template over a page's real behavior, copy the LiveView, keep its `mount` and events, and change only `render`.

There are no mockups at the moment: the home, ID, browse, places, rank, Gall, Host, Source, Articles and Keys pages they proposed are built. Each mockup opens with a "Mockup" notice saying what is real and what isn't.

- Use real content from the database or a fixture, never lorem ipsum.
- A mockup may sketch a component that doesn't exist yet, as plain markup in the mockup file with a `<!-- PROPOSED: name -->` comment. It must not be imported anywhere else. Building it for real starts with a catalog entry in [components.md](components.md).
- Mockups live outside `lib/`, so the conformance check doesn't scan them; still use tokens only, since the built page will copy the markup. Delete a mockup once its page is built.

## As a shared page (planned)

For a mockup someone reviews outside the running app (a published HTML page), `mix gallformers.design_system.export` writes one self-contained stylesheet (tokens, fonts as data URIs, base and component styles) to include in the page. Write the mockup's markup with the same classes the components produce (the style guide shows each component's markup), so the page looks like the app.

## What a mockup shows

- The first screen at 1440 × 900, and a phone at 390 wide.
- Real content, including the awkward cases: the longest name, the Gall with 14 Hosts, the empty state.
- Each new component or token it introduces, named, so it can go into the catalog.
