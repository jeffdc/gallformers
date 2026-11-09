# Modules being replaced (matter c800; see Gallformers.Guardrails.Retirements).
#
# A task that builds a replacement adds its entry here first, as its failing
# test, and deletes the old module in the same commit:
#
#     %{retire: GallformersWeb.Admin.ReviewLive.ItemRow,
#       replaced_by: GallformersWeb.Admin.ReviewLive.Review, matter: "6611"}
#
# The test fails while both modules exist. Remove an entry once its old
# module is gone.
[]
