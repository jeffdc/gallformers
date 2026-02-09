---
description: Generate release notes from commits and create a GitHub Release
---

# Release

Create a GitHub Release with user-friendly release notes generated from commit messages.

## Prerequisites

### 1. Verify deploy pipeline completed

Before creating a release, confirm with the user that:

1. All changes have been **pushed to main**
2. **CI has passed** (the "CI V2" workflow)
3. **Deploy has completed** (the "Deploy V2" workflow, triggered automatically by CI)
4. The **deploy has been verified** (site is working)

Ask the user: "Has the deploy pipeline completed and been verified? (push → CI → deploy → verify)"

**Do not proceed until the user confirms.** Creating a release before deploy means the release won't match what's actually running in production.

### 2. Verify `gh` is authenticated

```bash
gh auth status
```

If not authenticated, tell the user to run `gh auth login` and stop.

## Steps

### 1. Determine the next tag

Tag format: `vYYYY.M.D` (first release of the day), `vYYYY.M.D.2` (second), `vYYYY.M.D.3`, etc.

```bash
gh release list --limit 10
```

- Parse today's date and check if any tags for today already exist
- If `vYYYY.M.D` exists, use `vYYYY.M.D.2`; if `.2` exists, use `.3`, etc.
- If no tag for today, use `vYYYY.M.D`

### 2. Collect commits since last release

Get the most recent release tag:

```bash
gh release list --limit 1
```

Then get commits since that tag:

```bash
git log <last-tag>..HEAD --oneline --no-merges
```

**Bootstrap case** (no prior releases): Use the last 20 commits and confirm the range with the user before proceeding.

**No commits since last release**: Tell the user there are no new commits. Offer to create a release with a manual note or abort.

### 3. Generate release notes

Read the commit messages and categorize each as:
- **User-facing**: New features, bug fixes, UI changes, content updates — anything a site visitor or contributor would notice
- **Technical**: Refactoring, dependency updates, CI changes, code cleanup — things only developers care about

Rewrite user-facing changes in **plain language** (not commit-message-ese). Group related commits together.

Use this template:

```markdown
## What's New
- [plain language description of user-facing changes]

## Technical Changes
- [developer-focused changes]

**Full Changelog**: https://github.com/jeffdc/gallformers/compare/<previous-tag>...<new-tag>
```

Omit a section if it would be empty.

### 4. Show draft and get approval

Present the full draft to the user:
- The tag name
- The release title (use the tag name, e.g., "v2026.2.6")
- The release notes body

**Wait for explicit approval before creating the release.** If the user wants changes, revise and show again.

### 5. Create the release

```bash
gh release create <tag> --title "<tag>" --notes "<notes>" --target main
```

Report the release URL to the user when done.
