# Modules being replaced (Heartwood.Guardrails.Retirements).
#
# A task that builds a replacement adds its entry here first, as its failing
# test, and deletes the old module in the same change:
#
#     %{retire: GallformersWeb.Admin.ReviewLive.ItemRow,
#       replaced_by: GallformersWeb.Admin.ReviewLive.Review, why: "matter 6611"}
#
# The test fails while both modules exist. `why` cites the plan doc, PR or
# commit behind the replacement. Remove an entry once its old module is gone.
[]
