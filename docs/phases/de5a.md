# Design: is all data a Fact?

## Why

Jeff, 2026-11-15: should every piece of data be tied to Facts, so that data handling, history and replay are unified? It may change what *One write path* builds (its inventory, its writers), what *Migration through the import* carries, and the interfaces the UI calls, so it is settled with Jeff before that work starts.

## The two candidate models

- **Everything is a Fact:** every piece of data, editorial data and plants included, is a Fact with a Source (Gallformers where there is no other). Every write is a package, and replay is only "apply the packages in order". Jeff: most of the objections are easily overcome, and this may have value as the primary approach.
- **Everything is a change; Facts are the changes that carry a Source:** every write goes through one envelope (recorded, replayed and audited the same way), and only knowledge with a Source is a Fact. Editorial changes carry no Source or stance.

## What to weigh

- Data with no natural Source: a Gall's Gallformers code, photo order, article text, key couplets, users.
- Plants: the plan says Gallformers is not an authority on plants, and keeps plant taxonomy editorial.
- Scale: about 1.08 million Host range rows, each read resolving its standing.
- The self-curating goal (plan doc, *Operating principles*): anomaly detection over uniform records.
- Kinds that may be worth making Facts on their own merits, such as plant ranges with WCVP as their Source.
- How it fits the other open design items in the plan doc: exactly which data is editorial, ranges, and audit.

## Done when

Jeff has decided the model, it is in the decision log, and the plan doc and the docs of *One write path*, *Migration through the import* and *The UI* say what it means for them (changes proposed to Jeff first).
