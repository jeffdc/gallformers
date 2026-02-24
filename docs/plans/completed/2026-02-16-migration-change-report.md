# Migration Change Report

**Date**: 2026-02-16
**Migration**: `20260216152627_separate_undescribed_from_incomplete`
**Comparison**: post-migration (`priv/gallformers.sqlite`) vs pre-migration (`/tmp/gallformers-pre.sqlite`)

This migration separates undescribed status from data completeness by:
1. Populating `gallformers_code` on gall_traits from species name epithets
2. Fixing mislabeled `undescribed` flags
3. Enforcing `datacomplete` rules (requires sources, prohibits undescribed)
4. Converting `former_undescribed` aliases to `scientific`

---

## 1. Gallformers Codes Populated

**Total: 1365 species received a `gallformers_code`.**

| Species ID |                              Species Name                              |                  Gallformers Code                   |
|------------|------------------------------------------------------------------------|-----------------------------------------------------|
| 1749       | Acalitus iva-bead-gall                                                 | iva-bead-gall                                       |
| 5404       | Aceria b-sarothroides-leaf-blister                                     | b-sarothroides-leaf-blister                         |
| 3971       | Aceria f-pubescens-leaf-curl                                           | f-pubescens-leaf-curl                               |
| 3318       | Aceria l-pallidum-leaf-gall-organism                                   | l-pallidum-leaf-gall-organism                       |
| 2730       | Aceria near-campestricola                                              | near-campestricola                                  |
| 1357       | Ampelomyia v-mustangensis-lower-tube-gall                              | v-mustangensis-lower-tube-gall                      |
| 3355       | Ampelomyia v-tiliifolia-pubescent-conical-gall                         | v-tiliifolia-pubescent-conical-gall                 |
| 2265       | Ampelomyia vitis-large-cone-gall                                       | vitis-large-cone-gall                               |
| 1520       | Ampelovirus hackberry-island-chlorosis                                 | hackberry-island-chlorosis                          |
| 5620       | Amphibolips mexican-red-small-oak-apple (agamic)                       | mexican-red-small-oak-apple                         |
| 1137       | Amphibolips q-coccinea-like-cookii (agamic)                            | q-coccinea-like-cookii                              |
| 2233       | Amphibolips q-hemisphaerica-spindle-flower-gall (sexgen)               | q-hemisphaerica-spindle-flower-gall                 |
| 1140       | Amphibolips q-laurifolia-green-spindle (agamic)                        | q-laurifolia-green-spindle                          |
| 1224       | Amphibolips q-laurifolia-like-coelebs (sexgen)                         | q-laurifolia-like-coelebs                           |
| 4882       | Amphibolips q-marilandica-marbled-oak-apple (sexgen)                   | q-marilandica-marbled-oak-apple                     |
| 1150       | Amphibolips q-myrtifolia-like-acuminata (sexgen)                       | q-myrtifolia-like-acuminata                         |
| 2285       | Amphibolips q-nigra-brown-plum-gall (agamic)                           | q-nigra-brown-plum-gall                             |
| 4382       | Amphibolips q-nigra-speckled-bud-gall (agamic)                         | q-nigra-speckled-bud-gall                           |
| 4244       | Amphibolips q-phellos-bell-gall (sexgen)                               | q-phellos-bell-gall                                 |
| 1126       | Amphibolips q-phellos-large-plum-gall (agamic)                         | q-phellos-large-plum-gall                           |
| 1160       | Amphibolips q-phellos-leaf-spindle (sexgen)                            | q-phellos-leaf-spindle                              |
| 4157       | Amphibolips q-rubra-small-oak-apple (agamic)                           | q-rubra-small-oak-apple                             |
| 1145       | Amphibolips q-velutina-pointed-bud-gall (agamic)                       | q-velutina-pointed-bud-gall                         |
| 2599       | Andricus q-arizonica-woolly-russet-gall (agamic)                       | q-arizonica-woolly-russet-gall                      |
| 2030       | Andricus q-chrysolepis-oak-apple-gall (agamic)                         | q-chrysolepis-oak-apple-gall                        |
| 1984       | Andricus q-cornelius-mulleri-lobed-gall (agamic)                       | q-cornelius-mulleri-lobed-gall                      |
| 2566       | Andricus q-emoryi-crested-stem-gall                                    | q-emoryi-crested-stem-gall                          |
| 2303       | Andricus q-gambelii-pear-gall                                          | q-gambelii-pear-gall                                |
| 2028       | Andricus q-palmeri-oak-apple-gall (agamic)                             | q-palmeri-oak-apple-gall                            |
| 1041       | Andricus q-stellata-inside-mature-acorn-gall (agamic)                  | q-stellata-inside-mature-acorn-gall                 |
| 2604       | Andricus q-turbinella-succulent-gall (agamic)                          | q-turbinella-succulent-gall                         |
| 5438       | Antistrophus a-heterophylla-stem-swelling                              | a-heterophylla-stem-swelling                        |
| 4856       | Antistrophus l-juncea-collar-gall                                      | l-juncea-collar-gall                                |
| 4857       | Antistrophus l-juncea-spindle-gall                                     | l-juncea-spindle-gall                               |
| 4875       | Antistrophus m-lindleyi-basal-stem-gall                                | m-lindleyi-basal-stem-gall                          |
| 5437       | Antistrophus p-exigua-stem-swelling                                    | p-exigua-stem-swelling                              |
| 4201       | Antistrophus p-pauciflorus-stem-blister                                | p-pauciflorus-stem-blister                          |
| 4865       | Antistrophus s-astericus-cryptic-stem-gall                             | s-astericus-cryptic-stem-gall                       |
| 4409       | Antistrophus s-astericus-stem-swelling                                 | s-astericus-stem-swelling                           |
| 4864       | Antistrophus s-dentatum-cryptic-stem-gall                              | s-dentatum-cryptic-stem-gall                        |
| 4860       | Antistrophus s-gracile-flower-gall                                     | s-gracile-flower-gall                               |
| 4861       | Antistrophus s-integrifolium-flower-gall                               | s-integrifolium-flower-gall                         |
| 5439       | Antistrophus s-integrifolium-leaf-blister                              | s-integrifolium-leaf-blister                        |
| 4867       | Antistrophus s-integrifolium-stem-cluster-gall                         | s-integrifolium-stem-cluster-gall                   |
| 4868       | Antistrophus s-laciniatum-cryptic-leaf-gall                            | s-laciniatum-cryptic-leaf-gall                      |
| 1438       | Antistrophus s-perfoliatum-stem-swelling                               | s-perfoliatum-stem-swelling                         |
| 1436       | Antistrophus s-terebinthinaceum-seed-gall                              | s-terebinthinaceum-seed-gall                        |
| 5615       | Antron q-obtusata-wrinkled-sphere                                      | q-obtusata-wrinkled-sphere                          |
| 3233       | Asphondylia a-hymenelytra-pom-pom-bud-gall-midge                       | a-hymenelytra-pom-pom-bud-gall-midge                |
| 5737       | Asphondylia a-hymenelytra-slight-leaf-blade-deformity                  | a-hymenelytra-slight-leaf-blade-deformity           |
| 3328       | Asphondylia a-salsola-medusa-gall-midge                                | a-salsola-medusa-gall-midge                         |
| 5282       | Asphondylia a-salsola-pediceled-bud-gall                               | a-salsola-pediceled-bud-gall                        |
| 5283       | Asphondylia a-salsola-sessile-bud-gall                                 | a-salsola-sessile-bud-gall                          |
| 2212       | Asphondylia a-salsola-smooth-bud-gall                                  | a-salsola-smooth-bud-gall                           |
| 2213       | Asphondylia a-salsola-woolly-bud-gall                                  | a-salsola-woolly-bud-gall                           |
| 5207       | Asphondylia b-juncea-flower-head-gall                                  | b-juncea-flower-head-gall                           |
| 5202       | Asphondylia b-pilularis-potatolike-swelling                            | b-pilularis-potatolike-swelling                     |
| 5386       | Asphondylia b-vulgaris-bud-gall                                        | b-vulgaris-bud-gall                                 |
| 4044       | Asphondylia c-annuum-bud-flower-fruit-gall                             | c-annuum-bud-flower-fruit-gall                      |
| 5218       | Asphondylia c-coelestinum-damaged-seed-head                            | c-coelestinum-damaged-seed-head                     |
| 4806       | Asphondylia c-jepsonii-round-bud-gall                                  | c-jepsonii-round-bud-gall                           |
| 3037       | Asphondylia c-palmata-succulent-gall                                   | c-palmata-succulent-gall                            |
| 5873       | Asphondylia c-pumila-pod-gall                                          | c-pumila-pod-gall                                   |
| 5709       | Asphondylia c-velutinus-spindle-shaped-flower-gall                     | c-velutinus-spindle-shaped-flower-gall              |
| 3324       | Asphondylia c-velutinus-vein-gall-midge                                | c-velutinus-vein-gall-midge                         |
| 4673       | Asphondylia d-aurantiacus-seed-pod-gall                                | d-aurantiacus-seed-pod-gall                         |
| 4022       | Asphondylia d-erecta-enlarged-aborted-flowers                          | d-erecta-enlarged-aborted-flowers                   |
| 4274       | Asphondylia e-californicum-flower-gall                                 | e-californicum-flower-gall                          |
| 5405       | Asphondylia e-caroliniana-elongated-bud-rosette-gall                   | e-caroliniana-elongated-bud-rosette-gall            |
| 5222       | Asphondylia e-hieraciifolius-flower-head-gall                          | e-hieraciifolius-flower-head-gall                   |
| 2176       | Asphondylia f-californica-flower-gall                                  | f-californica-flower-gall                           |
| 2209       | Asphondylia f-splendens-aborted-bud-gall                               | f-splendens-aborted-bud-gall                        |
| 5234       | Asphondylia gnaphalium-stem-swelling                                   | gnaphalium-stem-swelling                            |
| 5235       | Asphondylia gnaphalium-white-woolly-bud-gall                           | gnaphalium-white-woolly-bud-gall                    |
| 5242       | Asphondylia h-microcephalum-aborted-disc-floret                        | h-microcephalum-aborted-disc-floret                 |
| 5396       | Asphondylia ipomoea-swollen-flower                                     | ipomoea-swollen-flower                              |
| 4020       | Asphondylia l-camara-enlarged-aborted-flowers                          | l-camara-enlarged-aborted-flowers                   |
| 2204       | Asphondylia l-tridentata-scimitar-leaf-gall                            | l-tridentata-scimitar-leaf-gall                     |
| 5958       | Asphondylia ludwigia-distorted-pod                                     | ludwigia-distorted-pod                              |
| 5888       | Asphondylia n-glandulosa-rough-persistent-flower-bud-gall              | n-glandulosa-rough-persistent-flower-bud-gall       |
| 5332       | Asphondylia nasturtium-swollen-flower                                  | nasturtium-swollen-flower                           |
| 5289       | Asphondylia p-baccharis-seed-head-gall                                 | p-baccharis-seed-head-gall                          |
| 3279       | Asphondylia p-gracile-stem-swelling                                    | p-gracile-stem-swelling                             |
| 4131       | Asphondylia p-keyense-aborted-pod                                      | p-keyense-aborted-pod                               |
| 2716       | Asphondylia p-praecox-swollen-fruit-gall                               | p-praecox-swollen-fruit-gall                        |
| 5369       | Asphondylia palafoxia-globular-bud-gall                                | palafoxia-globular-bud-gall                         |
| 5890       | Asphondylia r-senna-deformed-pod                                       | r-senna-deformed-pod                                |
| 5817       | Asphondylia s-angustifolia-aborted-flower-bud                          | s-angustifolia-aborted-flower-bud                   |
| 5793       | Asphondylia s-arguta-bud-rosette-gall                                  | s-arguta-bud-rosette-gall                           |
| 2896       | Asphondylia s-bicolor-bud-rosette                                      | s-bicolor-bud-rosette                               |
| 4950       | Asphondylia s-chapmanii-bud-rosette-gall                               | s-chapmanii-bud-rosette-gall                        |
| 5770       | Asphondylia s-fistulosa-larger-bud-rosette-gall                        | s-fistulosa-larger-bud-rosette-gall                 |
| 5295       | Asphondylia s-flaccidus-swollen-bud-gall                               | s-flaccidus-swollen-bud-gall                        |
| 5763       | Asphondylia s-gillmanii-bud-rosette-gall                               | s-gillmanii-bud-rosette-gall                        |
| 5661       | Asphondylia s-latissimifolia-terminal-rosette                          | s-latissimifolia-terminal-rosette                   |
| 5768       | Asphondylia s-leavenworthii-bud-rosette-gall                           | s-leavenworthii-bud-rosette-gall                    |
| 5673       | Asphondylia s-mellifera-leaf-snap-gall                                 | s-mellifera-leaf-snap-gall                          |
| 5771       | Asphondylia s-mexicana-leaf-snap                                       | s-mexicana-leaf-snap                                |
| 3051       | Asphondylia s-nemoralis-leaf-snap                                      | s-nemoralis-leaf-snap                               |
| 4951       | Asphondylia s-odora-aggregated-bud-rosette-gall                        | s-odora-aggregated-bud-rosette-gall                 |
| 5796       | Asphondylia s-odora-small-bud-rosette-gall                             | s-odora-small-bud-rosette-gall                      |
| 4060       | Asphondylia s-rigida-bud-rosette-gall                                  | s-rigida-bud-rosette-gall                           |
| 3244       | Asphondylia s-sempervirens-bud-rosette-gall                            | s-sempervirens-bud-rosette-gall                     |
| 5790       | Asphondylia s-speciosa-bud-rosette-gall                                | s-speciosa-bud-rosette-gall                         |
| 5197       | Asphondylia s-subulatum-apical-bud-gall                                | s-subulatum-apical-bud-gall                         |
| 3052       | Asphondylia s-tortifolia-bud-rosette-cluster                           | s-tortifolia-bud-rosette-cluster                    |
| 4643       | Asphondylia s-uliginosa-bud-rosette-gall                               | s-uliginosa-bud-rosette-gall                        |
| 5117       | Asphondylia s-ulmifolia-bud-rosette-gall                               | s-ulmifolia-bud-rosette-gall                        |
| 5849       | Asphondylia v-alternifolia-bud-swelling                                | v-alternifolia-bud-swelling                         |
| 4662       | Asteromyia a-carolinianus-asteromyia-like-blister                      | a-carolinianus-asteromyia-like-blister              |
| 5206       | Asteromyia b-douglasii-leaf-blister                                    | b-douglasii-leaf-blister                            |
| 5124       | Asteromyia b-halimifolia-spot-gall                                     | b-halimifolia-spot-gall                             |
| 5203       | Asteromyia b-pteronioides-blister-gall-species-two                     | b-pteronioides-blister-gall-species-two             |
| 5204       | Asteromyia b-salicina-blister-gall-species-three                       | b-salicina-blister-gall-species-three               |
| 4664       | Asteromyia c-ericoides-asteromyia-like-blister                         | c-ericoides-asteromyia-like-blister                 |
| 5545       | Asteromyia c-filaginifolia-leaf-blister                                | c-filaginifolia-leaf-blister                        |
| 4687       | Asteromyia h-squarrosa-leaf-spot                                       | h-squarrosa-leaf-spot                               |
| 4685       | Asteromyia h-subaxillaris-asteromyia-like-blister                      | h-subaxillaris-asteromyia-like-blister              |
| 5764       | Asteromyia s-rigida-midrib-gall                                        | s-rigida-midrib-gall                                |
| 4660       | Asteromyia x-tortifolia-asteromyia-like-blister                        | x-tortifolia-asteromyia-like-blister                |
| 2606       | Atrusca q-turbinella-rusty-oak-apple (agamic)                          | q-turbinella-rusty-oak-apple                        |
| 5421       | Aulacidea h-albiflorum-leaf-midrib-swelling                            | h-albiflorum-leaf-midrib-swelling                   |
| 4210       | Aulacidea l-canadensis-crown-gall                                      | l-canadensis-crown-gall                             |
| 4896       | Belonocnema q-brandegeei-midrib-gall                                   | q-brandegeei-midrib-gall                            |
| 1525       | Betacarmovirus turnip-crinkle-virus                                    | turnip-crinkle-virus                                |
| 2979       | Blaesodiplosis a-alnifolia-curled-tongue-gall                          | a-alnifolia-curled-tongue-gall                      |
| 2978       | Blaesodiplosis a-alnifolia-mouth-gall                                  | a-alnifolia-mouth-gall                              |
| 2980       | Blaesodiplosis a-alnifolia-skinny-mitten-gall                          | a-alnifolia-skinny-mitten-gall                      |
| 2981       | Blaesodiplosis a-alnifolia-thorn-gall                                  | a-alnifolia-thorn-gall                              |
| 2982       | Blaesodiplosis a-arborea-bead-gall                                     | a-arborea-bead-gall                                 |
| 2983       | Blaesodiplosis a-arborea-button-gall                                   | a-arborea-button-gall                               |
| 2977       | Blaesodiplosis a-arborea-spotted-fan-gall                              | a-arborea-spotted-fan-gall                          |
| 4620       | Blaesodiplosis a-utahensis-balloon-gall                                | a-utahensis-balloon-gall                            |
| 5511       | Blaesodiplosis a-utahensis-hairy-protuberances                         | a-utahensis-hairy-protuberances                     |
| 623        | Blaesodiplosis amelanchier-hook-gall                                   | amelanchier-hook-gall                               |
| 4080       | Blaesodiplosis r-nutkana-fuzzy-vein-swellings                          | r-nutkana-fuzzy-vein-swellings                      |
| 5950       | Bruggmannia pisonia-woody-convex-leaf-gall                             | pisonia-woody-convex-leaf-gall                      |
| 1038       | Callirhytis q-alba-inside-mature-acorn-gall (agamic)                   | q-alba-inside-mature-acorn-gall                     |
| 1120       | Callirhytis q-ilicifolia-pip-gall (agamic)                             | q-ilicifolia-pip-gall                               |
| 1124       | Callirhytis q-marilandica-like-fructuosa (agamic)                      | q-marilandica-like-fructuosa                        |
| 3295       | Callirhytis q-rubra-red-pip-gall (agamic)                              | q-rubra-red-pip-gall                                |
| 1065       | Callirhytis q-stellata-cells-under-bark (agamic)                       | q-stellata-cells-under-bark                         |
| 1080       | Callirhytis q-stellata-pentagonal-cluster (agamic)                     | q-stellata-pentagonal-cluster                       |
| 3241       | Cameraria central-frass-spot                                           | central-frass-spot                                  |
| 4897       | Cembrotia p-edulis-enlarged-needle-sheath                              | p-edulis-enlarged-needle-sheath                     |
| 3877       | Cembrotia p-edulis-needle-lip-gall                                     | p-edulis-needle-lip-gall                            |
| 5969       | Cembrotia p-monophylla-second-needle-gall                              | p-monophylla-second-needle-gall                     |
| 5970       | Cembrotia p-monophylla-stunted-needle-gall                             | p-monophylla-stunted-needle-gall                    |
| 2763       | Chamaediplosis c-forbesii-golden-goblet-gall                           | c-forbesii-golden-goblet-gall                       |
| 2237       | Chamaediplosis h-macrocarpa-tiny-cup-gall                              | h-macrocarpa-tiny-cup-gall                          |
| 5179       | Contarinia a-androsaemifolium-enlarged-flower-bud                      | a-androsaemifolium-enlarged-flower-bud              |
| 5181       | Contarinia a-incarnata-rolled-leaf-or-swollen-midrib-fold              | a-incarnata-rolled-leaf-or-swollen-midrib-fold      |
| 541        | Contarinia a-negundo-bead-gall                                         | a-negundo-bead-gall                                 |
| 2342       | Contarinia a-rubrum-marginal-leaf-fold                                 | a-rubrum-marginal-leaf-fold                         |
| 4301       | Contarinia a-syriaca-swollen-flower-gall                               | a-syriaca-swollen-flower-gall                       |
| 2747       | Contarinia c-americana-enlarged-bud-gall                               | c-americana-enlarged-bud-gall-contarinia            |
| 3006       | Contarinia c-dentata-leaf-vein-fold                                    | c-dentata-leaf-vein-fold                            |
| 3325       | Contarinia c-integerrimus-midrib-fold-gall-midge                       | c-integerrimus-midrib-fold-gall-midge               |
| 2191       | Contarinia c-verrucosus-leaf-pouch-gall                                | c-verrucosus-leaf-pouch-gall                        |
| 2930       | Contarinia e-repens-spikelet-gall                                      | e-repens-spikelet-gall                              |
| 5954       | Contarinia f-pennsylvanica-swollen-seed                                | f-pennsylvanica-swollen-seed                        |
| 3973       | Contarinia f-pubescens-globular-bud-gall                               | f-pubescens-globular-bud-gall                       |
| 4066       | Contarinia g-asprellum-aborted-flower-bud                              | g-asprellum-aborted-flower-bud                      |
| 5881       | Contarinia g-tinctoria-folded-leaflet                                  | g-tinctoria-folded-leaflet                          |
| 5898       | Contarinia h-virginiana-circular-leaf-blister                          | h-virginiana-circular-leaf-blister                  |
| 5473       | Contarinia h-virginiana-vein-gall                                      | h-virginiana-vein-gall                              |
| 5902       | Contarinia j-cinerea-folded-swollen-leaflets                           | j-cinerea-folded-swollen-leaflets                   |
| 5918       | Contarinia l-benzoin-leaf-roll-contarinia                              | l-benzoin-leaf-roll-contarinia                      |
| 3317       | Contarinia l-cooperi-cabbage-gall-midge                                | l-cooperi-cabbage-gall-midge                        |
| 2205       | Contarinia l-tridentata-clasping-leaf-gall                             | l-tridentata-clasping-leaf-gall                     |
| 5376       | Contarinia lonicera-lobulate-swollen-bud                               | lonicera-lobulate-swollen-bud                       |
| 5932       | Contarinia m-virginiana-leaf-spot                                      | m-virginiana-leaf-spot                              |
| 2339       | Contarinia n-sylvatica-swollen-flower                                  | n-sylvatica-swollen-flower                          |
| 2901       | Contarinia o-tesota-swollen-leaflet-gall                               | o-tesota-swollen-leaflet-gall                       |
| 4097       | Contarinia p-americana-leafy-bud-gall                                  | p-americana-leafy-bud-gall                          |
| 2309       | Contarinia p-opulifolius-bulb-gall                                     | p-opulifolius-bulb-gall                             |
| 2608       | Contarinia p-opulifolius-red-bead-gall                                 | p-opulifolius-red-bead-gall                         |
| 4122       | Contarinia p-opulifolius-vein-swelling                                 | p-opulifolius-vein-swelling                         |
| 3997       | Contarinia p-tremuloides-stem-gall                                     | p-tremuloides-stem-gall                             |
| 4095       | Contarinia p-tridentata-deformed-flower-receptacle                     | p-tridentata-deformed-flower-receptacle             |
| 4096       | Contarinia p-tridentata-filamentous-node-gall                          | p-tridentata-filamentous-node-gall                  |
| 4741       | Contarinia q-chrysolepis-leaf-edge-roll                                | q-chrysolepis-leaf-edge-roll                        |
| 1191       | Contarinia q-palustris-male-catkin-larvae                              | q-palustris-male-catkin-larvae                      |
| 1206       | Contarinia q-palustris-vein-fold-gall                                  | q-palustris-vein-fold-gall                          |
| 1192       | Contarinia q-rubra-aborted-bud                                         | q-rubra-aborted-bud                                 |
| 1208       | Contarinia q-vaccinifolia-leaf-edge-roll                               | q-vaccinifolia-leaf-edge-roll                       |
| 4078       | Contarinia r-allegheniensis-aborted-flower-buds                        | r-allegheniensis-aborted-flower-buds                |
| 4082       | Contarinia r-carolina-folded-terminal-leaflet-contarinia               | r-carolina-folded-terminal-leaflet-contarinia       |
| 3010       | Contarinia s-albidum-leaf-spot                                         | s-albidum-leaf-spot                                 |
| 5939       | Contarinia s-coccinea-bud-gall                                         | s-coccinea-bud-gall                                 |
| 4068       | Contarinia s-douglasii-leafy-rosette-gall                              | s-douglasii-leafy-rosette-gall                      |
| 3234       | Contarinia s-greggii-leaflet-gall-midge                                | s-greggii-leaflet-gall-midge                        |
| 2319       | Contarinia s-greggii-tube-gall                                         | s-greggii-tube-gall                                 |
| 4049       | Contarinia s-marilandica-distorted-flower-bud                          | s-marilandica-distorted-flower-bud                  |
| 5170       | Contarinia t-radicans-curled-leaf-margin-contarinia                    | t-radicans-curled-leaf-margin-contarinia            |
| 5378       | Contarinia v-cassinoides-marginal-leaf-roll                            | v-cassinoides-marginal-leaf-roll                    |
| 5857       | Contarinia vaccinium-leaf-spot                                         | vaccinium-leaf-spot                                 |
| 3242       | Cristulariella quercus-concentric-spot                                 | quercus-concentric-spot                             |
| 1366       | Cynips q-kelloggii-acorn-cup-gall-wasp                                 | q-kelloggii-acorn-cup-gall-wasp                     |
| 2954       | Dasineura a-canescens-organ-pipe-gall                                  | a-canescens-organ-pipe-gall                         |
| 2771       | Dasineura a-grandis-aborted-seed-gall                                  | a-grandis-aborted-seed-gall                         |
| 4529       | Dasineura a-rubra-flower-gall                                          | a-rubra-flower-gall                                 |
| 2343       | Dasineura a-rubrum-expanded-veins                                      | a-rubrum-expanded-veins                             |
| 3149       | Dasineura alnus-fold-gall                                              | alnus-fold-gall                                     |
| 5865       | Dasineura astragalus-petiole-swelling                                  | astragalus-petiole-swelling                         |
| 5443       | Dasineura c-americana-enlarged-bud-gall                                | c-americana-enlarged-bud-gall-dasineura             |
| 5826       | Dasineura c-pensylvanica-deformed-fruit-gall                           | c-pensylvanica-deformed-fruit-gall                  |
| 5328       | Dasineura cardamine-irregularly-conical-flowers                        | cardamine-irregularly-conical-flowers               |
| 4510       | Dasineura d-umbellata-hairy-bud-gall                                   | d-umbellata-hairy-bud-gall                          |
| 6018       | Dasineura e-fendleri-swollen-bracts-on-terminal-bud                    | e-fendleri-swollen-bracts-on-terminal-bud           |
| 5955       | Dasineura fraxinus-folded-leaflets-swollen-midrib                      | fraxinus-folded-leaflets-swollen-midrib             |
| 4124       | Dasineura h-discolor-swollen-vein-fold                                 | h-discolor-swollen-vein-fold                        |
| 5903       | Dasineura j-nigra-folded-swollen-leaflets                              | j-nigra-folded-swollen-leaflets                     |
| 5919       | Dasineura l-benzoin-leaf-roll-dasineura                                | l-benzoin-leaf-roll-dasineura                       |
| 4526       | Dasineura l-involucrata-roll-gall                                      | l-involucrata-roll-gall                             |
| 5885       | Dasineura lespedeza-rolled-leaflet                                     | lespedeza-rolled-leaflet                            |
| 2264       | Dasineura n-densiflorus-tanoak-flower-gall                             | n-densiflorus-tanoak-flower-gall                    |
| 2261       | Dasineura n-densiflorus-tanoak-fuzzy-gall                              | n-densiflorus-tanoak-fuzzy-gall                     |
| 4959       | Dasineura o-cerasiformis-leaf-rollup                                   | o-cerasiformis-leaf-rollup                          |
| 5827       | Dasineura p-aquilinum-leaf-edge-roll                                   | p-aquilinum-leaf-edge-roll                          |
| 4123       | Dasineura p-opulifolius-deformed-seed                                  | p-opulifolius-deformed-seed                         |
| 3151       | Dasineura p-trichocarpa-big-bud-gall                                   | p-trichocarpa-big-bud-gall                          |
| 4100       | Dasineura p-virginiana-simple-leaf-fold                                | p-virginiana-simple-leaf-fold                       |
| 2019       | Dasineura q-chrysolepis-purse-gall                                     | q-chrysolepis-purse-gall                            |
| 4081       | Dasineura r-carolina-folded-terminal-leaflet-dasineura                 | r-carolina-folded-terminal-leaflet-dasineura        |
| 4083       | Dasineura r-carolina-large-rosette-gall                                | r-carolina-large-rosette-gall                       |
| 2612       | Dasineura r-parviflorus-fold-gall                                      | r-parviflorus-fold-gall                             |
| 5452       | Dasineura r-sanguineum-furled-leaf-with-enlarged-veins                 | r-sanguineum-furled-leaf-with-enlarged-veins        |
| 4069       | Dasineura s-alba-marginal-roll                                         | s-alba-marginal-roll                                |
| 4645       | Dasineura s-californica-blistered-bud-rosette                          | s-californica-blistered-bud-rosette                 |
| 5762       | Dasineura s-gillmanii-swollen-petiole-cluster                          | s-gillmanii-swollen-petiole-cluster                 |
| 4556       | Dasineura s-mollis-roll-gall                                           | s-mollis-roll-gall                                  |
| 5767       | Dasineura s-odora-wrinkled-bud-gall                                    | s-odora-wrinkled-bud-gall                           |
| 5169       | Dasineura t-radicans-curled-leaf-margin-dasineura                      | t-radicans-curled-leaf-margin-dasineura             |
| 4023       | Dasineura u-dioica-ovoid-leaf-gall                                     | u-dioica-ovoid-leaf-gall                            |
| 4040       | Dasineura u-rubra-enlarged-stem-bud                                    | u-rubra-enlarged-stem-bud                           |
| 1748       | Dasineura v-cinerea-hook-gall                                          | v-cinerea-hook-gall                                 |
| 5851       | Dasineura v-stamineum-reddened-enlarged-fruit                          | v-stamineum-reddened-enlarged-fruit                 |
| 5478       | Diastrophus f-vesca-swollen-runner                                     | f-vesca-swollen-runner                              |
| 5189       | Diastrophus h-daucifolia-stem-swelling                                 | h-daucifolia-stem-swelling                          |
| 4871       | Diastrophus p-congesta-stem-gall                                       | p-congesta-stem-gall                                |
| 4884       | Diastrophus r-hispidus-like-radicum                                    | r-hispidus-like-radicum                             |
| 5319       | Diastrophus r-trivialis-root-gall                                      | r-trivialis-root-gall                               |
| 4275       | Diplolepis r-carolina-like-nebulosa                                    | r-carolina-like-nebulosa                            |
| 2011       | Disholandricus q-chrysolepis-potato-stem-gall (agamic)                 | q-chrysolepis-potato-stem-gall                      |
| 2434       | Disholcaspis q-arizonica-witch-hat-gall (agamic)                       | q-arizonica-witch-hat-gall                          |
| 1056       | Disholcaspis q-breviloba-rugose-bullet-gall (agamic)                   | q-breviloba-rugose-bullet-gall                      |
| 4189       | Disholcaspis q-havardii-urchin-gall (agamic)                           | q-havardii-urchin-gall                              |
| 4268       | Disholcaspis q-laceyi-bullet-gall (agamic)                             | q-laceyi-bullet-gall                                |
| 1063       | Disholcaspis q-margaretiae-bullet-gall (agamic)                        | q-margaretiae-bullet-gall                           |
| 1057       | Disholcaspis q-michauxii-bullet-gall (agamic)                          | q-michauxii-bullet-gall                             |
| 4162       | Disholcaspis q-oglethorpensis-bullet-gall (agamic)                     | q-oglethorpensis-bullet-gall                        |
| 4308       | Disholcaspis q-oleoides-like-quercusvirens (agamic)                    | q-oleoides-like-quercusvirens                       |
| 2529       | Disholcaspis q-turbinella-conical-stem-gall (agamic)                   | q-turbinella-conical-stem-gall                      |
| 2580       | Disholcaspis q-turbinella-round-top-gall (agamic)                      | q-turbinella-round-top-gall                         |
| 2012       | Disholcaspis q-vacciniifolia-lens-gall (agamic)                        | q-vacciniifolia-lens-gall                           |
| 4242       | Disholcaspis q-vaseyana-peach-gall (agamic)                            | q-vaseyana-peach-gall                               |
| 1985       | Druon brown-eye-gall                                                   | brown-eye-gall                                      |
| 2442       | Druon q-arizonica-woolly-midrib-cluster (agamic)                       | q-arizonica-woolly-midrib-cluster                   |
| 4886       | Druon q-muehlenbergii-tuft-gall (agamic)                               | q-muehlenbergii-tuft-gall                           |
| 4217       | Druon q-potosina-like-flocci (agamic)                                  | q-potosina-like-flocci                              |
| 1437       | Dryocosmus q-imbricaria-glob-free-rolling-cell (sexgen)                | q-imbricaria-glob-free-rolling-cell                 |
| 4266       | Dryocosmus q-imbricaria-sack-gall (sexgen)                             | q-imbricaria-sack-gall                              |
| 2232       | Dryocosmus q-pumila-fuzzy-hemispherical-leaf-gall (sexgen)             | q-pumila-fuzzy-hemispherical-leaf-gall              |
| 5225       | Emaravirus p-florida-witches-broom                                     | p-florida-witches-broom                             |
| 1945       | Eriophyes arizona-red-oak-erineum                                      | arizona-red-oak-erineum                             |
| 4094       | Eriophyes u-thomasii-frost-gall                                        | u-thomasii-frost-gall                               |
| 4178       | Erythres q-phellos-bud-rosette (agamic)                                | q-phellos-bud-rosette                               |
| 3327       | Eugnosta a-salsola-stem-gall-moth                                      | a-salsola-stem-gall-moth                            |
| 3683       | Euura s-alaxensis-fuzzy-gall                                           | s-alaxensis-fuzzy-gall                              |
| 3898       | Euura s-amygdaloides-like-proxima                                      | s-amygdaloides-like-proxima                         |
| 3626       | Euura s-barclayi-smooth-petiole-gall                                   | s-barclayi-smooth-petiole-gall                      |
| 3679       | Euura s-bebbiana-hairy-gall                                            | s-bebbiana-hairy-gall                               |
| 3680       | Euura s-bebbiana-like-pomum                                            | s-bebbiana-like-pomum                               |
| 3664       | Euura s-breweri-pilose-gall                                            | s-breweri-pilose-gall                               |
| 3673       | Euura s-eastwoodiae-peach-gall                                         | s-eastwoodiae-peach-gall                            |
| 3900       | Euura s-exigua-midrib-gall                                             | s-exigua-midrib-gall                                |
| 3901       | Euura s-fragilis-shoot-gall                                            | s-fragilis-shoot-gall                               |
| 3714       | Euura s-glauca-like-cosensii                                           | s-glauca-like-cosensii                              |
| 3681       | Euura s-hookeriana-apple-gall                                          | s-hookeriana-apple-gall                             |
| 4166       | Euura s-irrorata-irregular-stem-swelling                               | s-irrorata-irregular-stem-swelling                  |
| 4652       | Euura s-irrorata-midrib-sack-gall                                      | s-irrorata-midrib-sack-gall                         |
| 3674       | Euura s-lasiandra-apple-gall                                           | s-lasiandra-apple-gall                              |
| 3656       | Euura s-lasiandra-like-proxima                                         | s-lasiandra-like-proxima                            |
| 3625       | Euura s-lasiandra-petiole-gall                                         | s-lasiandra-petiole-gall                            |
| 3899       | Euura s-lasiolepis-near-pacifica                                       | s-lasiolepis-near-pacifica                          |
| 3655       | Euura s-lemmonii-bud-gall                                              | s-lemmonii-bud-gall                                 |
| 3672       | Euura s-prolixa-spotted-leaf-gall                                      | s-prolixa-spotted-leaf-gall                         |
| 3903       | Euura s-scouleriana-bud-gall                                           | s-scouleriana-bud-gall                              |
| 2193       | Euura s-scouleriana-fuzzy-gall                                         | s-scouleriana-fuzzy-gall                            |
| 3663       | Euura s-sitchensis-apple-gall                                          | s-sitchensis-apple-gall                             |
| 3631       | Euura s-sitchensis-potato-gall                                         | s-sitchensis-potato-gall                            |
| 3671       | Euura s-tracyi-apple-gall                                              | s-tracyi-apple-gall                                 |
| 3665       | Euura salix-petiole-gall                                               | salix-petiole-gall                                  |
| 3635       | Euura salix-woolly-gall                                                | salix-woolly-gall                                   |
| 3657       | Euura type-ii-leaf-gall                                                | type-ii-leaf-gall                                   |
| 3659       | Euura type-iii-leaf-gall                                               | type-iii-leaf-gall                                  |
| 3660       | Euura type-iv-leaf-gall                                                | type-iv-leaf-gall                                   |
| 3661       | Euura type-v-leaf-gall                                                 | type-v-leaf-gall                                    |
| 3662       | Euura type-vi-leaf-gall                                                | type-vi-leaf-gall                                   |
| 5667       | Exobasidium a-menziesii-fungal-leaf-blister                            | a-menziesii-fungal-leaf-blister                     |
| 4548       | Exobasidium a-spp-whole-shoot-discoloration                            | a-spp-whole-shoot-discoloration                     |
| 5398       | Exobasidium florifolium-nom-prov                                       | florifolium-nom-prov                                |
| 5114       | Exobasidium g-baccata-from-taxon-split                                 | g-baccata-from-taxon-split                          |
| 5986       | Exobasidium r-canescens-galls-from-taxon-split                         | r-canescens-galls-from-taxon-split                  |
| 6003       | Exobasidium r-groenlandicum-galls-from-taxon-split                     | r-groenlandicum-galls-from-taxon-split              |
| 5533       | Exobasidium r-macrophyllum-galls-from-taxon-split                      | r-macrophyllum-galls-from-taxon-split               |
| 5068       | Exobasidium r-menziesii-galls-from-taxon-split                         | r-menziesii-galls-from-taxon-split                  |
| 4549       | Exobasidium v-ovatum-galls-from-taxon-split                            | v-ovatum-galls-from-taxon-split                     |
| 2447       | Feron q-arizonica-pointed-leaf-edge-cell (sexgen)                      | q-arizonica-pointed-leaf-edge-cell                  |
| 2456       | Feron q-arizonica-prolonged-vein (sexgen)                              | q-arizonica-prolonged-vein                          |
| 1995       | Feron q-garryana-bowl-gall                                             | q-garryana-bowl-gall                                |
| 5991       | Feron q-garryana-hair-stalk-gall (sexgen)                              | q-garryana-hair-stalk-gall                          |
| 1990       | Feron q-garryana-plate-gall                                            | q-garryana-plate-gall                               |
| 5665       | Feron q-john-tuckeri-cone-gall (agamic)                                | q-john-tuckeri-cone-gall                            |
| 4402       | Feron q-lobata-hairy-pebble (sexgen)                                   | q-lobata-hairy-pebble                               |
| 5611       | Feron q-obtusata-disc-gall                                             | q-obtusata-disc-gall                                |
| 5992       | Feron white-oak-hair-stalk-gall (sexgen)                               | white-oak-hair-stalk-gall                           |
| 2704       | Gnorimoschema b-sarothroides-leaf-gall-moth                            | b-sarothroides-leaf-gall-moth                       |
| 5847       | Gnorimoschema s-auriculata-pyriform-stem-swelling                      | s-auriculata-pyriform-stem-swelling                 |
| 4949       | Gnorimoschema s-chapmanii-ovoid-stem-swelling                          | s-chapmanii-ovoid-stem-swelling                     |
| 4956       | Gnorimoschema s-fistulosa-elliptical-stem-gall                         | s-fistulosa-elliptical-stem-gall                    |
| 5792       | Gnorimoschema s-hispida-pyriform-stem-swelling                         | s-hispida-pyriform-stem-swelling                    |
| 5846       | Gnorimoschema s-latissimifolia-spindle-gall                            | s-latissimifolia-spindle-gall                       |
| 5513       | Gnorimoschema s-odora-spindle-gall                                     | s-odora-spindle-gall                                |
| 5766       | Gnorimoschema s-rugosa-pyriform-stem-swelling                          | s-rugosa-pyriform-stem-swelling                     |
| 5118       | Gnorimoschema s-velutina-spindle-gall                                  | s-velutina-spindle-gall                             |
| 5580       | Golovinomyces h-virginiana-circle-spot                                 | h-virginiana-circle-spot                            |
| 3983       | Hamamelistes b-occidentalis                                            | b-occidentalis                                      |
| 3987       | Harmandiola p-balsamifera-leaf-gall                                    | p-balsamifera-leaf-gall                             |
| 3999       | Harmandiola p-tremuloides-bead-gall                                    | p-tremuloides-bead-gall                             |
| 4000       | Harmandiola p-tremuloides-bumpy-bead-gall                              | p-tremuloides-bumpy-bead-gall                       |
| 4033       | Harmandiola p-tremuloides-like-globuli                                 | p-tremuloides-like-globuli                          |
| 4030       | Harmandiola p-tremuloides-like-populnea                                | p-tremuloides-like-populnea                         |
| 4028       | Harmandiola p-tremuloides-like-tremulae                                | p-tremuloides-like-tremulae                         |
| 4029       | Harmandiola p-tremuloides-lips-gall                                    | p-tremuloides-lips-gall                             |
| 4031       | Harmandiola p-tremuloides-pouch-gall                                   | p-tremuloides-pouch-gall                            |
| 4027       | Harmandiola p-tristis-leaf-spot                                        | p-tristis-leaf-spot                                 |
| 2027       | Heteroecus q-chrysolepis-club-vein-gall (sexgen)                       | q-chrysolepis-club-vein-gall                        |
| 2408       | Heteroecus q-chrysolepis-hair-capsule-gall (sexgen)                    | q-chrysolepis-hair-capsule-gall                     |
| 2025       | Heteroecus q-chrysolepis-vase-gall (agamic)                            | q-chrysolepis-vase-gall                             |
| 5432       | Heteroecus q-palmeri-chefs-hat-gall                                    | q-palmeri-chefs-hat-gall                            |
| 2010       | Heteroecus q-palmeri-kernel-gall (agamic)                              | q-palmeri-kernel-gall                               |
| 5350       | Homaluroides aristida-stem-swelling                                    | aristida-stem-swelling                              |
| 5357       | Homaluroides c-dactylon-stem-swelling                                  | c-dactylon-stem-swelling                            |
| 5354       | Homaluroides d-oligosanthes-bud-gall                                   | d-oligosanthes-bud-gall                             |
| 5356       | Homaluroides dichanthelium-bud-gall                                    | dichanthelium-bud-gall                              |
| 5352       | Homaluroides sporobolus-stem-swelling                                  | sporobolus-stem-swelling                            |
| 4942       | Hyadaphis l-involucrata-leaf-edge-fold                                 | l-involucrata-leaf-edge-fold                        |
| 2613       | Illinoia r-parviflorus-pouch-gall                                      | r-parviflorus-pouch-gall                            |
| 3124       | Iteomyia s-barclayi-appressed-tooth-gall-midge                         | s-barclayi-appressed-tooth-gall-midge               |
| 3676       | Iteomyia s-candida-leaf-spot                                           | s-candida-leaf-spot                                 |
| 3628       | Iteomyia s-lasiolepis-tooth-gall                                       | s-lasiolepis-tooth-gall                             |
| 2267       | Iteomyia s-lasiolepis-tube-gall                                        | s-lasiolepis-tube-gall                              |
| 3633       | Iteomyia s-scouleriana-small-tube-gall                                 | s-scouleriana-small-tube-gall                       |
| 3708       | Iteomyia salix-chili-pepper-gall                                       | salix-chili-pepper-gall                             |
| 3647       | Iteomyia salix-tooth-gall                                              | salix-tooth-gall                                    |
| 5634       | Josephiella f-microcarpa-stem-cluster                                  | f-microcarpa-stem-cluster                           |
| 4825       | Kinseyella q-segoviensis-thick-walled-gall (agamic)                    | q-segoviensis-thick-walled-gall                     |
| 5216       | Lasioptera c-occidentale-swollen-stem                                  | c-occidentale-swollen-stem                          |
| 5388       | Lasioptera d-ambrosioides-stem-swelling                                | d-ambrosioides-stem-swelling                        |
| 3724       | Lasioptera t-laxa-lily-stem-gall                                       | t-laxa-lily-stem-gall                               |
| 5824       | Lonicerae l-interrupta-bud-gall-similar-to-L-lonicera                  | l-interrupta-bud-gall-similar-to-L-lonicera         |
| 5526       | Lonicerae l-subspicata-leafy-rosette                                   | l-subspicata-leafy-rosette                          |
| 2186       | Lonicerae s-albus-basal-stem-gall                                      | s-albus-basal-stem-gall                             |
| 3090       | Lopesia c-glandulosus-swollen-leaf-gall                                | c-glandulosus-swollen-leaf-gall                     |
| 4401       | Lopesia m-arborea-tuft-gall                                            | m-arborea-tuft-gall                                 |
| 3007       | Macrodiplosis c-dentata-ribbed-fold-gall                               | c-dentata-ribbed-fold-gall                          |
| 3138       | Macrodiplosis lobe-fold-mine                                           | lobe-fold-mine                                      |
| 3104       | Macrodiplosis q-agrifolia-vein-fold                                    | q-agrifolia-vein-fold                               |
| 2837       | Macrodiplosis q-marilandica-bubble-gall                                | q-marilandica-bubble-gall                           |
| 1164       | Macrodiplosis q-marilandica-globular-vein-gall                         | q-marilandica-globular-vein-gall                    |
| 2962       | Macrodiplosis q-marilandica-linear-pocket                              | q-marilandica-linear-pocket                         |
| 4248       | Macrodiplosis q-muehlenbergii-expanded-veins-gall                      | q-muehlenbergii-expanded-veins-gall                 |
| 2308       | Macrodiplosis q-phellos-ribbed-gall                                    | q-phellos-ribbed-gall                               |
| 1639       | Macrodiplosis q-rubra-early-vein-swelling                              | q-rubra-early-vein-swelling                         |
| 3463       | Macrodiplosis q-stellata-like-majalis                                  | q-stellata-like-majalis                             |
| 5988       | Mayetiola c-canadensis-stem-swelling                                   | c-canadensis-stem-swelling                          |
| 5339       | Mayetiola o-lindheimeri-slight-swelling-on-pad-orange-larvae           | o-lindheimeri-slight-swelling-on-pad-orange-larvae  |
| 4252       | Melikaiella q-buckleyi-late-gall (sexgen)                              | q-buckleyi-late-gall                                |
| 4689       | Melikaiella q-imbricaria-bent-catkin (sexgen)                          | q-imbricaria-bent-catkin                            |
| 1170       | Melikaiella q-phellos-midrib-swelling (sexgen)                         | q-phellos-midrib-swelling                           |
| 4893       | Melikaiella q-rubra-flower-swelling                                    | q-rubra-flower-swelling                             |
| 1492       | Meunieriella on-smilax                                                 | on-smilax                                           |
| 3359       | Meunieriella u-sessilifolia-leaf-spot                                  | u-sessilifolia-leaf-spot                            |
| 3424       | Mompha c-angustifolium-stem-swelling                                   | c-angustifolium-stem-swelling                       |
| 4238       | Mompha e-canum-leaf-shell                                              | e-canum-leaf-shell                                  |
| 3246       | Mompha o-lindheimeri-stem-swelling                                     | o-lindheimeri-stem-swelling                         |
| 5863       | Neolasioptera a-bracteata-stem-swelling                                | a-bracteata-stem-swelling                           |
| 3077       | Neolasioptera a-canadense-rhizome-gall                                 | a-canadense-rhizome-gall                            |
| 3237       | Neolasioptera a-ostryifolia-stem-gall                                  | a-ostryifolia-stem-gall                             |
| 3330       | Neolasioptera a-salsola-rosette-gall-midge                             | a-salsola-rosette-gall-midge                        |
| 3329       | Neolasioptera a-salsola-stem-gall-midge                                | a-salsola-stem-gall-midge                           |
| 5867       | Neolasioptera baptisia-stem-swelling                                   | baptisia-stem-swelling                              |
| 5210       | Neolasioptera bidens-sp-tapered-stem-swelling                          | bidens-sp-tapered-stem-swelling                     |
| 4045       | Neolasioptera c-annuum-swollen-stem                                    | c-annuum-swollen-stem                               |
| 5326       | Neolasioptera c-bignonioides-circular-leaf-spot                        | c-bignonioides-circular-leaf-spot                   |
| 5830       | Neolasioptera c-discolor-midrib-gall                                   | c-discolor-midrib-gall                              |
| 5967       | Neolasioptera c-glabra-swelling                                        | c-glabra-swelling                                   |
| 5960       | Neolasioptera cattleya-root-nodules                                    | cattleya-root-nodules                               |
| 5786       | Neolasioptera d-umbellata-tapered-stem-swelling                        | d-umbellata-tapered-stem-swelling                   |
| 2749       | Neolasioptera d-villosa-woody-swelling                                 | d-villosa-woody-swelling                            |
| 4133       | Neolasioptera e-confertiflorum-white-stem-swelling                     | e-confertiflorum-white-stem-swelling                |
| 3210       | Neolasioptera e-hieraciifolius-stem-swelling                           | e-hieraciifolius-stem-swelling                      |
| 5897       | Neolasioptera ephedra-irregular-stem-swelling                          | ephedra-irregular-stem-swelling                     |
| 5232       | Neolasioptera f-linearis-tapered-stem-swelling                         | f-linearis-tapered-stem-swelling                    |
| 5573       | Neolasioptera g-bipinnatifida-stem-swelling                            | g-bipinnatifida-stem-swelling                       |
| 3363       | Neolasioptera g-circaezans-stem-swelling                               | g-circaezans-stem-swelling                          |
| 5271       | Neolasioptera h-angustifolius-tapered-stem-swelling                    | h-angustifolius-tapered-stem-swelling               |
| 2831       | Neolasioptera h-curassavicum-green-blob-gall                           | h-curassavicum-green-blob-gall                      |
| 5269       | Neolasioptera h-eggertii-tapered-stem-swelling                         | h-eggertii-tapered-stem-swelling                    |
| 2680       | Neolasioptera h-grosseserratus-globose-stem-gall                       | h-grosseserratus-globose-stem-gall                  |
| 5303       | Neolasioptera h-longifolia-swollen-stem-gall                           | h-longifolia-swollen-stem-gall                      |
| 5900       | Neolasioptera h-volubilis-irregular-root-swelling                      | h-volubilis-irregular-root-swelling                 |
| 5395       | Neolasioptera ipomoea-tapered-stem-swelling                            | ipomoea-tapered-stem-swelling                       |
| 5285       | Neolasioptera iva-tapered-stem-swelling                                | iva-tapered-stem-swelling                           |
| 5390       | Neolasioptera k-lanata-tapered-stem-swelling                           | k-lanata-tapered-stem-swelling                      |
| 2739       | Neolasioptera k-pentacarpos-tapered-stem-swelling                      | k-pentacarpos-tapered-stem-swelling                 |
| 5926       | Neolasioptera l-puberula-elongate-swollen-stem                         | l-puberula-elongate-swollen-stem                    |
| 4043       | Neolasioptera l-torreyi-stem-swelling                                  | l-torreyi-stem-swelling                             |
| 5883       | Neolasioptera l-violacea-swollen-stem                                  | l-violacea-swollen-stem                             |
| 5910       | Neolasioptera m-arvensis-stem-gall                                     | m-arvensis-stem-gall                                |
| 5948       | Neolasioptera m-linearis-stem-swelling                                 | m-linearis-stem-swelling                            |
| 2824       | Neolasioptera n-cataria-stem-swelling                                  | n-cataria-stem-swelling                             |
| 5338       | Neolasioptera o-lindheimeri-slight-swelling-on-pad-red-larvae          | o-lindheimeri-slight-swelling-on-pad-red-larvae     |
| 4121       | Neolasioptera p-glabella-crown-swelling                                | p-glabella-crown-swelling                           |
| 4026       | Neolasioptera p-pumila-stem-swelling                                   | p-pumila-stem-swelling                              |
| 4053       | Neolasioptera r-sanguineum-irregular-stem-gall                         | r-sanguineum-irregular-stem-gall                    |
| 4074       | Neolasioptera s-alba-swollen-stem                                      | s-alba-swollen-stem                                 |
| 4141       | Neolasioptera s-ambigua-abrupt-stem-swelling                           | s-ambigua-abrupt-stem-swelling                      |
| 3255       | Neolasioptera s-carolinense-leaf-gall                                  | s-carolinense-leaf-gall                             |
| 3020       | Neolasioptera s-chamissonis-stem-swelling                              | s-chamissonis-stem-swelling                         |
| 5043       | Neolasioptera s-lanceolatum-tapered-stem-swelling                      | s-lanceolatum-tapered-stem-swelling                 |
| 4147       | Neolasioptera s-marilandica-stem-swelling                              | s-marilandica-stem-swelling                         |
| 2873       | Neolasioptera s-mexicana-bladder-sage-gall-midge                       | s-mexicana-bladder-sage-gall-midge                  |
| 4207       | Neolasioptera s-vermiculatus-stem-swelling                             | s-vermiculatus-stem-swelling                        |
| 5446       | Neolasioptera symphoricarpos-swollen-twig                              | symphoricarpos-swollen-twig                         |
| 5336       | Neolasioptera tillandsia-root-nodule                                   | tillandsia-root-nodule                              |
| 4015       | Neolasioptera v-hastata-stem-swelling                                  | v-hastata-stem-swelling                             |
| 1753       | Neolasioptera v-urticifolia-stem-swelling                              | v-urticifolia-stem-swelling                         |
| 4263       | Neuroterus q-alba-early-flake-gall                                     | q-alba-early-flake-gall                             |
| 4851       | Neuroterus q-alba-raised-blisters (sexgen)                             | q-alba-raised-blisters                              |
| 1071       | Neuroterus q-alba-white-bead-gall (agamic)                             | q-alba-white-bead-gall                              |
| 2647       | Neuroterus q-bumelioides-bead-gall                                     | q-bumelioides-bead-gall                             |
| 2646       | Neuroterus q-bumelioides-solitary-gall                                 | q-bumelioides-solitary-gall                         |
| 2648       | Neuroterus q-bumelioides-tuber-gall                                    | q-bumelioides-tuber-gall                            |
| 2644       | Neuroterus q-bumelioides-twig-gall                                     | q-bumelioides-twig-gall                             |
| 1943       | Neuroterus q-cornelius-mulleri-flat-topped-gall (sexgen)               | q-cornelius-mulleri-flat-topped-gall                |
| 4934       | Neuroterus q-fusiformis-mottled-filament-gall (agamic)                 | q-fusiformis-mottled-filament-gall                  |
| 5410       | Neuroterus q-fusiformis-spring-bud-gall (sexgen)                       | q-fusiformis-spring-bud-gall                        |
| 3753       | Neuroterus q-gambelii-like-niger (agamic)                              | q-gambelii-like-niger                               |
| 4696       | Neuroterus q-gambelii-new-growth-swelling (sexgen)                     | q-gambelii-new-growth-swelling                      |
| 4811       | Neuroterus q-havardii-bead-gall (agamic)                               | q-havardii-bead-gall                                |
| 3484       | Neuroterus q-havardii-blackeye-gall (agamic)                           | q-havardii-blackeye-gall                            |
| 4954       | Neuroterus q-havardii-like-niger (agamic)                              | q-havardii-like-niger                               |
| 4847       | Neuroterus q-john-tuckeri-leaf-blister (sexgen)                        | q-john-tuckeri-leaf-blister                         |
| 1061       | Neuroterus q-laceyi-hairy-spangle-gall (agamic)                        | q-laceyi-hairy-spangle-gall                         |
| 3422       | Neuroterus q-laceyi-midrib-swelling (sexgen)                           | q-laceyi-midrib-swelling                            |
| 2645       | Neuroterus q-lancifolia-catkin-gall                                    | q-lancifolia-catkin-gall                            |
| 2643       | Neuroterus q-lancifolia-midrib-capsule                                 | q-lancifolia-midrib-capsule                         |
| 4160       | Neuroterus q-lyrata-like-papillosus (sexgen)                           | q-lyrata-like-papillosus                            |
| 2973       | Neuroterus q-lyrata-red-spangle (agamic)                               | q-lyrata-red-spangle                                |
| 1047       | Neuroterus q-macrocarpa-flower-swelling-gall (sexgen)                  | q-macrocarpa-flower-swelling-gall                   |
| 2120       | Neuroterus q-macrocarpa-fuzzy-flower-gall (sexgen)                     | q-macrocarpa-fuzzy-flower-gall                      |
| 4283       | Neuroterus q-macrocarpa-hairy-glob (agamic)                            | q-macrocarpa-hairy-glob                             |
| 4282       | Neuroterus q-macrocarpa-hairy-saucer (agamic)                          | q-macrocarpa-hairy-saucer                           |
| 4850       | Neuroterus q-muehlenbergii-rough-blister (sexgen)                      | q-muehlenbergii-rough-blister                       |
| 2472       | Neuroterus q-oblongifolia-woolly-white-gall (agamic)                   | q-oblongifolia-woolly-white-gall                    |
| 5609       | Neuroterus q-obtusata-like-quercusverrucarum (agamic)                  | q-obtusata-like-quercusverrucarum                   |
| 5614       | Neuroterus q-obtusata-white-spangle                                    | q-obtusata-white-spangle                            |
| 4295       | Neuroterus q-stellata-hole-punch-gall (sexgen)                         | q-stellata-hole-punch-gall                          |
| 5514       | Neuroterus q-undulata-fall-like-oblongifoliae                          | q-undulata-fall-like-oblongifoliae                  |
| 2014       | Neuroterus q-vacciniifolia-abrupt-stem-gall                            | q-vacciniifolia-abrupt-stem-gall                    |
| 1110       | Neuroterus q-virginiana-numerous-leaf-galls (agamic)                   | q-virginiana-numerous-leaf-galls                    |
| 5639       | Neuroterus q-virginiana-winter-blister                                 | q-virginiana-winter-blister                         |
| 5433       | Nichollsiella q-turbinella-globular-bud-gall                           | q-turbinella-globular-bud-gall                      |
| 2755       | Oligotrophus j-scopulorum-recurved-leaf-scale-gall                     | j-scopulorum-recurved-leaf-scale-gall               |
| 4300       | Pachypsylla c-caudata-ring-gall                                        | c-caudata-ring-gall                                 |
| 3102       | Pachypsylla c-laevigata-blister-gall                                   | c-laevigata-blister-gall                            |
| 3996       | Pemphigus p-fremontii-midrib-gall                                      | p-fremontii-midrib-gall                             |
| 3630       | Phyllocolpa s-exigua-fold-gall                                         | s-exigua-fold-gall                                  |
| 2710       | Phyllocoptes s-canadensis-leaf-puckering-gall                          | s-canadensis-leaf-puckering-gall                    |
| 3200       | Phylloteras q-alba-red-margin-spangle (agamic)                         | q-alba-red-margin-spangle                           |
| 4278       | Phylloteras q-bicolor-like-poculum (agamic)                            | q-bicolor-like-poculum                              |
| 1260       | Phylloteras q-muehlenbergii-spangle-gall (agamic)                      | q-muehlenbergii-spangle-gall                        |
| 5613       | Phylloteras q-obtusata-plate-gall                                      | q-obtusata-plate-gall                               |
| 1081       | Phylloteras q-stellata-spangle-gall (agamic)                           | q-stellata-spangle-gall                             |
| 2972       | Phylloxera c-ovata-netted-gall                                         | c-ovata-netted-gall                                 |
| 4187       | Phylloxera c-texana-new-shoot-gall                                     | c-texana-new-shoot-gall                             |
| 2757       | Planetella c-vesicaria-tuber-gall                                      | c-vesicaria-tuber-gall                              |
| 2775       | Plemeliella p-glauca-hidden-cell                                       | p-glauca-hidden-cell                                |
| 1721       | Polystepha q-agrifolia-leaf-spot                                       | q-agrifolia-leaf-spot                               |
| 4183       | Polystepha q-alba-spot-gall                                            | q-alba-spot-gall                                    |
| 2611       | Polystepha q-hypoleucoides-red-apple-gall                              | q-hypoleucoides-red-apple-gall                      |
| 4205       | Polystepha q-imbricaria-leaf-spot                                      | q-imbricaria-leaf-spot                              |
| 2993       | Polystepha q-imbricaria-raspberry-gall                                 | q-imbricaria-raspberry-gall                         |
| 2994       | Polystepha q-marilandica-flat-top-gall                                 | q-marilandica-flat-top-gall                         |
| 3353       | Polystepha q-marilandica-short-leaf-gall                               | q-marilandica-short-leaf-gall                       |
| 1811       | Polystepha q-nigra-cone-gall                                           | q-nigra-cone-gall                                   |
| 3298       | Polystepha q-nigra-leaf-spot                                           | q-nigra-leaf-spot                                   |
| 3112       | Polystepha q-nigra-vein-axil-gall                                      | q-nigra-vein-axil-gall                              |
| 3215       | Polystepha q-phellos-purple-leaf-spot                                  | q-phellos-purple-leaf-spot                          |
| 3266       | Polystepha q-shumardii-vein-angle-gall                                 | q-shumardii-vein-angle-gall                         |
| 3339       | Polystepha q-velutina-small-leaf-spots                                 | q-velutina-small-leaf-spots                         |
| 2655       | Polystepha q-virginiana-wart-gall                                      | q-virginiana-wart-gall                              |
| 5490       | Procecidochares b-californica-abrupt-stem-swelling                     | b-californica-abrupt-stem-swelling                  |
| 5491       | Procecidochares e-nauseosa-swollen-flower-bud                          | e-nauseosa-swollen-flower-bud                       |
| 5780       | Procecidochares s-cordifolium-leafy-bud-gall                           | s-cordifolium-leafy-bud-gall                        |
| 5769       | Procecidochares s-leavenworthii-large-distinct-rosettes                | s-leavenworthii-large-distinct-rosettes             |
| 4099       | Putoniella p-angustifolia-globular-leaf-fold                           | p-angustifolia-globular-leaf-fold                   |
| 3366       | Putoniella v-angustifolium-leaf-edge-fold                              | v-angustifolium-leaf-edge-fold                      |
| 592        | Rabdophaga like-rosaria                                                | like-rosaria                                        |
| 3908       | Rabdophaga s-discolor-stem-gall                                        | s-discolor-stem-gall                                |
| 3713       | Rabdophaga s-exigua-fuzzy-cone-gall                                    | s-exigua-fuzzy-cone-gall                            |
| 3614       | Rabdophaga s-lasiolepis-bud-gall                                       | s-lasiolepis-bud-gall                               |
| 2798       | Resseliella g-angustifolium-swollen-bud-gall                           | g-angustifolium-swollen-bud-gall                    |
| 2773       | Resseliella l-laricina-seed-gall                                       | l-laricina-seed-gall                                |
| 2948       | Rhopalomyia a-canescens-red-tube-gall                                  | a-canescens-red-tube-gall                           |
| 3294       | Rhopalomyia a-dracunculus-globular-rosette                             | a-dracunculus-globular-rosette                      |
| 4769       | Rhopalomyia a-filifolia-linear-rosette                                 | a-filifolia-linear-rosette                          |
| 3426       | Rhopalomyia a-frigida-globular-rosette                                 | a-frigida-globular-rosette                          |
| 3427       | Rhopalomyia a-ludoviciana-hairy-bud-gall                               | a-ludoviciana-hairy-bud-gall                        |
| 5080       | Rhopalomyia a-millefolium-downy-bud-gall                               | a-millefolium-downy-bud-gall                        |
| 3954       | Rhopalomyia a-tridentata-woolly-gall                                   | a-tridentata-woolly-gall                            |
| 4828       | Rhopalomyia b-glutinosa-like-californica                               | b-glutinosa-like-californica                        |
| 4249       | Rhopalomyia b-pilularis-leaf-gall                                      | b-pilularis-leaf-gall                               |
| 4839       | Rhopalomyia b-sarothroides-bud-gall                                    | b-sarothroides-bud-gall                             |
| 4838       | Rhopalomyia b-sarothroides-teardrop-gall                               | b-sarothroides-teardrop-gall                        |
| 2185       | Rhopalomyia c-filaginifolia-cotton-bud-gall                            | c-filaginifolia-cotton-bud-gall                     |
| 5532       | Rhopalomyia d-ledophylla-terminal-leafy-rosette                        | d-ledophylla-terminal-leafy-rosette                 |
| 5219       | Rhopalomyia e-canadensis-hairy-bud-gall                                | e-canadensis-hairy-bud-gall                         |
| 3319       | Rhopalomyia e-farinosa-leaf-gall-midge                                 | e-farinosa-leaf-gall-midge                          |
| 3044       | Rhopalomyia e-leptocephala-ribbed-leaf-gall                            | e-leptocephala-ribbed-leaf-gall                     |
| 4111       | Rhopalomyia e-nauseosa-almond-gall                                     | e-nauseosa-almond-gall                              |
| 3882       | Rhopalomyia e-nauseosa-purple-cone-gall                                | e-nauseosa-purple-cone-gall                         |
| 3970       | Rhopalomyia e-nauseosa-terminal-stem-gall                              | e-nauseosa-terminal-stem-gall                       |
| 5224       | Rhopalomyia e-peregrinus-swollen-deformed-calyx                        | e-peregrinus-swollen-deformed-calyx                 |
| 5240       | Rhopalomyia gutierrezia-linear-rosette-leaf-gall                       | gutierrezia-linear-rosette-leaf-gall                |
| 5239       | Rhopalomyia gutierrezia-ovate-rosette-leaf-gall                        | gutierrezia-ovate-rosette-leaf-gall                 |
| 3976       | Rhopalomyia h-squarrosa-rosette-gall                                   | h-squarrosa-rosette-gall                            |
| 5565       | Rhopalomyia r-cereum-rosette-gall                                      | r-cereum-rosette-gall                               |
| 3223       | Rhopalomyia s-altissima-cone-gall                                      | s-altissima-cone-gall                               |
| 5298       | Rhopalomyia s-canadensis-cylindrical-smooth-gall                       | s-canadensis-cylindrical-smooth-gall                |
| 5413       | Rhopalomyia s-columbariae-purple-leaf-blisters                         | s-columbariae-purple-leaf-blisters                  |
| 5831       | Rhopalomyia s-cordifolium-multi-celled-rosette-gall                    | s-cordifolium-multi-celled-rosette-gall             |
| 3180       | Rhopalomyia s-fistulosa-stem-cluster-gall                              | s-fistulosa-stem-cluster-gall                       |
| 5297       | Rhopalomyia s-juncea-teardrop-bulbletlike-gall                         | s-juncea-teardrop-bulbletlike-gall                  |
| 5194       | Rhopalomyia s-lateriflorum-conical-leaf-gall                           | s-lateriflorum-conical-leaf-gall                    |
| 2970       | Rhopalomyia s-lateriflorum-spongy-gall                                 | s-lateriflorum-spongy-gall                          |
| 5994       | Rhopalomyia s-leucophylla-hemispherical-swellings-on-leaf-top          | s-leucophylla-hemispherical-swellings-on-leaf-top   |
| 5750       | Rhopalomyia s-nemoralis-spongy-gall                                    | s-nemoralis-spongy-gall                             |
| 5201       | Rhopalomyia s-novae-angliae-ovoid-gall-among-flowers                   | s-novae-angliae-ovoid-gall-among-flowers            |
| 4644       | Rhopalomyia s-odora-fusiform-inflorescence-gall                        | s-odora-fusiform-inflorescence-gall                 |
| 5200       | Rhopalomyia s-undulatum-deformed-lateral-floret                        | s-undulatum-deformed-lateral-floret                 |
| 5183       | Schizomyia a-artemisiifolia-globular-leaf-swelling                     | a-artemisiifolia-globular-leaf-swelling             |
| 2743       | Schizomyia c-canadensis-swollen-flower-gall                            | c-canadensis-swollen-flower-gall                    |
| 5636       | Schizomyia g-sarothrae-like-s-racemicola                               | g-sarothrae-like-s-racemicola                       |
| 2779       | Schizomyia r-ilicifolia-swollen-flower-club                            | r-ilicifolia-swollen-flower-club                    |
| 4184       | Stegophylla q-stellata-edge-fold                                       | q-stellata-edge-fold                                |
| 3505       | Stephomyia eugenia-conical-gall                                        | eugenia-conical-gall                                |
| 3316       | Symmetrischema l-cooperi-stem-gall-moth                                | l-cooperi-stem-gall-moth                            |
| 5475       | Synchytrium p-erecta-red-pustules                                      | p-erecta-red-pustules                               |
| 2235       | Synergus deforming-pacificus                                           | deforming-pacificus                                 |
| 5706       | Taphrina a-incana-near-japonica-on-other-Alnus-species                 | a-incana-near-japonica-on-other-Alnus-species       |
| 5423       | Taphrina p-fremontii-leaf-blister                                      | p-fremontii-leaf-blister                            |
| 2290       | Taxodiomyia t-distichum-mustard-seed-gall                              | t-distichum-mustard-seed-gall                       |
| 5738       | Taxodiomyia t-distichum-pinwheel-gall                                  | t-distichum-pinwheel-gall                           |
| 5740       | Taxodiomyia t-distichum-ridged-gall                                    | t-distichum-ridged-gall                             |
| 5733       | Taxodiomyia t-distichum-spindle-gall                                   | t-distichum-spindle-gall                            |
| 2154       | Taxodiomyia t-distichum-starburst-gall                                 | t-distichum-starburst-gall                          |
| 5713       | Taxodiomyia t-distichum-urchin-gall                                    | t-distichum-urchin-gall                             |
| 5664       | Trioza f-californica-nr-beameri-pit-gall                               | f-californica-nr-beameri-pit-gall                   |
| 5718       | Unknown (Aphididae) l-conjugialis-tight-leaf-curl                      | l-conjugialis-tight-leaf-curl                       |
| 4265       | Unknown (Aphididae) p-balsamifera-horn-curl                            | p-balsamifera-horn-curl                             |
| 4058       | Unknown (Aphididae) p-tremuloides-cherry-gall                          | p-tremuloides-cherry-gall                           |
| 2260       | Unknown (Aphididae) u-crassifolia-thickened-leaf-curl                  | u-crassifolia-thickened-leaf-curl                   |
| 5486       | Unknown (Cecidomyiidae) a-alnifolia-pouch-gall                         | a-alnifolia-pouch-gall                              |
| 3127       | Unknown (Cecidomyiidae) a-altissima-cryptic-petiole-gall               | a-altissima-cryptic-petiole-gall                    |
| 3126       | Unknown (Cecidomyiidae) a-altissima-flower-gall                        | a-altissima-flower-gall                             |
| 3125       | Unknown (Cecidomyiidae) a-altissima-hairy-bud-gall                     | a-altissima-hairy-bud-gall                          |
| 3043       | Unknown (Cecidomyiidae) a-ambrosioides-hemispherical-leaf-gall         | a-ambrosioides-hemispherical-leaf-gall              |
| 2745       | Unknown (Cecidomyiidae) a-androsaemifolium-seed-pod-gall               | a-androsaemifolium-seed-pod-gall                    |
| 5595       | Unknown (Cecidomyiidae) a-bisulcatus-flower-bud-gall                   | a-bisulcatus-flower-bud-gall                        |
| 4498       | Unknown (Cecidomyiidae) a-californica-leafy-rosette-gall               | a-californica-leafy-rosette-gall                    |
| 5921       | Unknown (Cecidomyiidae) a-canadense-aborted-seed-pod                   | a-canadense-aborted-seed-pod                        |
| 2949       | Unknown (Cecidomyiidae) a-canescens-leaf-pouch-gall                    | a-canescens-leaf-pouch-gall                         |
| 2950       | Unknown (Cecidomyiidae) a-canescens-leaf-roll                          | a-canescens-leaf-roll                               |
| 3820       | Unknown (Cecidomyiidae) a-canescens-purple-blister-gall                | a-canescens-purple-blister-gall                     |
| 2953       | Unknown (Cecidomyiidae) a-dracunculus-leafy-rosette-gall               | a-dracunculus-leafy-rosette-gall                    |
| 5747       | Unknown (Cecidomyiidae) a-mollissimus-swollen-stem-gall                | a-mollissimus-swollen-stem-gall                     |
| 2341       | Unknown (Cecidomyiidae) a-negundo-rough-twig-swelling                  | a-negundo-rough-twig-swelling                       |
| 4599       | Unknown (Cecidomyiidae) a-podocarpa-flowerbud-gall                     | a-podocarpa-flowerbud-gall                          |
| 4531       | Unknown (Cecidomyiidae) a-rainbowensis-leaf-blister                    | a-rainbowensis-leaf-blister                         |
| 5596       | Unknown (Cecidomyiidae) a-robbinsii-flower-bud-gall                    | a-robbinsii-flower-bud-gall                         |
| 3171       | Unknown (Cecidomyiidae) a-rubra-swollen-bud-gall                       | a-rubra-swollen-bud-gall                            |
| 3265       | Unknown (Cecidomyiidae) a-rubra-vein-gall                              | a-rubra-vein-gall                                   |
| 5281       | Unknown (Cecidomyiidae) a-salsola-woolly-bud-gall-two                  | a-salsola-woolly-bud-gall-two                       |
| 3402       | Unknown (Cecidomyiidae) a-triphylla-purple-leaf-spot                   | a-triphylla-purple-leaf-spot                        |
| 5104       | Unknown (Cecidomyiidae) a-uva-ursi-bud-gall                            | a-uva-ursi-bud-gall                                 |
| 4774       | Unknown (Cecidomyiidae) a-viscida-club-gall                            | a-viscida-club-gall                                 |
| 4688       | Unknown (Cecidomyiidae) b-californica-leaf-blister                     | b-californica-leaf-blister                          |
| 4703       | Unknown (Cecidomyiidae) b-connata-midrib-swelling                      | b-connata-midrib-swelling                           |
| 5891       | Unknown (Cecidomyiidae) b-diffusa-stem-swelling                        | b-diffusa-stem-swelling                             |
| 4840       | Unknown (Cecidomyiidae) b-sarothroides-rosette-gall                    | b-sarothroides-rosette-gall                         |
| 3117       | Unknown (Cecidomyiidae) c-americana-folded-leaf                        | c-americana-folded-leaf                             |
| 5444       | Unknown (Cecidomyiidae) c-bignonioides-curled-leaf-midrib              | c-bignonioides-curled-leaf-midrib                   |
| 5325       | Unknown (Cecidomyiidae) c-bignonioides-swollen-new-shoots              | c-bignonioides-swollen-new-shoots                   |
| 3475       | Unknown (Cecidomyiidae) c-canadensis-blister-gall                      | c-canadensis-blister-gall                           |
| 2693       | Unknown (Cecidomyiidae) c-canadensis-striped-needle-gall               | c-canadensis-striped-needle-gall                    |
| 2966       | Unknown (Cecidomyiidae) c-cordiformis-succulent-swelling               | c-cordiformis-succulent-swelling                    |
| 4558       | Unknown (Cecidomyiidae) c-cornuta-aborted-bud                          | c-cornuta-aborted-bud                               |
| 5552       | Unknown (Cecidomyiidae) c-douglasii-abrupt-petiole-gall                | c-douglasii-abrupt-petiole-gall                     |
| 5415       | Unknown (Cecidomyiidae) c-fruticulosus-hairy-cluster-gall              | c-fruticulosus-hairy-cluster-gall                   |
| 4243       | Unknown (Cecidomyiidae) c-imbricata-deformed-fruit-gall                | c-imbricata-deformed-fruit-gall                     |
| 5749       | Unknown (Cecidomyiidae) c-leucodermis-midrib-swelling                  | c-leucodermis-midrib-swelling                       |
| 5103       | Unknown (Cecidomyiidae) c-origanoides-swollen-bud-gall                 | c-origanoides-swollen-bud-gall                      |
| 2759       | Unknown (Cecidomyiidae) c-praegracilis-deformed-fruit-gall             | c-praegracilis-deformed-fruit-gall                  |
| 4930       | Unknown (Cecidomyiidae) c-pterocarya-hairy-leaf-gall                   | c-pterocarya-hairy-leaf-gall                        |
| 3004       | Unknown (Cecidomyiidae) c-pumila-swollen-petiole-gall                  | c-pumila-swollen-petiole-gall                       |
| 5092       | Unknown (Cecidomyiidae) c-sericea-swollen-fruit                        | c-sericea-swollen-fruit                             |
| 2956       | Unknown (Cecidomyiidae) c-umbellata-leafy-bract-gall                   | c-umbellata-leafy-bract-gall                        |
| 5894       | Unknown (Cecidomyiidae) chrysolepis-vein-swelling-or-rolled-leaf       | chrysolepis-vein-swelling-or-rolled-leaf            |
| 3039       | Unknown (Cecidomyiidae) coreopsis-globular-stem-swelling               | coreopsis-globular-stem-swelling                    |
| 5485       | Unknown (Cecidomyiidae) d-californica-stem-swelling                    | d-californica-stem-swelling                         |
| 2924       | Unknown (Cecidomyiidae) d-candida-swollen-stem-gall                    | d-candida-swollen-stem-gall                         |
| 3063       | Unknown (Cecidomyiidae) d-formosa-globular-leaf-gall                   | d-formosa-globular-leaf-gall                        |
| 3268       | Unknown (Cecidomyiidae) d-lonicera-leaf-spot                           | d-lonicera-leaf-spot                                |
| 5930       | Unknown (Cecidomyiidae) d-verticillatus-bud-gall                       | d-verticillatus-bud-gall                            |
| 5571       | Unknown (Cecidomyiidae) e-arborescens-wide-bract-rosette-cluster       | e-arborescens-wide-bract-rosette-cluster            |
| 4826       | Unknown (Cecidomyiidae) e-californica-fuzzy-bud-gall                   | e-californica-fuzzy-bud-gall                        |
| 4534       | Unknown (Cecidomyiidae) e-corollata-deformed-fruit                     | e-corollata-deformed-fruit                          |
| 5227       | Unknown (Cecidomyiidae) e-ebano-round-gall                             | e-ebano-round-gall                                  |
| 3068       | Unknown (Cecidomyiidae) e-fendleri-snapped-leaf-gall                   | e-fendleri-snapped-leaf-gall                        |
| 3073       | Unknown (Cecidomyiidae) e-melanadenia-pubescent-tube-gall              | e-melanadenia-pubescent-tube-gall                   |
| 3061       | Unknown (Cecidomyiidae) e-pallida-fuzzy-floret-gall                    | e-pallida-fuzzy-floret-gall                         |
| 3069       | Unknown (Cecidomyiidae) e-pediculifera-capsule-gall                    | e-pediculifera-capsule-gall                         |
| 3071       | Unknown (Cecidomyiidae) e-polycarpa-tubular-gall                       | e-polycarpa-tubular-gall                            |
| 2931       | Unknown (Cecidomyiidae) e-repens-imbricated-stem-gall                  | e-repens-imbricated-stem-gall                       |
| 5810       | Unknown (Cecidomyiidae) e-sericeus-rosette-gall                        | e-sericeus-rosette-gall                             |
| 4203       | Unknown (Cecidomyiidae) erigeron-lace-gall                             | erigeron-lace-gall                                  |
| 3134       | Unknown (Cecidomyiidae) f-californica-fruit-gall                       | f-californica-fruit-gall                            |
| 3035       | Unknown (Cecidomyiidae) f-latifolia-vein-pocket                        | f-latifolia-vein-pocket                             |
| 3751       | Unknown (Cecidomyiidae) f-paradoxia-aborted-flower                     | f-paradoxia-aborted-flower                          |
| 4061       | Unknown (Cecidomyiidae) f-rupicola-enlarged-woody-bud                  | f-rupicola-enlarged-woody-bud                       |
| 5953       | Unknown (Cecidomyiidae) f-segregata-cylindrical-hairy-leaf-gall        | f-segregata-cylindrical-hairy-leaf-gall             |
| 4126       | Unknown (Cecidomyiidae) f-virginiana-reniform-petiole-gall             | f-virginiana-reniform-petiole-gall                  |
| 5419       | Unknown (Cecidomyiidae) g-aparine-abrupt-swelling                      | g-aparine-abrupt-swelling                           |
| 3516       | Unknown (Cecidomyiidae) g-hirsutula-leafy-gall                         | g-hirsutula-leafy-gall                              |
| 5236       | Unknown (Cecidomyiidae) g-lanceolata-leafy-rosette-gall                | g-lanceolata-leafy-rosette-gall                     |
| 4827       | Unknown (Cecidomyiidae) g-sarothrae-linear-flower-gall                 | g-sarothrae-linear-flower-gall                      |
| 5237       | Unknown (Cecidomyiidae) g-squarrosa-globular-bud-gall                  | g-squarrosa-globular-bud-gall                       |
| 3512       | Unknown (Cecidomyiidae) g-stricta-red-spur-gall                        | g-stricta-red-spur-gall                             |
| 5936       | Unknown (Cecidomyiidae) g-thurberi-midrib-fold-leaf-roll               | g-thurberi-midrib-fold-leaf-roll                    |
| 5629       | Unknown (Cecidomyiidae) h-alpinum-flower-bud-gall                      | h-alpinum-flower-bud-gall                           |
| 2911       | Unknown (Cecidomyiidae) h-annuus-phyllary-bead-gall                    | h-annuus-phyllary-bead-gall                         |
| 6020       | Unknown (Cecidomyiidae) h-maximiliani-volcano-stem-gall                | h-maximiliani-volcano-stem-gall                     |
| 2811       | Unknown (Cecidomyiidae) h-occidentalis-flower-cluster-gall             | h-occidentalis-flower-cluster-gall                  |
| 3023       | Unknown (Cecidomyiidae) h-pauciflorus-stem-swelling                    | h-pauciflorus-stem-swelling                         |
| 5908       | Unknown (Cecidomyiidae) hedeoma-swollen-flower-bud                     | hedeoma-swollen-flower-bud                          |
| 2961       | Unknown (Cecidomyiidae) i-capensis-stem-swelling                       | i-capensis-stem-swelling                            |
| 2746       | Unknown (Cecidomyiidae) i-vomitoria-leaf-fold                          | i-vomitoria-leaf-fold                               |
| 4127       | Unknown (Cecidomyiidae) j-scopulorum-leaf-tip-gall                     | j-scopulorum-leaf-tip-gall                          |
| 2117       | Unknown (Cecidomyiidae) k-albicaule-green-ovate-gall                   | k-albicaule-green-ovate-gall                        |
| 5448       | Unknown (Cecidomyiidae) krascheninnikovia-irregular-bud-swelling       | krascheninnikovia-irregular-bud-swelling            |
| 4521       | Unknown (Cecidomyiidae) l-capitata-leaf-pouch                          | l-capitata-leaf-pouch                               |
| 5374       | Unknown (Cecidomyiidae) l-ciliosa-irregular-swollen-bud                | l-ciliosa-irregular-swollen-bud                     |
| 5598       | Unknown (Cecidomyiidae) l-ochroleucus-flower-bud-gall                  | l-ochroleucus-flower-bud-gall                       |
| 3098       | Unknown (Cecidomyiidae) l-siphilitica-slight-midrib-swelling           | l-siphilitica-slight-midrib-swelling                |
| 5554       | Unknown (Cecidomyiidae) l-terrestris-leaf-axil-gall                    | l-terrestris-leaf-axil-gall                         |
| 4151       | Unknown (Cecidomyiidae) l-vestitus-leaf-curl                           | l-vestitus-leaf-curl                                |
| 5886       | Unknown (Cecidomyiidae) l-violacea-whitish-haired-bud-gall             | l-violacea-whitish-haired-bud-gall                  |
| 5330       | Unknown (Cecidomyiidae) lepidium-stem-or-root-swelling                 | lepidium-stem-or-root-swelling                      |
| 4777       | Unknown (Cecidomyiidae) m-densiflorus-stem-swelling                    | m-densiflorus-stem-swelling                         |
| 5680       | Unknown (Cecidomyiidae) m-fabacea-fuzzy-gall                           | m-fabacea-fuzzy-gall                                |
| 6010       | Unknown (Cecidomyiidae) m-fistulosa-apical-rosette-gall                | m-fistulosa-apical-rosette-gall                     |
| 2377       | Unknown (Cecidomyiidae) m-gale-leaf-midrib-pocket                      | m-gale-leaf-midrib-pocket                           |
| 2818       | Unknown (Cecidomyiidae) m-parvifolia-globular-swelling                 | m-parvifolia-globular-swelling                      |
| 4169       | Unknown (Cecidomyiidae) m-texana-circle-gall                           | m-texana-circle-gall                                |
| 4306       | Unknown (Cecidomyiidae) m-trinervia-starburst-gall                     | m-trinervia-starburst-gall                          |
| 5915       | Unknown (Cecidomyiidae) monarda-ovate-rootstalk-outgrowth              | monarda-ovate-rootstalk-outgrowth                   |
| 5449       | Unknown (Cecidomyiidae) n-sylvatica-swollen-twigs                      | n-sylvatica-swollen-twigs                           |
| 2340       | Unknown (Cecidomyiidae) n-sylvatica-twig-swelling                      | n-sylvatica-twig-swelling                           |
| 4155       | Unknown (Cecidomyiidae) o-virginiana-leaf-fold                         | o-virginiana-leaf-fold                              |
| 2782       | Unknown (Cecidomyiidae) o-virginiana-vein-pocket-gall                  | o-virginiana-vein-pocket-gall                       |
| 5317       | Unknown (Cecidomyiidae) p-aquatica-hairy-bladder-gall                  | p-aquatica-hairy-bladder-gall                       |
| 2816       | Unknown (Cecidomyiidae) p-cistoides-tapered-swelling                   | p-cistoides-tapered-swelling                        |
| 5745       | Unknown (Cecidomyiidae) p-edulis-bent-needle-gall                      | p-edulis-bent-needle-gall                           |
| 5641       | Unknown (Cecidomyiidae) p-edulis-swollen-needle-base                   | p-edulis-swollen-needle-base                        |
| 4892       | Unknown (Cecidomyiidae) p-edulis-tiny-needle-gall                      | p-edulis-tiny-needle-gall                           |
| 4891       | Unknown (Cecidomyiidae) p-edulis-witches-broom                         | p-edulis-witches-broom                              |
| 5784       | Unknown (Cecidomyiidae) p-graminifolia-bud-rosette-gall                | p-graminifolia-bud-rosette-gall                     |
| 5657       | Unknown (Cecidomyiidae) p-heterophyllus-swollen-bud                    | p-heterophyllus-swollen-bud                         |
| 6000       | Unknown (Cecidomyiidae) p-linarioides-red-leaf-swelling                | p-linarioides-red-leaf-swelling                     |
| 5487       | Unknown (Cecidomyiidae) p-mariana-bud-scale-gall                       | p-mariana-bud-scale-gall                            |
| 3470       | Unknown (Cecidomyiidae) p-menziesii-swollen-bud-gall                   | p-menziesii-swollen-bud-gall                        |
| 5382       | Unknown (Cecidomyiidae) p-myrsinites-folded-red-leaves                 | p-myrsinites-folded-red-leaves                      |
| 4063       | Unknown (Cecidomyiidae) p-nervosa-swollen-stem                         | p-nervosa-swollen-stem                              |
| 5659       | Unknown (Cecidomyiidae) p-nothofulvus-swollen-flower-bud               | p-nothofulvus-swollen-flower-bud                    |
| 5626       | Unknown (Cecidomyiidae) p-pallida-tuber-gall                           | p-pallida-tuber-gall                                |
| 5978       | Unknown (Cecidomyiidae) p-ponderosa-apical-bud-like-deformity          | p-ponderosa-apical-bud-like-deformity               |
| 5409       | Unknown (Cecidomyiidae) p-spectabilis-bud-gall                         | p-spectabilis-bud-gall                              |
| 4139       | Unknown (Cecidomyiidae) p-tremuloides-club-gall                        | p-tremuloides-club-gall                             |
| 4001       | Unknown (Cecidomyiidae) p-tremuloides-petiole-gall                     | p-tremuloides-petiole-gall                          |
| 1638       | Unknown (Cecidomyiidae) p-umbellata-fuzzy-vein-swelling                | p-umbellata-fuzzy-vein-swelling                     |
| 2614       | Unknown (Cecidomyiidae) p-virginiana-leaf-bud-gall                     | p-virginiana-leaf-bud-gall                          |
| 2839       | Unknown (Cecidomyiidae) p-virginianum-fuzzy-rosette-gall               | p-virginianum-fuzzy-rosette-gall                    |
| 2822       | Unknown (Cecidomyiidae) p-vulgaris-leaf-pocket                         | p-vulgaris-leaf-pocket                              |
| 5318       | Unknown (Cecidomyiidae) q-agrifolia-swollen-bud                        | q-agrifolia-swollen-bud                             |
| 4712       | Unknown (Cecidomyiidae) q-falcata-swollen-bud                          | q-falcata-swollen-bud                               |
| 2838       | Unknown (Cecidomyiidae) q-kelloggii-fold-gall                          | q-kelloggii-fold-gall                               |
| 3443       | Unknown (Cecidomyiidae) q-macrocarpa-vein-swelling                     | q-macrocarpa-vein-swelling                          |
| 3301       | Unknown (Cecidomyiidae) q-prinoides-leaf-curl                          | q-prinoides-leaf-curl                               |
| 3368       | Unknown (Cecidomyiidae) q-stellata-lateral-vein-swelling               | q-stellata-lateral-vein-swelling                    |
| 4077       | Unknown (Cecidomyiidae) r-allegheniensis-marginal-leaf-roll            | r-allegheniensis-marginal-leaf-roll                 |
| 2814       | Unknown (Cecidomyiidae) r-californica-pouch-gall                       | r-californica-pouch-gall                            |
| 5292       | Unknown (Cecidomyiidae) r-hirta-leafy-flower-heads                     | r-hirta-leafy-flower-heads                          |
| 4054       | Unknown (Cecidomyiidae) r-inerme-leaf-blister                          | r-inerme-leaf-blister                               |
| 3404       | Unknown (Cecidomyiidae) r-recurvatus-succulent-gall                    | r-recurvatus-succulent-gall                         |
| 4055       | Unknown (Cecidomyiidae) r-uva-crispa-enlarged-deformed-fruit           | r-uva-crispa-enlarged-deformed-fruit                |
| 4072       | Unknown (Cecidomyiidae) s-alba-upper-leaf-cone                         | s-alba-upper-leaf-cone                              |
| 4076       | Unknown (Cecidomyiidae) s-americana-pea-gall                           | s-americana-pea-gall                                |
| 2736       | Unknown (Cecidomyiidae) s-ciliata-gourd-gall                           | s-ciliata-gourd-gall                                |
| 5163       | Unknown (Cecidomyiidae) s-elaeagnifolium-stem-gall                     | s-elaeagnifolium-stem-gall                          |
| 2849       | Unknown (Cecidomyiidae) s-ericoides-fuzzy-tube-gall                    | s-ericoides-fuzzy-tube-gall                         |
| 2840       | Unknown (Cecidomyiidae) s-ericoides-rosette-gall                       | s-ericoides-rosette-gall                            |
| 5563       | Unknown (Cecidomyiidae) s-fistulosa-small-bud-rosette-gall             | s-fistulosa-small-bud-rosette-gall                  |
| 4559       | Unknown (Cecidomyiidae) s-gigantea-midrib-swelling                     | s-gigantea-midrib-swelling                          |
| 3707       | Unknown (Cecidomyiidae) s-hookeriana-apical-stem-gall                  | s-hookeriana-apical-stem-gall                       |
| 2677       | Unknown (Cecidomyiidae) s-panamensis-hairy-barrel-gall                 | s-panamensis-hairy-barrel-gall                      |
| 2813       | Unknown (Cecidomyiidae) s-rotundifolia-chartreuse-blister-gall         | s-rotundifolia-chartreuse-blister-gall              |
| 5772       | Unknown (Cecidomyiidae) s-sempervirens-small-bud-rosette-gall          | s-sempervirens-small-bud-rosette-gall               |
| 5175       | Unknown (Cecidomyiidae) s-spp-tiny-spherical-stem-and-leaf-enlargement | s-spp-tiny-spherical-stem-and-leaf-enlargement      |
| 3528       | Unknown (Cecidomyiidae) salix-blasted-tip                              | salix-blasted-tip                                   |
| 1309       | Unknown (Cecidomyiidae) t-americana-tuft-gall                          | t-americana-tuft-gall                               |
| 5917       | Unknown (Cecidomyiidae) t-canadense-curled-deformed-leaf               | t-canadense-curled-deformed-leaf                    |
| 5671       | Unknown (Cecidomyiidae) t-fendleri-flower-and-bud-distortions          | t-fendleri-flower-and-bud-distortions               |
| 4985       | Unknown (Cecidomyiidae) t-rhombifolia-pod-like-gall                    | t-rhombifolia-pod-like-gall                         |
| 3365       | Unknown (Cecidomyiidae) t-virginiana-leaf-fold                         | t-virginiana-leaf-fold                              |
| 1341       | Unknown (Cecidomyiidae) u-alata-spot-gall                              | u-alata-spot-gall                                   |
| 4315       | Unknown (Cecidomyiidae) v-acerifolium-red-spot                         | v-acerifolium-red-spot                              |
| 5597       | Unknown (Cecidomyiidae) v-americana-flower-bud-gall                    | v-americana-flower-bud-gall                         |
| 2768       | Unknown (Cecidomyiidae) v-canescens-stem-gall                          | v-canescens-stem-gall                               |
| 3238       | Unknown (Cecidomyiidae) v-gigantea-abrupt-seedhead-gall                | v-gigantea-abrupt-seedhead-gall                     |
| 4226       | Unknown (Cecidomyiidae) v-rufidulum-leaf-spot                          | v-rufidulum-leaf-spot                               |
| 5430       | Unknown (Cynipidae) a-heterophylla-curved-stem-swelling                | a-heterophylla-curved-stem-swelling                 |
| 4841       | Unknown (Cynipidae) b-sarothroides-ball-gall                           | b-sarothroides-ball-gall                            |
| 1115       | Unknown (Cynipidae) c-dentata-woody-radiating-fibers                   | c-dentata-woody-radiating-fibers                    |
| 4209       | Unknown (Cynipidae) columnar-oak-stem-swelling                         | columnar-oak-stem-swelling                          |
| 2577       | Unknown (Cynipidae) m-aculeaticarpa-kidney-stem-swelling               | m-aculeaticarpa-kidney-stem-swelling                |
| 2578       | Unknown (Cynipidae) m-aculeaticarpa-spiny-stem-galls                   | m-aculeaticarpa-spiny-stem-galls                    |
| 5608       | Unknown (Cynipidae) mexican-white-oak-stone-gall (agamic)              | mexican-white-oak-stone-gall                        |
| 2828       | Unknown (Cynipidae) p-gracilis-rootstalk-swelling                      | p-gracilis-rootstalk-swelling                       |
| 2827       | Unknown (Cynipidae) p-gracilis-stem-swelling                           | p-gracilis-stem-swelling                            |
| 3214       | Unknown (Cynipidae) q-agrifolia-globular-bud-gall                      | q-agrifolia-globular-bud-gall                       |
| 2416       | Unknown (Cynipidae) q-agrifolia-green-bud-gall                         | q-agrifolia-green-bud-gall                          |
| 2415       | Unknown (Cynipidae) q-agrifolia-hidden-bud-gall                        | q-agrifolia-hidden-bud-gall                         |
| 2140       | Unknown (Cynipidae) q-agrifolia-new-growth-swelling                    | q-agrifolia-new-growth-swelling                     |
| 2378       | Unknown (Cynipidae) q-agrifolia-parenchyma-blister                     | q-agrifolia-parenchyma-blister                      |
| 3728       | Unknown (Cynipidae) q-agrifolia-pedicel-swelling                       | q-agrifolia-pedicel-swelling                        |
| 1519       | Unknown (Cynipidae) q-alba-(deforming-pisiformis)                      | q-alba-(deforming-pisiformis)                       |
| 1037       | Unknown (Cynipidae) q-alba-dwarf-acorn-gall                            | q-alba-dwarf-acorn-gall                             |
| 1044       | Unknown (Cynipidae) q-alba-enlarged-lateral-bud-gall                   | q-alba-enlarged-lateral-bud-gall                    |
| 4284       | Unknown (Cynipidae) q-alba-hairy-donut                                 | q-alba-hairy-donut                                  |
| 1264       | Unknown (Cynipidae) q-alba-hairy-petiole-cluster                       | q-alba-hairy-petiole-cluster                        |
| 1043       | Unknown (Cynipidae) q-alba-hidden-white-bud-gall                       | q-alba-hidden-white-bud-gall                        |
| 4176       | Unknown (Cynipidae) q-alba-lump-gall                                   | q-alba-lump-gall                                    |
| 3297       | Unknown (Cynipidae) q-alba-mottled-bud-gall                            | q-alba-mottled-bud-gall                             |
| 3357       | Unknown (Cynipidae) q-alba-new-growth-swelling                         | q-alba-new-growth-swelling                          |
| 1064       | Unknown (Cynipidae) q-alba-pith-cell                                   | q-alba-pith-cell                                    |
| 1042       | Unknown (Cynipidae) q-alba-red-cone-bud-gall                           | q-alba-red-cone-bud-gall                            |
| 1072       | Unknown (Cynipidae) q-alba-red-hairy-bead-gall                         | q-alba-red-hairy-bead-gall                          |
| 2906       | Unknown (Cynipidae) q-alba-rugose-spangle                              | q-alba-rugose-spangle                               |
| 1070       | Unknown (Cynipidae) q-alba-truncate-petiole-cluster                    | q-alba-truncate-petiole-cluster                     |
| 2425       | Unknown (Cynipidae) q-arizonica-bract-bud-gall                         | q-arizonica-bract-bud-gall                          |
| 2449       | Unknown (Cynipidae) q-arizonica-burr-gall                              | q-arizonica-burr-gall                               |
| 2452       | Unknown (Cynipidae) q-arizonica-cluster-in-parenchyma                  | q-arizonica-cluster-in-parenchyma                   |
| 2455       | Unknown (Cynipidae) q-arizonica-dead-spot                              | q-arizonica-dead-spot                               |
| 2446       | Unknown (Cynipidae) q-arizonica-disk-spangle                           | q-arizonica-disk-spangle                            |
| 2436       | Unknown (Cynipidae) q-arizonica-hairy-stem-gall                        | q-arizonica-hairy-stem-gall                         |
| 2432       | Unknown (Cynipidae) q-arizonica-hollow-terminal-stem-gall              | q-arizonica-hollow-terminal-stem-gall               |
| 4491       | Unknown (Cynipidae) q-arizonica-like-opertus                           | q-arizonica-like-opertus                            |
| 2448       | Unknown (Cynipidae) q-arizonica-like-p-nigra                           | q-arizonica-like-p-nigra                            |
| 2440       | Unknown (Cynipidae) q-arizonica-like-pulchripenne-free-rolling         | q-arizonica-like-pulchripenne-free-rolling          |
| 2457       | Unknown (Cynipidae) q-arizonica-parenchyma-blister                     | q-arizonica-parenchyma-blister                      |
| 2420       | Unknown (Cynipidae) q-arizonica-red-bullet-root-cluster                | q-arizonica-red-bullet-root-cluster                 |
| 2153       | Unknown (Cynipidae) q-arizonica-rosy-tube-gall                         | q-arizonica-rosy-tube-gall                          |
| 2443       | Unknown (Cynipidae) q-arizonica-woolly-midrib-elongate-cluster         | q-arizonica-woolly-midrib-elongate-cluster          |
| 3609       | Unknown (Cynipidae) q-berberidifolia-flying-saucer-gall                | q-berberidifolia-flying-saucer-gall                 |
| 3045       | Unknown (Cynipidae) q-berberidifolia-globular-bud-gall                 | q-berberidifolia-globular-bud-gall                  |
| 4883       | Unknown (Cynipidae) q-berberidifolia-hairy-spring-gall                 | q-berberidifolia-hairy-spring-gall                  |
| 5703       | Unknown (Cynipidae) q-berberidifolia-honeydew-bud-gall                 | q-berberidifolia-honeydew-bud-gall                  |
| 4177       | Unknown (Cynipidae) q-berberidifolia-tapered-leaf-gall                 | q-berberidifolia-tapered-leaf-gall                  |
| 1039       | Unknown (Cynipidae) q-bicolor-acorn-cup-gall                           | q-bicolor-acorn-cup-gall                            |
| 1074       | Unknown (Cynipidae) q-breviloba-cup-gall                               | q-breviloba-cup-gall                                |
| 1075       | Unknown (Cynipidae) q-breviloba-spangle-gall                           | q-breviloba-spangle-gall                            |
| 1154       | Unknown (Cynipidae) q-buckleyi-horned-dropping                         | q-buckleyi-horned-dropping                          |
| 4261       | Unknown (Cynipidae) q-buckleyi-woolly-gall                             | q-buckleyi-woolly-gall                              |
| 5619       | Unknown (Cynipidae) q-castanea-like-howertoni                          | q-castanea-like-howertoni                           |
| 5618       | Unknown (Cynipidae) q-castanea-stem-swelling                           | q-castanea-stem-swelling                            |
| 1069       | Unknown (Cynipidae) q-chapmanii-cell-in-wood                           | q-chapmanii-cell-in-wood                            |
| 1045       | Unknown (Cynipidae) q-chapmanii-fusiform-flower-gall                   | q-chapmanii-fusiform-flower-gall                    |
| 1046       | Unknown (Cynipidae) q-chapmanii-green-axil-gall                        | q-chapmanii-green-axil-gall                         |
| 1040       | Unknown (Cynipidae) q-chapmanii-pip-gall                               | q-chapmanii-pip-gall                                |
| 2411       | Unknown (Cynipidae) q-chrysolepis-acorn-hidden-cell                    | q-chrysolepis-acorn-hidden-cell                     |
| 2051       | Unknown (Cynipidae) q-chrysolepis-ball-gall                            | q-chrysolepis-ball-gall                             |
| 2015       | Unknown (Cynipidae) q-chrysolepis-bent-stem-gall                       | q-chrysolepis-bent-stem-gall                        |
| 2034       | Unknown (Cynipidae) q-chrysolepis-bristly-pear-gall                    | q-chrysolepis-bristly-pear-gall                     |
| 2142       | Unknown (Cynipidae) q-chrysolepis-bud-gall                             | q-chrysolepis-bud-gall                              |
| 2049       | Unknown (Cynipidae) q-chrysolepis-clustered-blister-gall               | q-chrysolepis-clustered-blister-gall                |
| 2018       | Unknown (Cynipidae) q-chrysolepis-cotton-candy-gall                    | q-chrysolepis-cotton-candy-gall                     |
| 2403       | Unknown (Cynipidae) q-chrysolepis-cream-spangles-in-row                | q-chrysolepis-cream-spangles-in-row                 |
| 2144       | Unknown (Cynipidae) q-chrysolepis-dead-bud-scales                      | q-chrysolepis-dead-bud-scales                       |
| 2050       | Unknown (Cynipidae) q-chrysolepis-fluted-gall                          | q-chrysolepis-fluted-gall                           |
| 2796       | Unknown (Cynipidae) q-chrysolepis-free-rolling-cell-gall               | q-chrysolepis-free-rolling-cell-gall                |
| 2032       | Unknown (Cynipidae) q-chrysolepis-funnel-gall                          | q-chrysolepis-funnel-gall                           |
| 2503       | Unknown (Cynipidae) q-chrysolepis-fusiform-bud-gall                    | q-chrysolepis-fusiform-bud-gall                     |
| 5442       | Unknown (Cynipidae) q-chrysolepis-fuzzy-cushion-on-pedestal            | q-chrysolepis-fuzzy-cushion-on-pedestal             |
| 2669       | Unknown (Cynipidae) q-chrysolepis-globular-root-cluster                | q-chrysolepis-globular-root-cluster                 |
| 2061       | Unknown (Cynipidae) q-chrysolepis-granulate-bead-gall                  | q-chrysolepis-granulate-bead-gall                   |
| 2063       | Unknown (Cynipidae) q-chrysolepis-hairy-bead-gall                      | q-chrysolepis-hairy-bead-gall                       |
| 2067       | Unknown (Cynipidae) q-chrysolepis-hairy-integral-bead-gall             | q-chrysolepis-hairy-integral-bead-gall              |
| 2052       | Unknown (Cynipidae) q-chrysolepis-hairy-mushroom-gall                  | q-chrysolepis-hairy-mushroom-gall                   |
| 2066       | Unknown (Cynipidae) q-chrysolepis-hairy-tip-leaf-gall                  | q-chrysolepis-hairy-tip-leaf-gall                   |
| 2914       | Unknown (Cynipidae) q-chrysolepis-hidden-cells                         | q-chrysolepis-hidden-cells                          |
| 2136       | Unknown (Cynipidae) q-chrysolepis-hollow-twig-swelling                 | q-chrysolepis-hollow-twig-swelling                  |
| 2502       | Unknown (Cynipidae) q-chrysolepis-pip-gall                             | q-chrysolepis-pip-gall                              |
| 2795       | Unknown (Cynipidae) q-chrysolepis-scattered-cells                      | q-chrysolepis-scattered-cells                       |
| 1743       | Unknown (Cynipidae) q-chrysolepis-smooth-stamen-gall                   | q-chrysolepis-smooth-stamen-gall                    |
| 3745       | Unknown (Cynipidae) q-chrysolepis-spurred-cup-gall                     | q-chrysolepis-spurred-cup-gall                      |
| 2031       | Unknown (Cynipidae) q-chrysolepis-starburst-gall                       | q-chrysolepis-starburst-gall                        |
| 5123       | Unknown (Cynipidae) q-chrysolepis-thorn-gall                           | q-chrysolepis-thorn-gall                            |
| 5814       | Unknown (Cynipidae) q-chrysolepis-torpedo-leaf-gall                    | q-chrysolepis-torpedo-leaf-gall                     |
| 2062       | Unknown (Cynipidae) q-chrysolepis-tuberculate-bead-gall                | q-chrysolepis-tuberculate-bead-gall                 |
| 2065       | Unknown (Cynipidae) q-chrysolepis-tuberculate-cup-gall                 | q-chrysolepis-tuberculate-cup-gall                  |
| 2033       | Unknown (Cynipidae) q-chrysolepis-vein-gall                            | q-chrysolepis-vein-gall                             |
| 1165       | Unknown (Cynipidae) q-coccinea-fuzzy-leaf-gall                         | q-coccinea-fuzzy-leaf-gall                          |
| 1139       | Unknown (Cynipidae) q-coccinea-like-single-gemmaria                    | q-coccinea-like-single-gemmaria                     |
| 1597       | Unknown (Cynipidae) q-coccinea-mottled-gall                            | q-coccinea-mottled-gall                             |
| 1166       | Unknown (Cynipidae) q-coccinea-petiole-swelling                        | q-coccinea-petiole-swelling                         |
| 1138       | Unknown (Cynipidae) q-coccinea-tan-bud-gall                            | q-coccinea-tan-bud-gall                             |
| 1992       | Unknown (Cynipidae) q-cornelius-mulleri-melon-gall                     | q-cornelius-mulleri-melon-gall                      |
| 1993       | Unknown (Cynipidae) q-cornelius-mulleri-peach-gall                     | q-cornelius-mulleri-peach-gall                      |
| 1988       | Unknown (Cynipidae) q-cornelius-mulleri-pink-cone-gall                 | q-cornelius-mulleri-pink-cone-gall                  |
| 1989       | Unknown (Cynipidae) q-douglasii-basket-gall (agamic)                   | q-douglasii-basket-gall                             |
| 1950       | Unknown (Cynipidae) q-douglasii-flange-gall                            | q-douglasii-flange-gall                             |
| 5577       | Unknown (Cynipidae) q-douglasii-hidden-multicell-bud-gall              | q-douglasii-hidden-multicell-bud-gall               |
| 2413       | Unknown (Cynipidae) q-douglasii-inside-acorn                           | q-douglasii-inside-acorn                            |
| 2401       | Unknown (Cynipidae) q-douglasii-pointed-bud-gall                       | q-douglasii-pointed-bud-gall                        |
| 2802       | Unknown (Cynipidae) q-douglasii-spherical-bud-gall                     | q-douglasii-spherical-bud-gall                      |
| 3442       | Unknown (Cynipidae) q-douglasii-truncate-cone-gall                     | q-douglasii-truncate-cone-gall                      |
| 4501       | Unknown (Cynipidae) q-douglasii-vein-club                              | q-douglasii-vein-club                               |
| 2404       | Unknown (Cynipidae) q-dumosa-bell-gall                                 | q-dumosa-bell-gall                                  |
| 2804       | Unknown (Cynipidae) q-dumosa-bracted-axil-gall                         | q-dumosa-bracted-axil-gall                          |
| 2799       | Unknown (Cynipidae) q-dumosa-globular-root-gall                        | q-dumosa-globular-root-gall                         |
| 2809       | Unknown (Cynipidae) q-dumosa-greenish-purple-gall                      | q-dumosa-greenish-purple-gall                       |
| 2381       | Unknown (Cynipidae) q-dumosa-leaf-blister                              | q-dumosa-leaf-blister                               |
| 2382       | Unknown (Cynipidae) q-dumosa-lower-leaf-teardrop-gall                  | q-dumosa-lower-leaf-teardrop-gall                   |
| 1994       | Unknown (Cynipidae) q-dumosa-pip-gall                                  | q-dumosa-pip-gall                                   |
| 2803       | Unknown (Cynipidae) q-dumosa-ribbed-axil-gall                          | q-dumosa-ribbed-axil-gall                           |
| 2800       | Unknown (Cynipidae) q-dumosa-ribbed-pip-gall                           | q-dumosa-ribbed-pip-gall                            |
| 2380       | Unknown (Cynipidae) q-dumosa-small-blister-galls                       | q-dumosa-small-blister-galls                        |
| 3129       | Unknown (Cynipidae) q-emoryi-abrupt-stem-gall                          | q-emoryi-abrupt-stem-gall                           |
| 3754       | Unknown (Cynipidae) q-emoryi-bent-stem-swelling                        | q-emoryi-bent-stem-swelling                         |
| 2561       | Unknown (Cynipidae) q-emoryi-bursting-stem-gall                        | q-emoryi-bursting-stem-gall                         |
| 2298       | Unknown (Cynipidae) q-emoryi-clustered-flower-gall                     | q-emoryi-clustered-flower-gall                      |
| 2558       | Unknown (Cynipidae) q-emoryi-conical-bud-gall                          | q-emoryi-conical-bud-gall                           |
| 2568       | Unknown (Cynipidae) q-emoryi-free-rolling-cell-gall                    | q-emoryi-free-rolling-cell-gall                     |
| 2549       | Unknown (Cynipidae) q-emoryi-globular-root-gall                        | q-emoryi-globular-root-gall                         |
| 2557       | Unknown (Cynipidae) q-emoryi-hidden-bud-gall                           | q-emoryi-hidden-bud-gall                            |
| 2562       | Unknown (Cynipidae) q-emoryi-hidden-cells                              | q-emoryi-hidden-cells                               |
| 2572       | Unknown (Cynipidae) q-emoryi-like-rileyi                               | q-emoryi-like-rileyi                                |
| 2552       | Unknown (Cynipidae) q-emoryi-lop-sided-acorn                           | q-emoryi-lop-sided-acorn                            |
| 2556       | Unknown (Cynipidae) q-emoryi-tan-axil-gall                             | q-emoryi-tan-axil-gall                              |
| 2807       | Unknown (Cynipidae) q-engelmannii-like-h-devorus                       | q-engelmannii-like-h-devorus                        |
| 5635       | Unknown (Cynipidae) q-engelmannii-midrib-cell                          | q-engelmannii-midrib-cell                           |
| 1986       | Unknown (Cynipidae) q-engelmannii-truncated-cone-gall                  | q-engelmannii-truncated-cone-gall                   |
| 1146       | Unknown (Cynipidae) q-falcata-oblong-bud-gall                          | q-falcata-oblong-bud-gall                           |
| 2595       | Unknown (Cynipidae) q-gambelii-budding-stem-gall                       | q-gambelii-budding-stem-gall                        |
| 2511       | Unknown (Cynipidae) q-gambelii-conical-bud-gall                        | q-gambelii-conical-bud-gall                         |
| 2498       | Unknown (Cynipidae) q-gambelii-fleshy-cluster                          | q-gambelii-fleshy-cluster                           |
| 2535       | Unknown (Cynipidae) q-gambelii-glaucous-spangle                        | q-gambelii-glaucous-spangle                         |
| 2536       | Unknown (Cynipidae) q-gambelii-globular-midrib-cluster                 | q-gambelii-globular-midrib-cluster                  |
| 2533       | Unknown (Cynipidae) q-gambelii-gray-felt-gall                          | q-gambelii-gray-felt-gall                           |
| 4313       | Unknown (Cynipidae) q-gambelii-hairy-shoot-cluster                     | q-gambelii-hairy-shoot-cluster                      |
| 3581       | Unknown (Cynipidae) q-gambelii-hairy-spangle                           | q-gambelii-hairy-spangle                            |
| 1717       | Unknown (Cynipidae) q-gambelii-mottled-bud-gall                        | q-gambelii-mottled-bud-gall                         |
| 3441       | Unknown (Cynipidae) q-garryana-flared-base-gall                        | q-garryana-flared-base-gall                         |
| 2409       | Unknown (Cynipidae) q-garryana-hairy-flower-cell                       | q-garryana-hairy-flower-cell                        |
| 4387       | Unknown (Cynipidae) q-garryana-hazelnut-gall                           | q-garryana-hazelnut-gall                            |
| 2406       | Unknown (Cynipidae) q-garryana-open-spindle-gall                       | q-garryana-open-spindle-gall                        |
| 1991       | Unknown (Cynipidae) q-garryana-orange-cap-gall                         | q-garryana-orange-cap-gall                          |
| 2405       | Unknown (Cynipidae) q-garryana-parenchya-cells                         | q-garryana-parenchya-cells                          |
| 2383       | Unknown (Cynipidae) q-garryana-pip-gall                                | q-garryana-pip-gall                                 |
| 3634       | Unknown (Cynipidae) q-garryana-smooth-stamen-gall                      | q-garryana-smooth-stamen-gall                       |
| 1536       | Unknown (Cynipidae) q-geminata-split-stem-swelling                     | q-geminata-split-stem-swelling                      |
| 2623       | Unknown (Cynipidae) q-grisea-columnar-gall                             | q-grisea-columnar-gall                              |
| 2622       | Unknown (Cynipidae) q-grisea-round-midrib-gall                         | q-grisea-round-midrib-gall                          |
| 2591       | Unknown (Cynipidae) q-grisea-stem-gall                                 | q-grisea-stem-gall                                  |
| 4179       | Unknown (Cynipidae) q-grisea-stem-swelling                             | q-grisea-stem-swelling                              |
| 3425       | Unknown (Cynipidae) q-havardii-cup-gall                                | q-havardii-cup-gall                                 |
| 3485       | Unknown (Cynipidae) q-havardii-globular-bud-gall                       | q-havardii-globular-bud-gall                        |
| 2477       | Unknown (Cynipidae) q-havardii-white-bud-cell                          | q-havardii-white-bud-cell                           |
| 4487       | Unknown (Cynipidae) q-hemisphaerica-hairy-sphere                       | q-hemisphaerica-hairy-sphere                        |
| 2569       | Unknown (Cynipidae) q-hypoleucoides-aborted-leaf-cells                 | q-hypoleucoides-aborted-leaf-cells                  |
| 2575       | Unknown (Cynipidae) q-hypoleucoides-bead-gall                          | q-hypoleucoides-bead-gall                           |
| 2563       | Unknown (Cynipidae) q-hypoleucoides-club-gall                          | q-hypoleucoides-club-gall                           |
| 2560       | Unknown (Cynipidae) q-hypoleucoides-conical-bud-gall                   | q-hypoleucoides-conical-bud-gall                    |
| 2574       | Unknown (Cynipidae) q-hypoleucoides-cylindrical-leaf-gall              | q-hypoleucoides-cylindrical-leaf-gall               |
| 2550       | Unknown (Cynipidae) q-hypoleucoides-elongated-flower-galls             | q-hypoleucoides-elongated-flower-galls              |
| 2554       | Unknown (Cynipidae) q-hypoleucoides-fall-pip-gall                      | q-hypoleucoides-fall-pip-gall                       |
| 2570       | Unknown (Cynipidae) q-hypoleucoides-fleshy-leaf-edge-gall              | q-hypoleucoides-fleshy-leaf-edge-gall               |
| 2567       | Unknown (Cynipidae) q-hypoleucoides-melon-cluster                      | q-hypoleucoides-melon-cluster                       |
| 2555       | Unknown (Cynipidae) q-hypoleucoides-spring-pip-gall                    | q-hypoleucoides-spring-pip-gall                     |
| 2571       | Unknown (Cynipidae) q-hypoleucoides-thickened-parenchyma               | q-hypoleucoides-thickened-parenchyma                |
| 2576       | Unknown (Cynipidae) q-hypoleucoides-woolly-midrib-cluster              | q-hypoleucoides-woolly-midrib-cluster               |
| 1248       | Unknown (Cynipidae) q-ilicifolia-fuzzy-yellow-spangle                  | q-ilicifolia-fuzzy-yellow-spangle                   |
| 1149       | Unknown (Cynipidae) q-imbricaria-horned-bursting-gall                  | q-imbricaria-horned-bursting-gall                   |
| 1122       | Unknown (Cynipidae) q-imbricaria-like-balanoides                       | q-imbricaria-like-balanoides                        |
| 4259       | Unknown (Cynipidae) q-imbricaria-nipple-gall (sexgen)                  | q-imbricaria-nipple-gall                            |
| 1157       | Unknown (Cynipidae) q-imbricaria-numerous-ellipsoidal-galls            | q-imbricaria-numerous-ellipsoidal-galls             |
| 1135       | Unknown (Cynipidae) q-incana-green-bud-gall                            | q-incana-green-bud-gall                             |
| 1136       | Unknown (Cynipidae) q-incana-hidden-bud-gall                           | q-incana-hidden-bud-gall                            |
| 3386       | Unknown (Cynipidae) q-john-tuckeri-pink-leaf-gall                      | q-john-tuckeri-pink-leaf-gall                       |
| 2417       | Unknown (Cynipidae) q-kelloggii-bud-scale-blister                      | q-kelloggii-bud-scale-blister                       |
| 2699       | Unknown (Cynipidae) q-kelloggii-free-rolling-cell-gall                 | q-kelloggii-free-rolling-cell-gall                  |
| 2698       | Unknown (Cynipidae) q-kelloggii-leaf-scar-swelling                     | q-kelloggii-leaf-scar-swelling                      |
| 3747       | Unknown (Cynipidae) q-kelloggii-stem-club                              | q-kelloggii-stem-club                               |
| 1062       | Unknown (Cynipidae) q-laceyi-blister-gall                              | q-laceyi-blister-gall                               |
| 1060       | Unknown (Cynipidae) q-laceyi-root-crown-cluster                        | q-laceyi-root-crown-cluster                         |
| 4202       | Unknown (Cynipidae) q-laceyi-stem-swelling                             | q-laceyi-stem-swelling                              |
| 1134       | Unknown (Cynipidae) q-laevis-hidden-bud-cell                           | q-laevis-hidden-bud-cell                            |
| 1133       | Unknown (Cynipidae) q-laevis-white-bud-gall                            | q-laevis-white-bud-gall                             |
| 1123       | Unknown (Cynipidae) q-laurifolia-like-fructuosa                        | q-laurifolia-like-fructuosa                         |
| 5704       | Unknown (Cynipidae) q-lobata-clustered-capsules                        | q-lobata-clustered-capsules                         |
| 1944       | Unknown (Cynipidae) q-lobata-mini-leaf-gall                            | q-lobata-mini-leaf-gall                             |
| 3748       | Unknown (Cynipidae) q-lobata-vein-blister                              | q-lobata-vein-blister                               |
| 4188       | Unknown (Cynipidae) q-macrocarpa-acorn-cup-gall                        | q-macrocarpa-acorn-cup-gall                         |
| 3258       | Unknown (Cynipidae) q-macrocarpa-acorn-pip-gall                        | q-macrocarpa-acorn-pip-gall                         |
| 4916       | Unknown (Cynipidae) q-macrocarpa-bud-cells (sexgen)                    | q-macrocarpa-bud-cells                              |
| 1066       | Unknown (Cynipidae) q-macrocarpa-cells-under-bark                      | q-macrocarpa-cells-under-bark                       |
| 2910       | Unknown (Cynipidae) q-macrocarpa-like-a-robustus                       | q-macrocarpa-like-a-robustus                        |
| 2187       | Unknown (Cynipidae) q-macrocarpa-mottled-bud-gall                      | q-macrocarpa-mottled-bud-gall                       |
| 3583       | Unknown (Cynipidae) q-macrocarpa-petiole-cluster                       | q-macrocarpa-petiole-cluster                        |
| 1048       | Unknown (Cynipidae) q-macrocarpa-ribbed-bud-gall                       | q-macrocarpa-ribbed-bud-gall                        |
| 1051       | Unknown (Cynipidae) q-macrocarpa-stem-swelling                         | q-macrocarpa-stem-swelling                          |
| 4224       | Unknown (Cynipidae) q-macrocarpa-thick-vein                            | q-macrocarpa-thick-vein                             |
| 4204       | Unknown (Cynipidae) q-macrocarpa-vein-blisters                         | q-macrocarpa-vein-blisters                          |
| 1156       | Unknown (Cynipidae) q-marilandica-bark-blister                         | q-marilandica-bark-blister                          |
| 3276       | Unknown (Cynipidae) q-marilandica-cone-topped-stem-gall                | q-marilandica-cone-topped-stem-gall                 |
| 1131       | Unknown (Cynipidae) q-marilandica-hemispherical-swellings              | q-marilandica-hemispherical-swellings               |
| 1141       | Unknown (Cynipidae) q-marilandica-hidden-bud-gall                      | q-marilandica-hidden-bud-gall                       |
| 2947       | Unknown (Cynipidae) q-marilandica-like-k-rileyi-between-vein           | q-marilandica-like-k-rileyi-between-vein            |
| 1168       | Unknown (Cynipidae) q-marilandica-like-utriculus                       | q-marilandica-like-utriculus                        |
| 2836       | Unknown (Cynipidae) q-marilandica-spike-gall                           | q-marilandica-spike-gall                            |
| 1132       | Unknown (Cynipidae) q-marilandica-spindle-swelling                     | q-marilandica-spindle-swelling                      |
| 3078       | Unknown (Cynipidae) q-mohriana-midrib-cluster                          | q-mohriana-midrib-cluster                           |
| 1262       | Unknown (Cynipidae) q-montana-fuzzy-sphere-cluster (agamic)            | q-montana-fuzzy-sphere-cluster                      |
| 1104       | Unknown (Cynipidae) q-montana-like-C-bipapillata                       | q-montana-like-C-bipapillata                        |
| 1078       | Unknown (Cynipidae) q-muehlenbergii-straight-sigma-gall                | q-muehlenbergii-straight-sigma-gall                 |
| 1125       | Unknown (Cynipidae) q-myrtifolia-stone-gall                            | q-myrtifolia-stone-gall                             |
| 4161       | Unknown (Cynipidae) q-nigra-arrowhead-gall (sexgen)                    | q-nigra-arrowhead-gall                              |
| 1142       | Unknown (Cynipidae) q-nigra-tan-axil-gall                              | q-nigra-tan-axil-gall                               |
| 4590       | Unknown (Cynipidae) q-nigra-woody-ribbed-gall                          | q-nigra-woody-ribbed-gall                           |
| 2461       | Unknown (Cynipidae) q-oblongifolia-acorn-cup                           | q-oblongifolia-acorn-cup                            |
| 2463       | Unknown (Cynipidae) q-oblongifolia-black-bud-gall                      | q-oblongifolia-black-bud-gall                       |
| 2466       | Unknown (Cynipidae) q-oblongifolia-conical-bud-gall                    | q-oblongifolia-conical-bud-gall                     |
| 2467       | Unknown (Cynipidae) q-oblongifolia-cracking-stem-swelling              | q-oblongifolia-cracking-stem-swelling               |
| 2307       | Unknown (Cynipidae) q-oblongifolia-crystal-gall                        | q-oblongifolia-crystal-gall                         |
| 2171       | Unknown (Cynipidae) q-oblongifolia-egg-gall                            | q-oblongifolia-egg-gall                             |
| 2597       | Unknown (Cynipidae) q-oblongifolia-erupted-gall                        | q-oblongifolia-erupted-gall                         |
| 2476       | Unknown (Cynipidae) q-oblongifolia-fimbriate-midrib-cell               | q-oblongifolia-fimbriate-midrib-cell                |
| 2464       | Unknown (Cynipidae) q-oblongifolia-gray-pubescent-bud-gall             | q-oblongifolia-gray-pubescent-bud-gall              |
| 2469       | Unknown (Cynipidae) q-oblongifolia-large-white-bullet                  | q-oblongifolia-large-white-bullet                   |
| 2299       | Unknown (Cynipidae) q-oblongifolia-leafy-flower-gall                   | q-oblongifolia-leafy-flower-gall                    |
| 3128       | Unknown (Cynipidae) q-oblongifolia-little-red-cup-gall                 | q-oblongifolia-little-red-cup-gall                  |
| 2251       | Unknown (Cynipidae) q-oblongifolia-little-teardrop-gall                | q-oblongifolia-little-teardrop-gall                 |
| 2462       | Unknown (Cynipidae) q-oblongifolia-lopsided-acorn                      | q-oblongifolia-lopsided-acorn                       |
| 2220       | Unknown (Cynipidae) q-oblongifolia-midrib-gall                         | q-oblongifolia-midrib-gall                          |
| 2592       | Unknown (Cynipidae) q-oblongifolia-necked-puzzle-gall                  | q-oblongifolia-necked-puzzle-gall                   |
| 2594       | Unknown (Cynipidae) q-oblongifolia-petiole-gall                        | q-oblongifolia-petiole-gall                         |
| 2473       | Unknown (Cynipidae) q-oblongifolia-pubescent-spheres                   | q-oblongifolia-pubescent-spheres                    |
| 2218       | Unknown (Cynipidae) q-oblongifolia-red-topped-cup-gall                 | q-oblongifolia-red-topped-cup-gall                  |
| 2468       | Unknown (Cynipidae) q-oblongifolia-swelling-base-branches              | q-oblongifolia-swelling-base-branches               |
| 4621       | Unknown (Cynipidae) q-oblongifolia-woolly-leaf-fold-gall               | q-oblongifolia-woolly-leaf-fold-gall                |
| 5616       | Unknown (Cynipidae) q-obtusata-petiole-thorn-gall                      | q-obtusata-petiole-thorn-gall                       |
| 5617       | Unknown (Cynipidae) q-obtusata-pink-cylinder-gall                      | q-obtusata-pink-cylinder-gall                       |
| 5612       | Unknown (Cynipidae) q-obtusata-thin-walled-stem-gall                   | q-obtusata-thin-walled-stem-gall                    |
| 5610       | Unknown (Cynipidae) q-obtusata-wooly-petiole-cluster                   | q-obtusata-wooly-petiole-cluster                    |
| 2058       | Unknown (Cynipidae) q-palmeri-bulb-gall                                | q-palmeri-bulb-gall                                 |
| 2056       | Unknown (Cynipidae) q-palmeri-lumpy-gall                               | q-palmeri-lumpy-gall                                |
| 2057       | Unknown (Cynipidae) q-palmeri-pumpkin-gall                             | q-palmeri-pumpkin-gall                              |
| 2016       | Unknown (Cynipidae) q-palmeri-spindle-gall                             | q-palmeri-spindle-gall                              |
| 2017       | Unknown (Cynipidae) q-palmeri-squash-neck-gall                         | q-palmeri-squash-neck-gall                          |
| 2070       | Unknown (Cynipidae) q-palmeri-uneven-spangle-gall                      | q-palmeri-uneven-spangle-gall                       |
| 5727       | Unknown (Cynipidae) q-palustris-midrib-ridge                           | q-palustris-midrib-ridge                            |
| 4260       | Unknown (Cynipidae) q-palustris-small-bud-gall                         | q-palustris-small-bud-gall                          |
| 1152       | Unknown (Cynipidae) q-palustris-spindle-cluster                        | q-palustris-spindle-cluster                         |
| 4813       | Unknown (Cynipidae) q-peduncularis-stalked-gall                        | q-peduncularis-stalked-gall                         |
| 4164       | Unknown (Cynipidae) q-phellos-fletching-bud-gall                       | q-phellos-fletching-bud-gall                        |
| 5821       | Unknown (Cynipidae) q-phellos-flower-pip-gall                          | q-phellos-flower-pip-gall                           |
| 1162       | Unknown (Cynipidae) q-phellos-globular-row-leaf-gall                   | q-phellos-globular-row-leaf-gall                    |
| 3506       | Unknown (Cynipidae) q-phellos-hairy-flower-gall                        | q-phellos-hairy-flower-gall                         |
| 4246       | Unknown (Cynipidae) q-phellos-hellmouth-gall                           | q-phellos-hellmouth-gall                            |
| 1161       | Unknown (Cynipidae) q-phellos-leaf-club                                | q-phellos-leaf-club                                 |
| 4262       | Unknown (Cynipidae) q-phellos-lemon-gall                               | q-phellos-lemon-gall                                |
| 1127       | Unknown (Cynipidae) q-phellos-pip-gall                                 | q-phellos-pip-gall                                  |
| 4191       | Unknown (Cynipidae) q-phellos-prune-gall                               | q-phellos-prune-gall                                |
| 1163       | Unknown (Cynipidae) q-phellos-white-globular-leaf-gall                 | q-phellos-white-globular-leaf-gall                  |
| 5621       | Unknown (Cynipidae) q-polymorpha-scattered-leaf-spots                  | q-polymorpha-scattered-leaf-spots                   |
| 1067       | Unknown (Cynipidae) q-prinoides-cells-under-bark                       | q-prinoides-cells-under-bark                        |
| 1058       | Unknown (Cynipidae) q-prinoides-stem-cluster-gall                      | q-prinoides-stem-cluster-gall                       |
| 4721       | Unknown (Cynipidae) q-pungens-mottled-stem-gall                        | q-pungens-mottled-stem-gall                         |
| 4722       | Unknown (Cynipidae) q-pungens-red-stem-bullet                          | q-pungens-red-stem-bullet                           |
| 1171       | Unknown (Cynipidae) q-rubra-cinereae-without-cell                      | q-rubra-cinereae-without-cell                       |
| 1249       | Unknown (Cynipidae) q-rubra-globular-vein-gall                         | q-rubra-globular-vein-gall                          |
| 3228       | Unknown (Cynipidae) q-rubra-hairy-cluster                              | q-rubra-hairy-cluster                               |
| 1153       | Unknown (Cynipidae) q-rubra-like-gemmaria                              | q-rubra-like-gemmaria                               |
| 4311       | Unknown (Cynipidae) q-rubra-ribbed-crown-gall                          | q-rubra-ribbed-crown-gall                           |
| 1330       | Unknown (Cynipidae) q-rubra-stellate-bud-gall                          | q-rubra-stellate-bud-gall                           |
| 1172       | Unknown (Cynipidae) q-rubra-thin-midrib-cell                           | q-rubra-thin-midrib-cell                            |
| 2493       | Unknown (Cynipidae) q-rugosa-abrupt-cluster                            | q-rugosa-abrupt-cluster                             |
| 2495       | Unknown (Cynipidae) q-rugosa-acorn-cup-gall                            | q-rugosa-acorn-cup-gall                             |
| 2508       | Unknown (Cynipidae) q-rugosa-axil-gall                                 | q-rugosa-axil-gall                                  |
| 2527       | Unknown (Cynipidae) q-rugosa-bullet-with-loose-cell                    | q-rugosa-bullet-with-loose-cell                     |
| 2545       | Unknown (Cynipidae) q-rugosa-cells-deforming-spring-leaf               | q-rugosa-cells-deforming-spring-leaf                |
| 2532       | Unknown (Cynipidae) q-rugosa-funnel-gall                               | q-rugosa-funnel-gall                                |
| 3790       | Unknown (Cynipidae) q-rugosa-hairy-cup-gall                            | q-rugosa-hairy-cup-gall                             |
| 2531       | Unknown (Cynipidae) q-rugosa-small-oak-apple                           | q-rugosa-small-oak-apple                            |
| 2518       | Unknown (Cynipidae) q-rugosa-terminal-club                             | q-rugosa-terminal-club                              |
| 4843       | Unknown (Cynipidae) q-sadleriana-leaf-blister                          | q-sadleriana-leaf-blister                           |
| 4492       | Unknown (Cynipidae) q-shumardii-midrib-swelling                        | q-shumardii-midrib-swelling                         |
| 4940       | Unknown (Cynipidae) q-sinuata-strawberry-gall                          | q-sinuata-strawberry-gall                           |
| 1082       | Unknown (Cynipidae) q-stellata-nipple-spangle                          | q-stellata-nipple-spangle                           |
| 1049       | Unknown (Cynipidae) q-stellata-oblong-bud-gall                         | q-stellata-oblong-bud-gall                          |
| 4247       | Unknown (Cynipidae) q-stellata-red-bud-gall                            | q-stellata-red-bud-gall                             |
| 1050       | Unknown (Cynipidae) q-stellata-round-bud-gall                          | q-stellata-round-bud-gall                           |
| 3260       | Unknown (Cynipidae) q-stellata-spotted-bud-gall                        | q-stellata-spotted-bud-gall                         |
| 1068       | Unknown (Cynipidae) q-stellata-under-bark-gall                         | q-stellata-under-bark-gall                          |
| 2509       | Unknown (Cynipidae) q-toumeyi-bluish-fleshy-bud-gall                   | q-toumeyi-bluish-fleshy-bud-gall                    |
| 2479       | Unknown (Cynipidae) q-toumeyi-conical-bud-gall                         | q-toumeyi-conical-bud-gall                          |
| 2483       | Unknown (Cynipidae) q-toumeyi-elongated-prolonged-vein                 | q-toumeyi-elongated-prolonged-vein                  |
| 2482       | Unknown (Cynipidae) q-toumeyi-tan-bead-gall                            | q-toumeyi-tan-bead-gall                             |
| 2544       | Unknown (Cynipidae) q-turbinella-bell-midrib-gall                      | q-turbinella-bell-midrib-gall                       |
| 2596       | Unknown (Cynipidae) q-turbinella-bullet-gall                           | q-turbinella-bullet-gall                            |
| 2497       | Unknown (Cynipidae) q-turbinella-cell-in-acorn-cup                     | q-turbinella-cell-in-acorn-cup                      |
| 2512       | Unknown (Cynipidae) q-turbinella-conical-bud-gall                      | q-turbinella-conical-bud-gall                       |
| 2513       | Unknown (Cynipidae) q-turbinella-ellipsoid-bud-gall                    | q-turbinella-ellipsoid-bud-gall                     |
| 2609       | Unknown (Cynipidae) q-turbinella-fuzzy-leaf-gall                       | q-turbinella-fuzzy-leaf-gall                        |
| 2624       | Unknown (Cynipidae) q-turbinella-green-urchin-gall                     | q-turbinella-green-urchin-gall                      |
| 2548       | Unknown (Cynipidae) q-turbinella-hairless-midrib-swelling              | q-turbinella-hairless-midrib-swelling               |
| 2625       | Unknown (Cynipidae) q-turbinella-hairy-cup-gall                        | q-turbinella-hairy-cup-gall                         |
| 2593       | Unknown (Cynipidae) q-turbinella-hairy-stem-gall                       | q-turbinella-hairy-stem-gall                        |
| 2516       | Unknown (Cynipidae) q-turbinella-hidden-bud-cell                       | q-turbinella-hidden-bud-cell                        |
| 4190       | Unknown (Cynipidae) q-turbinella-little-hut-gall                       | q-turbinella-little-hut-gall                        |
| 2598       | Unknown (Cynipidae) q-turbinella-lopsided-stem-gall                    | q-turbinella-lopsided-stem-gall                     |
| 2542       | Unknown (Cynipidae) q-turbinella-red-hairy-sphere                      | q-turbinella-red-hairy-sphere                       |
| 2528       | Unknown (Cynipidae) q-turbinella-ribbed-bullet                         | q-turbinella-ribbed-bullet                          |
| 2522       | Unknown (Cynipidae) q-turbinella-shortened-stem-swelling               | q-turbinella-shortened-stem-swelling                |
| 2610       | Unknown (Cynipidae) q-turbinella-small-urn-gall                        | q-turbinella-small-urn-gall                         |
| 2541       | Unknown (Cynipidae) q-turbinella-small-white-spheres                   | q-turbinella-small-white-spheres                    |
| 2515       | Unknown (Cynipidae) q-turbinella-thick-base-bud-gall                   | q-turbinella-thick-base-bud-gall                    |
| 2022       | Unknown (Cynipidae) q-turbinella-thistle-head-bud-gall                 | q-turbinella-thistle-head-bud-gall                  |
| 2540       | Unknown (Cynipidae) q-turbinella-tuberculate-spangle                   | q-turbinella-tuberculate-spangle                    |
| 4180       | Unknown (Cynipidae) q-turbinella-wedge-gall (agamic)                   | q-turbinella-wedge-gall                             |
| 4312       | Unknown (Cynipidae) q-undulata-cylindrical-root-gall                   | q-undulata-cylindrical-root-gall                    |
| 2008       | Unknown (Cynipidae) q-vacciniifolia-flower-gall                        | q-vacciniifolia-flower-gall                         |
| 2053       | Unknown (Cynipidae) q-vacciniifolia-little-cup-gall                    | q-vacciniifolia-little-cup-gall                     |
| 2054       | Unknown (Cynipidae) q-vacciniifolia-little-green-apple-gall            | q-vacciniifolia-little-green-apple-gall             |
| 2055       | Unknown (Cynipidae) q-vacciniifolia-petiole-gall                       | q-vacciniifolia-petiole-gall                        |
| 4749       | Unknown (Cynipidae) q-vaseyana-leaf-midrib-apple                       | q-vaseyana-leaf-midrib-apple                        |
| 1261       | Unknown (Cynipidae) q-velutina-fuzzy-vein-globs                        | q-velutina-fuzzy-vein-globs                         |
| 1144       | Unknown (Cynipidae) q-velutina-melon-bud-gall                          | q-velutina-melon-bud-gall                           |
| 1105       | Unknown (Cynipidae) q-virginiana-acorn-gall                            | q-virginiana-acorn-gall                             |
| 1106       | Unknown (Cynipidae) q-virginiana-hollow-bud-gall                       | q-virginiana-hollow-bud-gall                        |
| 4309       | Unknown (Cynipidae) q-virginiana-midrib-cell (sexgen)                  | q-virginiana-midrib-cell                            |
| 1059       | Unknown (Cynipidae) q-virginiana-root-gall                             | q-virginiana-root-gall                              |
| 1108       | Unknown (Cynipidae) q-virginiana-white-cell-twig-swelling              | q-virginiana-white-cell-twig-swelling               |
| 4288       | Unknown (Cynipidae) q-virginiana-young-acorn-cell                      | q-virginiana-young-acorn-cell                       |
| 2139       | Unknown (Cynipidae) q-wislizeni-bent-stem-swelling                     | q-wislizeni-bent-stem-swelling                      |
| 2138       | Unknown (Cynipidae) q-wislizeni-stem-swelling                          | q-wislizeni-stem-swelling                           |
| 1358       | Unknown (Cynipidae) red-oak-flat-disc-gall                             | red-oak-flat-disc-gall                              |
| 1367       | Unknown (Cynipidae) red-oak-fringed-gall (agamic)                      | red-oak-fringed-gall                                |
| 1344       | Unknown (Cynipidae) red-oak-fuzzy-red-globs                            | red-oak-fuzzy-red-globs                             |
| 3142       | Unknown (Cynipidae) rubus-like-d-rosae                                 | rubus-like-d-rosae                                  |
| 4879       | Unknown (Cynipidae) s-perfoliatum-stem-cluster                         | s-perfoliatum-stem-cluster                          |
| 2414       | Unknown (Cynipidae) white-oak-yellow-bud-gall                          | white-oak-yellow-bud-gall                           |
| 4103       | Unknown (Eriophyidae) a-grandidentatum-upper-leaf-erineum              | a-grandidentatum-upper-leaf-erineum                 |
| 2729       | Unknown (Eriophyidae) a-phleoides-pouch-gall                           | a-phleoides-pouch-gall                              |
| 5101       | Unknown (Eriophyidae) a-tilesii-cone-gall                              | a-tilesii-cone-gall                                 |
| 2271       | Unknown (Eriophyidae) arizona-white-oak-erineum                        | arizona-white-oak-erineum                           |
| 3586       | Unknown (Eriophyidae) b-alicastrum-leaf-gall                           | b-alicastrum-leaf-gall                              |
| 3286       | Unknown (Eriophyidae) b-alleghaniensis-upper-leaf-erineum              | b-alleghaniensis-upper-leaf-erineum                 |
| 4105       | Unknown (Eriophyidae) b-javanica-leaf-blister                          | b-javanica-leaf-blister                             |
| 2958       | Unknown (Eriophyidae) b-michauxii-leaf-erineum                         | b-michauxii-leaf-erineum                            |
| 3289       | Unknown (Eriophyidae) b-neoalaskana-erineum                            | b-neoalaskana-erineum                               |
| 5481       | Unknown (Eriophyidae) b-neoalaskana-small-red-pustules                 | b-neoalaskana-small-red-pustules                    |
| 5748       | Unknown (Eriophyidae) c-cordulatus-hairy-bead-galls                    | c-cordulatus-hairy-bead-galls                       |
| 4182       | Unknown (Eriophyidae) c-diphylla-bead-gall                             | c-diphylla-bead-gall                                |
| 4102       | Unknown (Eriophyidae) c-douglasii-lower-leaf-erineum                   | c-douglasii-lower-leaf-erineum                      |
| 3310       | Unknown (Eriophyidae) c-hookeri-conical-leaf-gall                      | c-hookeri-conical-leaf-gall                         |
| 5567       | Unknown (Eriophyidae) c-verticillata-bead-galls                        | c-verticillata-bead-galls                           |
| 1606       | Unknown (Eriophyidae) cedar-elm-fuzzy-gall                             | cedar-elm-fuzzy-gall                                |
| 1101       | Unknown (Eriophyidae) d-texana-blister-gall                            | d-texana-blister-gall                               |
| 2359       | Unknown (Eriophyidae) e-purpurea-rosette-mite                          | e-purpurea-rosette-mite                             |
| 3977       | Unknown (Eriophyidae) f-dipetala-leaf-curl                             | f-dipetala-leaf-curl                                |
| 5384       | Unknown (Eriophyidae) j-nigra-blister-gall                             | j-nigra-blister-gall                                |
| 3303       | Unknown (Eriophyidae) m-capitata-leaf-blister                          | m-capitata-leaf-blister                             |
| 4384       | Unknown (Eriophyidae) m-fusca-pink-erineum                             | m-fusca-pink-erineum                                |
| 5743       | Unknown (Eriophyidae) n-hastatus-leaf-curl                             | n-hastatus-leaf-curl                                |
| 3651       | Unknown (Eriophyidae) p-carolinensis-bead-gall                         | p-carolinensis-bead-gall                            |
| 2323       | Unknown (Eriophyidae) p-integrifolium-erineum-blisters                 | p-integrifolium-erineum-blisters                    |
| 3513       | Unknown (Eriophyidae) potentilla-bead-gall                             | potentilla-bead-gall                                |
| 2689       | Unknown (Eriophyidae) q-engelmannii-erineum-gall                       | q-engelmannii-erineum-gall                          |
| 3106       | Unknown (Eriophyidae) q-ilicifolia-erineum-blister                     | q-ilicifolia-erineum-blister                        |
| 1118       | Unknown (Eriophyidae) q-myrtifolia-erineum-mite                        | q-myrtifolia-erineum-mite                           |
| 5725       | Unknown (Eriophyidae) r-alnifolia-bead-leaf-gall                       | r-alnifolia-bead-leaf-gall                          |
| 2740       | Unknown (Eriophyidae) r-flagellaris-bead-gall                          | r-flagellaris-bead-gall                             |
| 3314       | Unknown (Eriophyidae) r-nevadense-bead-gall                            | r-nevadense-bead-gall                               |
| 2684       | Unknown (Eriophyidae) r-viscosissimum-leaf-gall                        | r-viscosissimum-leaf-gall                           |
| 3145       | Unknown (Eriophyidae) s-alaxensis-pouch-gall                           | s-alaxensis-pouch-gall                              |
| 3702       | Unknown (Eriophyidae) s-alba-capsule-gall                              | s-alba-capsule-gall                                 |
| 3699       | Unknown (Eriophyidae) s-alba-edge-roll                                 | s-alba-edge-roll                                    |
| 3701       | Unknown (Eriophyidae) s-amygdaloides-red-pocket-gall                   | s-amygdaloides-red-pocket-gall                      |
| 3154       | Unknown (Eriophyidae) s-barclayi-club-gall                             | s-barclayi-club-gall                                |
| 3632       | Unknown (Eriophyidae) s-discolor-vein-gall                             | s-discolor-vein-gall                                |
| 3703       | Unknown (Eriophyidae) s-eriocephala-capsule-gall                       | s-eriocephala-capsule-gall                          |
| 1182       | Unknown (Eriophyidae) s-lanuginosum-bead-gall                          | s-lanuginosum-bead-gall                             |
| 3854       | Unknown (Eriophyidae) s-reticulata-tuft-gall                           | s-reticulata-tuft-gall                              |
| 3293       | Unknown (Eriophyidae) s-sitchensis-hairy-bead-gall                     | s-sitchensis-hairy-bead-gall                        |
| 2259       | Unknown (Eriophyidae) s-tridentata-red-pouch-gall                      | s-tridentata-red-pouch-gall                         |
| 3648       | Unknown (Eriophyidae) salix-edge-roll                                  | salix-edge-roll                                     |
| 3700       | Unknown (Eriophyidae) salix-midrib-fold                                | salix-midrib-fold                                   |
| 3042       | Unknown (Eriophyidae) salix-wavy-edge-curl                             | salix-wavy-edge-curl                                |
| 4195       | Unknown (Eriophyidae) u-crassifolia-wart-gall                          | u-crassifolia-wart-gall                             |
| 3147       | Unknown (Eriophyidae) ulmus-globular-leaf-gall                         | ulmus-globular-leaf-gall                            |
| 5699       | Unknown (Eriophyidae) w-acapulcensis-erineum                           | w-acapulcensis-erineum                              |
| 3059       | Unknown (Pseudococcidae) ambrosia-mealybug-leaf-curl                   | ambrosia-mealybug-leaf-curl                         |
| 3482       | Unknown (Pucciniaceae) a-subverticillata-rust-gall                     | a-subverticillata-rust-gall                         |
| 2682       | Unknown (Pucciniaceae) h-fraseri-leaf-rust                             | h-fraseri-leaf-rust                                 |
| 2253       | Unknown (Pucciniaceae) hypericum-ring-rust                             | hypericum-ring-rust                                 |
| 3058       | Unknown (Pucciniaceae) rudbeckia-leaf-rust                             | rudbeckia-leaf-rust                                 |
| 2320       | Unknown (Tanaostigmatidae) s-greggii-petiole-gall                      | s-greggii-petiole-gall                              |
| 3627       | Unknown (Tenthredinidae) salix-midrib-gall                             | salix-midrib-gall                                   |
| 5164       | Unknown (Tephritidae) e-nauseosa-peduncle-gall                         | e-nauseosa-peduncle-gall                            |
| 3375       | Unknown (Tephritidae) s-drummondii-rosette                             | s-drummondii-rosette                                |
| 5492       | Unknown (Unknown) a-alnifolia-midrib-pinch-and-fold                    | a-alnifolia-midrib-pinch-and-fold                   |
| 3292       | Unknown (Unknown) a-americanus-witches-broom                           | a-americanus-witches-broom                          |
| 6005       | Unknown (Unknown) a-andersonii-leaf-blister                            | a-andersonii-leaf-blister                           |
| 5435       | Unknown (Unknown) a-californica-bud-gall                               | a-californica-bud-gall                              |
| 5600       | Unknown (Unknown) a-californica-stem-swelling                          | a-californica-stem-swelling                         |
| 5723       | Unknown (Unknown) a-californica-stem-swelling/distortion               | a-californica-stem-swelling/distortion              |
| 4832       | Unknown (Unknown) a-crustacea-onion-shaped-bud-gall                    | a-crustacea-onion-shaped-bud-gall                   |
| 5719       | Unknown (Unknown) a-douglasiana-rounded-lump-stem-gall                 | a-douglasiana-rounded-lump-stem-gall                |
| 2189       | Unknown (Unknown) a-douglasii-globular-stem-gall                       | a-douglasii-globular-stem-gall                      |
| 4129       | Unknown (Unknown) a-dracunculus-stem-swelling                          | a-dracunculus-stem-swelling                         |
| 2679       | Unknown (Unknown) a-fasciculatum-bud-rosette                           | a-fasciculatum-bud-rosette                          |
| 6006       | Unknown (Unknown) a-fasciculatum-stem-swelling                         | a-fasciculatum-stem-swelling                        |
| 5383       | Unknown (Unknown) a-germinans-fuzzy-underside-lesion                   | a-germinans-fuzzy-underside-lesion                  |
| 5454       | Unknown (Unknown) a-glaber-swollen-fruit-pocket                        | a-glaber-swollen-fruit-pocket                       |
| 4967       | Unknown (Unknown) a-manzanita-big-berry-gall                           | a-manzanita-big-berry-gall                          |
| 5651       | Unknown (Unknown) a-manzanita-ring-gall                                | a-manzanita-ring-gall                               |
| 4809       | Unknown (Unknown) a-manzanita-stem-borer                               | a-manzanita-stem-borer                              |
| 3057       | Unknown (Unknown) a-negundo-leaf-shot-hole                             | a-negundo-leaf-shot-hole                            |
| 3095       | Unknown (Unknown) a-norvegica-white-fuzz                               | a-norvegica-white-fuzz                              |
| 2617       | Unknown (Unknown) a-pachypoda-leaf-spot                                | a-pachypoda-leaf-spot                               |
| 4742       | Unknown (Unknown) a-palmeri-bud-aggregation                            | a-palmeri-bud-aggregation                           |
| 5674       | Unknown (Unknown) a-psilostachya-big-hair-bud-gall                     | a-psilostachya-big-hair-bud-gall                    |
| 2781       | Unknown (Unknown) a-quinquefolia-swollen-leaf-gall                     | a-quinquefolia-swollen-leaf-gall                    |
| 4767       | Unknown (Unknown) a-racemosa-leaf-blister                              | a-racemosa-leaf-blister                             |
| 4810       | Unknown (Unknown) a-rubrum-woody-globs                                 | a-rubrum-woody-globs                                |
| 3331       | Unknown (Unknown) a-salsola-leafy-bud-gall-midge                       | a-salsola-leafy-bud-gall-midge                      |
| 3080       | Unknown (Unknown) a-syriaca-leaf-blister                               | a-syriaca-leaf-blister                              |
| 3146       | Unknown (Unknown) a-tenuifolia-leaf-blister                            | a-tenuifolia-leaf-blister                           |
| 5502       | Unknown (Unknown) a-trichopodus-greatly-thickened-stem-segment         | a-trichopodus-greatly-thickened-stem-segment        |
| 3056       | Unknown (Unknown) a-trifida-leaf-gall                                  | a-trifida-leaf-gall                                 |
| 3082       | Unknown (Unknown) a-trifida-leaf-spot                                  | a-trifida-leaf-spot                                 |
| 5116       | Unknown (Unknown) a-utahensis-spot-gall                                | a-utahensis-spot-gall                               |
| 3718       | Unknown (Unknown) a-wrightii-stem-swelling                             | a-wrightii-stem-swelling                            |
| 1266       | Unknown (Unknown) ash-leaf-bunching                                    | ash-leaf-bunching                                   |
| 5099       | Unknown (Unknown) b-asteroides-stem-borer                              | b-asteroides-stem-borer                             |
| 4223       | Unknown (Unknown) b-laciniata-leafy-cluster                            | b-laciniata-leafy-cluster                           |
| 2357       | Unknown (Unknown) b-lenta-pocket-gall                                  | b-lenta-pocket-gall                                 |
| 1535       | Unknown (Unknown) b-nigra-stem-swelling                                | b-nigra-stem-swelling                               |
| 2718       | Unknown (Unknown) b-palmeri-witches-broom                              | b-palmeri-witches-broom                             |
| 4711       | Unknown (Unknown) b-parishii-fuzzy-leaf-gall                           | b-parishii-fuzzy-leaf-gall                          |
| 5605       | Unknown (Unknown) b-salicifolia-asteromyia-type-leaf-spot              | b-salicifolia-asteromyia-type-leaf-spot             |
| 3281       | Unknown (Unknown) b-vulgaris-seed-sprouting                            | b-vulgaris-seed-sprouting                           |
| 3273       | Unknown (Unknown) c-acanthocarpa-sumac-fruit-gall                      | c-acanthocarpa-sumac-fruit-gall                     |
| 3322       | Unknown (Unknown) c-album-pink-bean-galls                              | c-album-pink-bean-galls                             |
| 3119       | Unknown (Unknown) c-americana-vein-sac                                 | c-americana-vein-sac                                |
| 2628       | Unknown (Unknown) c-betuloides-witches-broom                           | c-betuloides-witches-broom                          |
| 3283       | Unknown (Unknown) c-blanda-fruit-gall                                  | c-blanda-fruit-gall                                 |
| 4969       | Unknown (Unknown) c-californicus-swollen-stem-moth-gall                | c-californicus-swollen-stem-moth-gall               |
| 3323       | Unknown (Unknown) c-cordulatus-abrupt-stem-swelling-gall               | c-cordulatus-abrupt-stem-swelling-gall              |
| 4715       | Unknown (Unknown) c-filaginifolia-stem-swelling                        | c-filaginifolia-stem-swelling                       |
| 3309       | Unknown (Unknown) c-hookeri-stem-swelling                              | c-hookeri-stem-swelling                             |
| 5732       | Unknown (Unknown) c-incanus-one-sided-stem-swelling                    | c-incanus-one-sided-stem-swelling                   |
| 5632       | Unknown (Unknown) c-linearis-curled-seed-pod                           | c-linearis-curled-seed-pod                          |
| 5836       | Unknown (Unknown) c-linearis-globular-shoot-gall                       | c-linearis-globular-shoot-gall                      |
| 4240       | Unknown (Unknown) c-montanus-leaf-curl                                 | c-montanus-leaf-curl                                |
| 5403       | Unknown (Unknown) c-perfoliata-stem-swelling                           | c-perfoliata-stem-swelling                          |
| 2855       | Unknown (Unknown) c-radicans-leaf-curl                                 | c-radicans-leaf-curl                                |
| 1310       | Unknown (Unknown) c-reticulata-raised-bark-gall                        | c-reticulata-raised-bark-gall                       |
| 5726       | Unknown (Unknown) c-scandens-leaf-wrinkle                              | c-scandens-leaf-wrinkle                             |
| 5758       | Unknown (Unknown) c-spinosus-round-leaf-gall                           | c-spinosus-round-leaf-gall                          |
| 5518       | Unknown (Unknown) c-spp-taphrina-like-thin-yellow-blisters             | c-spp-taphrina-like-thin-yellow-blisters            |
| 5701       | Unknown (Unknown) c-trifoliata-stem-swelling                           | c-trifoliata-stem-swelling                          |
| 3132       | Unknown (Unknown) callicarpa-stem-swelling                             | callicarpa-stem-swelling                            |
| 4199       | Unknown (Unknown) clarkia-stem-gall                                    | clarkia-stem-gall                                   |
| 5535       | Unknown (Unknown) d-breweri-leafy-rosette-gall                         | d-breweri-leafy-rosette-gall                        |
| 5702       | Unknown (Unknown) d-breweri-stem-swelling                              | d-breweri-stem-swelling                             |
| 3170       | Unknown (Unknown) d-cooleyi-gourd-pod-gall                             | d-cooleyi-gourd-pod-gall                            |
| 1755       | Unknown (Unknown) d-glandulosa-stem-swelling                           | d-glandulosa-stem-swelling                          |
| 2996       | Unknown (Unknown) d-lactea-stem-swelling                               | d-lactea-stem-swelling                              |
| 2407       | Unknown (Unknown) deforming-crystallinus                               | deforming-crystallinus                              |
| 3275       | Unknown (Unknown) e-anuus-bunch-gall                                   | e-anuus-bunch-gall                                  |
| 4936       | Unknown (Unknown) e-californica-swollen-flower-bract-gall              | e-californica-swollen-flower-bract-gall             |
| 5489       | Unknown (Unknown) e-canadensis-leaf-base-swelling                      | e-canadensis-leaf-base-swelling                     |
| 5811       | Unknown (Unknown) e-canadensis-tapered-stem-swelling                   | e-canadensis-tapered-stem-swelling                  |
| 5091       | Unknown (Unknown) e-carolinianus-stem-side-gall                        | e-carolinianus-stem-side-gall                       |
| 3032       | Unknown (Unknown) e-ciliatum-stem-swelling                             | e-ciliatum-stem-swelling                            |
| 5984       | Unknown (Unknown) e-fasciculatum-leaf-blister                          | e-fasciculatum-leaf-blister                         |
| 5686       | Unknown (Unknown) e-fasciculatum-swollen-leaf-bundle                   | e-fasciculatum-swollen-leaf-bundle                  |
| 5777       | Unknown (Unknown) e-glaucus-swollen-and-distorted-inflorescence        | e-glaucus-swollen-and-distorted-inflorescence       |
| 3100       | Unknown (Unknown) e-muricata-caryopses-gall                            | e-muricata-caryopses-gall                           |
| 4267       | Unknown (Unknown) e-nauseosa-scaly-stem-gall                           | e-nauseosa-scaly-stem-gall                          |
| 4193       | Unknown (Unknown) e-niveum-leafy-bunch-gall                            | e-niveum-leafy-bunch-gall                           |
| 5717       | Unknown (Unknown) e-nudum-flower-gall                                  | e-nudum-flower-gall                                 |
| 5538       | Unknown (Unknown) e-occidentalis-bud-gall                              | e-occidentalis-bud-gall                             |
| 4143       | Unknown (Unknown) e-paucicapitatus-green-stem-swelling                 | e-paucicapitatus-green-stem-swelling                |
| 4145       | Unknown (Unknown) e-pauciflorum-hairy-purple-rosette                   | e-pauciflorum-hairy-purple-rosette                  |
| 3075       | Unknown (Unknown) e-serpillifolia-leaf-pouch                           | e-serpillifolia-leaf-pouch                          |
| 5575       | Unknown (Unknown) e-teretifolia-fused-cluster-of-short-swollen-leaves  | e-teretifolia-fused-cluster-of-short-swollen-leaves |
| 3247       | Unknown (Unknown) e-texanum-red-leaf-gall                              | e-texanum-red-leaf-gall                             |
| 5895       | Unknown (Unknown) f-californica-midrib-underside-extension             | f-californica-midrib-underside-extension            |
| 3381       | Unknown (Unknown) f-californica-tapered-twig-gall                      | f-californica-tapered-twig-gall                     |
| 3612       | Unknown (Unknown) f-paradoxia-abrupt-swellings                         | f-paradoxia-abrupt-swellings                        |
| 3972       | Unknown (Unknown) f-pubescens-bud-gall                                 | f-pubescens-bud-gall                                |
| 5516       | Unknown (Unknown) f-splendens-witches-broom                            | f-splendens-witches-broom                           |
| 5406       | Unknown (Unknown) g-angustifolium-stem-swelling                        | g-angustifolium-stem-swelling                       |
| 3030       | Unknown (Unknown) g-boreale-hairy-leaf-curl                            | g-boreale-hairy-leaf-curl                           |
| 4802       | Unknown (Unknown) g-californica-witches-broom                          | g-californica-witches-broom                         |
| 5728       | Unknown (Unknown) g-elliptica-white-fuzz-on-twisted-leaf               | g-elliptica-white-fuzz-on-twisted-leaf              |
| 5343       | Unknown (Unknown) g-fremontii-leaf-blister                             | g-fremontii-leaf-blister                            |
| 4297       | Unknown (Unknown) g-jepsonii-trapezoid-gall                            | g-jepsonii-trapezoid-gall                           |
| 5499       | Unknown (Unknown) g-spp-stem-swelling                                  | g-spp-stem-swelling                                 |
| 5599       | Unknown (Unknown) g-stricta-apical-broadleaved-rosette                 | g-stricta-apical-broadleaved-rosette                |
| 5715       | Unknown (Unknown) h-annuus-leaf-fold                                   | h-annuus-leaf-fold                                  |
| 4955       | Unknown (Unknown) h-arbutifolia-witches-broom                          | h-arbutifolia-witches-broom                         |
| 5441       | Unknown (Unknown) h-discolor-flower-gall                               | h-discolor-flower-gall                              |
| 4701       | Unknown (Unknown) h-squarrosa-horned-leaf-gall                         | h-squarrosa-horned-leaf-gall                        |
| 3034       | Unknown (Unknown) halesia-petiole-swelling                             | halesia-petiole-swelling                            |
| 2899       | Unknown (Unknown) i-annua-swollen-bud-gall                             | i-annua-swollen-bud-gall                            |
| 5848       | Unknown (Unknown) i-annua-tapered-stem-swelling                        | i-annua-tapered-stem-swelling                       |
| 3153       | Unknown (Unknown) i-capensis-cockscomb-gall                            | i-capensis-cockscomb-gall                           |
| 3515       | Unknown (Unknown) j-monosperma-deformed-berry                          | j-monosperma-deformed-berry                         |
| 4528       | Unknown (Unknown) k-rothrockii-rosette-gall                            | k-rothrockii-rosette-gall                           |
| 1530       | Unknown (Unknown) knotweed-leaf-peeling-spots                          | knotweed-leaf-peeling-spots                         |
| 5711       | Unknown (Unknown) l-conjugialis-enlarged-flower-bud                    | l-conjugialis-enlarged-flower-bud                   |
| 3025       | Unknown (Unknown) l-hispidula-bud-proliferation                        | l-hispidula-bud-proliferation                       |
| 5694       | Unknown (Unknown) l-involucrata-flower-pair-gall                       | l-involucrata-flower-pair-gall                      |
| 2912       | Unknown (Unknown) l-juncea-bud-deformation                             | l-juncea-bud-deformation                            |
| 2109       | Unknown (Unknown) leafy-manzanita-gall                                 | leafy-manzanita-gall                                |
| 1348       | Unknown (Unknown) m-arboreus-fuzzy-blister-gall                        | m-arboreus-fuzzy-blister-gall                       |
| 4032       | Unknown (Unknown) m-arboreus-stem-swelling                             | m-arboreus-stem-swelling                            |
| 4175       | Unknown (Unknown) m-borealis-teardrop-gall                             | m-borealis-teardrop-gall                            |
| 3264       | Unknown (Unknown) m-dysocarpa-red-swelling                             | m-dysocarpa-red-swelling                            |
| 3065       | Unknown (Unknown) m-dysocarpa-stem-swellings                           | m-dysocarpa-stem-swellings                          |
| 5730       | Unknown (Unknown) m-odoratissima-thickened-branch-node                 | m-odoratissima-thickened-branch-node                |
| 4700       | Unknown (Unknown) n-densiflorus-big-bud-gall                           | n-densiflorus-big-bud-gall                          |
| 2968       | Unknown (Unknown) o-corniculata-leaf-curl                              | o-corniculata-leaf-curl                             |
| 3027       | Unknown (Unknown) o-spectabilis-roe-gall                               | o-spectabilis-roe-gall                              |
| 5417       | Unknown (Unknown) p-cinerascens-tapered-stem-swelling                  | p-cinerascens-tapered-stem-swelling                 |
| 3253       | Unknown (Unknown) p-coronopus-rosette-gall                             | p-coronopus-rosette-gall                            |
| 5981       | Unknown (Unknown) p-crassifolia-hairy-blisters                         | p-crassifolia-hairy-blisters                        |
| 2742       | Unknown (Unknown) p-emoryi-leaf-gall                                   | p-emoryi-leaf-gall                                  |
| 3093       | Unknown (Unknown) p-lewisii-swollen-leaf-gall                          | p-lewisii-swollen-leaf-gall                         |
| 3509       | Unknown (Unknown) p-maritima-petiole-swelling                          | p-maritima-petiole-swelling                         |
| 5524       | Unknown (Unknown) p-newberryi-elongated-stem-swelling                  | p-newberryi-elongated-stem-swelling                 |
| 2714       | Unknown (Unknown) p-obovata-raised-pouch                               | p-obovata-raised-pouch                              |
| 2269       | Unknown (Unknown) p-occidentalis-witches-broom                         | p-occidentalis-witches-broom                        |
| 5553       | Unknown (Unknown) p-opulifolius-leaf-blister                           | p-opulifolius-leaf-blister                          |
| 1528       | Unknown (Unknown) p-opulifolius-stem-swelling                          | p-opulifolius-stem-swelling                         |
| 5990       | Unknown (Unknown) p-spinosum-hairy-green-blob                          | p-spinosum-hairy-green-blob                         |
| 2857       | Unknown (Unknown) p-tridentata-leaf-bead-gall                          | p-tridentata-leaf-bead-gall                         |
| 3287       | Unknown (Unknown) p-virginiana-hairy-pedicel                           | p-virginiana-hairy-pedicel                          |
| 5687       | Unknown (Unknown) q-agrifolia-leaf-edge-roll                           | q-agrifolia-leaf-edge-roll                          |
| 3284       | Unknown (Unknown) q-alba-curling-leaf-spot                             | q-alba-curling-leaf-spot                            |
| 1719       | Unknown (Unknown) q-alba-elongate-pocket-gall                          | q-alba-elongate-pocket-gall                         |
| 2975       | Unknown (Unknown) q-alba-like-quercusfutilis                           | q-alba-like-quercusfutilis                          |
| 4453       | Unknown (Unknown) q-alba-polythalamous-swelling                        | q-alba-polythalamous-swelling                       |
| 3257       | Unknown (Unknown) q-alba-vein-bend                                     | q-alba-vein-bend                                    |
| 3277       | Unknown (Unknown) q-alba-vein-gall                                     | q-alba-vein-gall                                    |
| 5637       | Unknown (Unknown) q-gambelii-indented-blister                          | q-gambelii-indented-blister                         |
| 3261       | Unknown (Unknown) q-hypoleucoides-red-blister                          | q-hypoleucoides-red-blister                         |
| 3259       | Unknown (Unknown) q-imbricaria-midrib-pocket                           | q-imbricaria-midrib-pocket                          |
| 4156       | Unknown (Unknown) q-macrocarpa-pink-spot                               | q-macrocarpa-pink-spot                              |
| 2999       | Unknown (Unknown) q-palustris-leaf-curl                                | q-palustris-leaf-curl                               |
| 4299       | Unknown (Unknown) q-virginiana-bead-gall                               | q-virginiana-bead-gall                              |
| 4310       | Unknown (Unknown) q-virginiana-honeydew-acorn                          | q-virginiana-honeydew-acorn                         |
| 3291       | Unknown (Unknown) q-xwarei-bud-proliferation                           | q-xwarei-bud-proliferation                          |
| 3141       | Unknown (Unknown) r-aromatica-cone-gall                                | r-aromatica-cone-gall                               |
| 3084       | Unknown (Unknown) r-aromatica-pocket-gall                              | r-aromatica-pocket-gall                             |
| 2615       | Unknown (Unknown) r-aromatica-vein-pocket                              | r-aromatica-vein-pocket                             |
| 4708       | Unknown (Unknown) r-aureum-swollen-flowerbud-gall                      | r-aureum-swollen-flowerbud-gall                     |
| 3155       | Unknown (Unknown) r-copallinum-leaf-bunching                           | r-copallinum-leaf-bunching                          |
| 3517       | Unknown (Unknown) r-ilicifolia-leaf-fold                               | r-ilicifolia-leaf-fold                              |
| 5979       | Unknown (Unknown) r-integrifolia-broomlike-mass-of-pink-buds           | r-integrifolia-broomlike-mass-of-pink-buds          |
| 3311       | Unknown (Unknown) r-laciniata-white-rust                               | r-laciniata-white-rust                              |
| 2926       | Unknown (Unknown) r-neomexicana-folded-leaf-edge                       | r-neomexicana-folded-leaf-edge                      |
| 5604       | Unknown (Unknown) r-spp-witches-broom                                  | r-spp-witches-broom                                 |
| 3028       | Unknown (Unknown) r-trilobata-red-leaf-gall                            | r-trilobata-red-leaf-gall                           |
| 4873       | Unknown (Unknown) r-trivialis-stem-gall                                | r-trivialis-stem-gall                               |
| 3113       | Unknown (Unknown) s-alba-puckered-leaf-galls                           | s-alba-puckered-leaf-galls                          |
| 4646       | Unknown (Unknown) s-altissima-hairy-ovoid-gall                         | s-altissima-hairy-ovoid-gall                        |
| 4647       | Unknown (Unknown) s-altissima-petiole-blister                          | s-altissima-petiole-blister                         |
| 4497       | Unknown (Unknown) s-azurea-stem-swelling                               | s-azurea-stem-swelling                              |
| 5774       | Unknown (Unknown) s-buckleyi-narrow-stem-swelling                      | s-buckleyi-narrow-stem-swelling                     |
| 3307       | Unknown (Unknown) s-celastrinum-leaf-gall                              | s-celastrinum-leaf-gall                             |
| 5480       | Unknown (Unknown) s-cerulea-caterpillar-in-floral-ovary                | s-cerulea-caterpillar-in-floral-ovary               |
| 5993       | Unknown (Unknown) s-cerulea-stem-swelling                              | s-cerulea-stem-swelling                             |
| 4036       | Unknown (Unknown) s-crassicaulis-basal-stem-swelling                   | s-crassicaulis-basal-stem-swelling                  |
| 5643       | Unknown (Unknown) s-dorrii-purple-leaf-blister                         | s-dorrii-purple-leaf-blister                        |
| 5794       | Unknown (Unknown) s-fistulosa-midrib-blister                           | s-fistulosa-midrib-blister                          |
| 5501       | Unknown (Unknown) s-hartwegii-contorted-stem-swelling                  | s-hartwegii-contorted-stem-swelling                 |
| 1526       | Unknown (Unknown) s-interior-geometric-bud-deformation                 | s-interior-geometric-bud-deformation                |
| 3706       | Unknown (Unknown) s-interior-midrib-swelling                           | s-interior-midrib-swelling                          |
| 3085       | Unknown (Unknown) s-lasiolepis-pinched-fold                            | s-lasiolepis-pinched-fold                           |
| 3285       | Unknown (Unknown) s-lasiolepis-small-leaf-blisters                     | s-lasiolepis-small-leaf-blisters                    |
| 5788       | Unknown (Unknown) s-macrophylla-leaf-blister-gall                      | s-macrophylla-leaf-blister-gall                     |
| 5787       | Unknown (Unknown) s-macrophylla-terminal-leaf-bunch-gall               | s-macrophylla-terminal-leaf-bunch-gall              |
| 3096       | Unknown (Unknown) s-rotundifolia-crumpled-leaf                         | s-rotundifolia-crumpled-leaf                        |
| 5795       | Unknown (Unknown) s-rugosa-petiolate-leaf-cluster                      | s-rugosa-petiolate-leaf-cluster                     |
| 5765       | Unknown (Unknown) s-rugosa-small-fusiform-stem-swelling                | s-rugosa-small-fusiform-stem-swelling               |
| 5122       | Unknown (Unknown) s-sparsifolia-leaf-bunching                          | s-sparsifolia-leaf-bunching                         |
| 5983       | Unknown (Unknown) s-taxifolia-small-blisters                           | s-taxifolia-small-blisters                          |
| 1533       | Unknown (Unknown) s-tomentosa-stem-swelling                            | s-tomentosa-stem-swelling                           |
| 1617       | Unknown (Unknown) s-uvedalia-stem-swelling                             | s-uvedalia-stem-swelling                            |
| 3717       | Unknown (Unknown) s-verticillata-flower-gall                           | s-verticillata-flower-gall                          |
| 3024       | Unknown (Unknown) salix-sack-gall                                      | salix-sack-gall                                     |
| 4618       | Unknown (Unknown) sisymbrium-broom-swelling                            | sisymbrium-broom-swelling                           |
| 5813       | Unknown (Unknown) solidago-ribbed-flower-gall                          | solidago-ribbed-flower-gall                         |
| 3305       | Unknown (Unknown) t-azurea-stem-swelling                               | t-azurea-stem-swelling                              |
| 4241       | Unknown (Unknown) t-leptophylla-stem-swelling                          | t-leptophylla-stem-swelling                         |
| 5171       | Unknown (Unknown) t-pubescens-leaf-blister                             | t-pubescens-leaf-blister                            |
| 2913       | Unknown (Unknown) t-radicans-flower-witches-broom                      | t-radicans-flower-witches-broom                     |
| 3137       | Unknown (Unknown) trifolium-rugose-leaf-curl                           | trifolium-rugose-leaf-curl                          |
| 3269       | Unknown (Unknown) trifolium-witches-broom                              | trifolium-witches-broom                             |
| 4093       | Unknown (Unknown) u-americana-petiole-gall                             | u-americana-petiole-gall                            |
| 5760       | Unknown (Unknown) v-fasciculata-stem-swelling                          | v-fasciculata-stem-swelling                         |
| 5691       | Unknown (Unknown) v-gigantea-midrib-fold                               | v-gigantea-midrib-fold                              |
| 1500       | Unknown (Unknown) wax-myrtle-stem-swelling                             | wax-myrtle-stem-swelling                            |
| 1515       | Unknown (Unknown) white-oak-bud-proliferation                          | white-oak-bud-proliferation                         |
| 2687       | Vitisiella vitis-tuft-gall                                             | vitis-tuft-gall                                     |
| 2248       | Walshomyia c-decurrens-branch-tip-gall                                 | c-decurrens-branch-tip-gall                         |
| 2247       | Walshomyia c-decurrens-heart-gall                                      | c-decurrens-heart-gall                              |
| 2305       | Walshomyia c-decurrens-pointed-bract-gall                              | c-decurrens-pointed-bract-gall                      |
| 2246       | Walshomyia c-decurrens-spiny-bud-gall                                  | c-decurrens-spiny-bud-gall                          |
| 2764       | Walshomyia c-forbesii-christmas-star-gall                              | c-forbesii-christmas-star-gall                      |
| 2161       | Walshomyia j-occidentalis-artichoke-gall-midge                         | j-occidentalis-artichoke-gall-midge                 |
| 2159       | Walshomyia j-occidentalis-bud-gall-midge                               | j-occidentalis-bud-gall-midge                       |
| 2152       | Walshomyia j-osteosperma-cone-gall                                     | j-osteosperma-cone-gall                             |
| 2151       | Walshomyia j-osteosperma-leafy-bud-gall-midge                          | j-osteosperma-leafy-bud-gall-midge                  |
| 2155       | Walshomyia j-osteosperma-tube-gall-midge                               | j-osteosperma-tube-gall-midge                       |
| 2297       | Xanthoteras q-oblongifolia-crystalline-tube-gall (agamic)              | q-oblongifolia-crystalline-tube-gall                |

---

## 2. Undescribed Flag Changes

### Changed from `true` to `false` (72 species)

These are described species that were incorrectly marked as undescribed. They have real genera (not "Unknown") and non-dashed epithets, meaning they are formally described species.

| Species ID |               Species Name               | Old  |  New  |
|------------|------------------------------------------|------|-------|
| 681        | Aceria annonae                           | true | false |
| 5561       | Aciurina trilitura                       | true | false |
| 4269       | Acraspis pezomachoides (sexgen)          | true | false |
| 1373       | Albugo ipomoeae-panduratae               | true | false |
| 3436       | Amphicerus bicaudatus                    | true | false |
| 774        | Apiosporina morbosa                      | true | false |
| 2351       | Arnoldiola atra                          | true | false |
| 967        | Calamomyia phragmites                    | true | false |
| 5678       | Ceruraphis viburnicola                   | true | false |
| 1999       | Chilophaga tripsaci                      | true | false |
| 5078       | Chionaspis nyssae                        | true | false |
| 3140       | Coleosporium montanum                    | true | false |
| 3139       | Coleosporium solidaginis                 | true | false |
| 1247       | Cronartium quercuum (telial)             | true | false |
| 4270       | Cynips erutor                            | true | false |
| 4271       | Cynips expletor                          | true | false |
| 1969       | Cystiphora taraxaci                      | true | false |
| 1972       | Dasineura alopecuri                      | true | false |
| 624        | Dasineura crataegibedeguar               | true | false |
| 3592       | Disholcaspis fungiformis (sexgen)        | true | false |
| 4499       | Disholcaspis quercusglobulus (sexgen)    | true | false |
| 1810       | Ecdytolopha insiticiana                  | true | false |
| 1354       | Epitrimerus marginemtorquens             | true | false |
| 3248       | Eriophyes cerasicrumena (on-p-americana) | true | false |
| 4493       | Erysiphe platani                         | true | false |
| 3963       | Eurosta comma                            | true | false |
| 773        | Eurosta solidaginis                      | true | false |
| 5047       | Exobasidium decolorans                   | true | false |
| 5109       | Floracarus perrepae                      | true | false |
| 3975       | Gnorimoschema crypticum                  | true | false |
| 1507       | Gymnosporangium clavipes                 | true | false |
| 3477       | Gymnotelium blasdaleanum                 | true | false |
| 5564       | Hemitrioza sonchi                        | true | false |
| 2081       | Japanagromyza lonchocarpi                | true | false |
| 2074       | Jersonithrips galligenus                 | true | false |
| 1384       | Josephiella microcarpae                  | true | false |
| 2078       | Labania minuta                           | true | false |
| 1307       | Leuronota maculata                       | true | false |
| 3157       | Melampsora epitea                        | true | false |
| 4523       | Melanopsichium pennsylvanicum            | true | false |
| 1849       | Mompha stellella                         | true | false |
| 5174       | Neolasioptera angelicae                  | true | false |
| 5178       | Neolasioptera apocyni                    | true | false |
| 3602       | Neolasioptera portulacae                 | true | false |
| 1600       | Norvellina chenopodii                    | true | false |
| 3356       | Ophiodothella vaccinii                   | true | false |
| 1329       | Pachypsylla rugosa                       | true | false |
| 4293       | Phylloplecta tripunctata                 | true | false |
| 1814       | Pileolaria brevipes                      | true | false |
| 1740       | Pineus pinifoliae                        | true | false |
| 2834       | Podosphaera physocarpi                   | true | false |
| 3480       | Prospodium transformans                  | true | false |
| 1803       | Pseudomicrostroma juglandis              | true | false |
| 1610       | Puccinia asperior                        | true | false |
| 3346       | Puccinia mariae-wilsoniae                | true | false |
| 3726       | Puccinia spegazzinii                     | true | false |
| 2257       | Pucciniastrum pyrolae                    | true | false |
| 2350       | Pulvinaria cockerelli                    | true | false |
| 2324       | Ravenelia arizonica                      | true | false |
| 2325       | Ravenelia holwayii                       | true | false |
| 4736       | Rhinusa pilosa                           | true | false |
| 1531       | Rhytisma prini                           | true | false |
| 4287       | Saperda fayi                             | true | false |
| 1383       | Smicronyx sculpticollis                  | true | false |
| 4953       | Sorosphaerula veronicae                  | true | false |
| 5008       | Synchytrium hydrocotyles                 | true | false |
| 1851       | Takamatsuella circinata                  | true | false |
| 3263       | Testicularia cyperi                      | true | false |
| 1820       | Torymus druparum                         | true | false |
| 2076       | Trichochermes magna                      | true | false |
| 3158       | Trioza aylmeriae                         | true | false |
| 4163       | Walshia amorphella                       | true | false |

### Changed from `false` to `true` (1 species)

**Species 2235 (`Synergus deforming-pacificus`) was explicitly corrected to `undescribed = true`.** This is a known undescribed species that was incorrectly marked as described.

| Species ID | Species Name | Old | New |
|------------|--------------|-----|-----|
| 2235 | Synergus deforming-pacificus | false | true |


---

## 3. Datacomplete Flag Changes

**Total: 227 species changed from `datacomplete = true` to `datacomplete = false`.**

These species were marked complete but either:
- Have no sources linked (`species_source` join is empty), or
- Are undescribed (undescribed species cannot be data-complete by definition)

| Species ID |                          Species Name                          | Old  |  New  |
|------------|----------------------------------------------------------------|------|-------|
| 1749       | Acalitus iva-bead-gall                                         | true | false |
| 3971       | Aceria f-pubescens-leaf-curl                                   | true | false |
| 1357       | Ampelomyia v-mustangensis-lower-tube-gall                      | true | false |
| 3355       | Ampelomyia v-tiliifolia-pubescent-conical-gall                 | true | false |
| 2265       | Ampelomyia vitis-large-cone-gall                               | true | false |
| 5620       | Amphibolips mexican-red-small-oak-apple (agamic)               | true | false |
| 2233       | Amphibolips q-hemisphaerica-spindle-flower-gall (sexgen)       | true | false |
| 1224       | Amphibolips q-laurifolia-like-coelebs (sexgen)                 | true | false |
| 4882       | Amphibolips q-marilandica-marbled-oak-apple (sexgen)           | true | false |
| 2285       | Amphibolips q-nigra-brown-plum-gall (agamic)                   | true | false |
| 4382       | Amphibolips q-nigra-speckled-bud-gall (agamic)                 | true | false |
| 4244       | Amphibolips q-phellos-bell-gall (sexgen)                       | true | false |
| 1160       | Amphibolips q-phellos-leaf-spindle (sexgen)                    | true | false |
| 4157       | Amphibolips q-rubra-small-oak-apple (agamic)                   | true | false |
| 1145       | Amphibolips q-velutina-pointed-bud-gall (agamic)               | true | false |
| 2030       | Andricus q-chrysolepis-oak-apple-gall (agamic)                 | true | false |
| 2604       | Andricus q-turbinella-succulent-gall (agamic)                  | true | false |
| 4875       | Antistrophus m-lindleyi-basal-stem-gall                        | true | false |
| 4201       | Antistrophus p-pauciflorus-stem-blister                        | true | false |
| 4865       | Antistrophus s-astericus-cryptic-stem-gall                     | true | false |
| 4864       | Antistrophus s-dentatum-cryptic-stem-gall                      | true | false |
| 4860       | Antistrophus s-gracile-flower-gall                             | true | false |
| 4861       | Antistrophus s-integrifolium-flower-gall                       | true | false |
| 4867       | Antistrophus s-integrifolium-stem-cluster-gall                 | true | false |
| 4868       | Antistrophus s-laciniatum-cryptic-leaf-gall                    | true | false |
| 1438       | Antistrophus s-perfoliatum-stem-swelling                       | true | false |
| 1436       | Antistrophus s-terebinthinaceum-seed-gall                      | true | false |
| 5615       | Antron q-obtusata-wrinkled-sphere                              | true | false |
| 3037       | Asphondylia c-palmata-succulent-gall                           | true | false |
| 3324       | Asphondylia c-velutinus-vein-gall-midge                        | true | false |
| 4673       | Asphondylia d-aurantiacus-seed-pod-gall                        | true | false |
| 4274       | Asphondylia e-californicum-flower-gall                         | true | false |
| 3051       | Asphondylia s-nemoralis-leaf-snap                              | true | false |
| 3244       | Asphondylia s-sempervirens-bud-rosette-gall                    | true | false |
| 3052       | Asphondylia s-tortifolia-bud-rosette-cluster                   | true | false |
| 5124       | Asteromyia b-halimifolia-spot-gall                             | true | false |
| 2606       | Atrusca q-turbinella-rusty-oak-apple (agamic)                  | true | false |
| 4896       | Belonocnema q-brandegeei-midrib-gall                           | true | false |
| 2979       | Blaesodiplosis a-alnifolia-curled-tongue-gall                  | true | false |
| 1120       | Callirhytis q-ilicifolia-pip-gall (agamic)                     | true | false |
| 3295       | Callirhytis q-rubra-red-pip-gall (agamic)                      | true | false |
| 541        | Contarinia a-negundo-bead-gall                                 | true | false |
| 2342       | Contarinia a-rubrum-marginal-leaf-fold                         | true | false |
| 5473       | Contarinia h-virginiana-vein-gall                              | true | false |
| 2205       | Contarinia l-tridentata-clasping-leaf-gall                     | true | false |
| 2339       | Contarinia n-sylvatica-swollen-flower                          | true | false |
| 2901       | Contarinia o-tesota-swollen-leaflet-gall                       | true | false |
| 2608       | Contarinia p-opulifolius-red-bead-gall                         | true | false |
| 3997       | Contarinia p-tremuloides-stem-gall                             | true | false |
| 1366       | Cynips q-kelloggii-acorn-cup-gall-wasp                         | true | false |
| 3149       | Dasineura alnus-fold-gall                                      | true | false |
| 4526       | Dasineura l-involucrata-roll-gall                              | true | false |
| 2261       | Dasineura n-densiflorus-tanoak-fuzzy-gall                      | true | false |
| 3151       | Dasineura p-trichocarpa-big-bud-gall                           | true | false |
| 2612       | Dasineura r-parviflorus-fold-gall                              | true | false |
| 4556       | Dasineura s-mollis-roll-gall                                   | true | false |
| 1748       | Dasineura v-cinerea-hook-gall                                  | true | false |
| 4871       | Diastrophus p-congesta-stem-gall                               | true | false |
| 4884       | Diastrophus r-hispidus-like-radicum                            | true | false |
| 5319       | Diastrophus r-trivialis-root-gall                              | true | false |
| 4275       | Diplolepis r-carolina-like-nebulosa                            | true | false |
| 2011       | Disholandricus q-chrysolepis-potato-stem-gall (agamic)         | true | false |
| 4189       | Disholcaspis q-havardii-urchin-gall (agamic)                   | true | false |
| 4268       | Disholcaspis q-laceyi-bullet-gall (agamic)                     | true | false |
| 4162       | Disholcaspis q-oglethorpensis-bullet-gall (agamic)             | true | false |
| 4308       | Disholcaspis q-oleoides-like-quercusvirens (agamic)            | true | false |
| 4242       | Disholcaspis q-vaseyana-peach-gall (agamic)                    | true | false |
| 4886       | Druon q-muehlenbergii-tuft-gall (agamic)                       | true | false |
| 4217       | Druon q-potosina-like-flocci (agamic)                          | true | false |
| 1437       | Dryocosmus q-imbricaria-glob-free-rolling-cell (sexgen)        | true | false |
| 4266       | Dryocosmus q-imbricaria-sack-gall (sexgen)                     | true | false |
| 2232       | Dryocosmus q-pumila-fuzzy-hemispherical-leaf-gall (sexgen)     | true | false |
| 1945       | Eriophyes arizona-red-oak-erineum                              | true | false |
| 4094       | Eriophyes u-thomasii-frost-gall                                | true | false |
| 4178       | Erythres q-phellos-bud-rosette (agamic)                        | true | false |
| 3683       | Euura s-alaxensis-fuzzy-gall                                   | true | false |
| 3898       | Euura s-amygdaloides-like-proxima                              | true | false |
| 3626       | Euura s-barclayi-smooth-petiole-gall                           | true | false |
| 3679       | Euura s-bebbiana-hairy-gall                                    | true | false |
| 3680       | Euura s-bebbiana-like-pomum                                    | true | false |
| 3664       | Euura s-breweri-pilose-gall                                    | true | false |
| 3673       | Euura s-eastwoodiae-peach-gall                                 | true | false |
| 3714       | Euura s-glauca-like-cosensii                                   | true | false |
| 3681       | Euura s-hookeriana-apple-gall                                  | true | false |
| 3674       | Euura s-lasiandra-apple-gall                                   | true | false |
| 3656       | Euura s-lasiandra-like-proxima                                 | true | false |
| 3625       | Euura s-lasiandra-petiole-gall                                 | true | false |
| 3655       | Euura s-lemmonii-bud-gall                                      | true | false |
| 3672       | Euura s-prolixa-spotted-leaf-gall                              | true | false |
| 3903       | Euura s-scouleriana-bud-gall                                   | true | false |
| 2193       | Euura s-scouleriana-fuzzy-gall                                 | true | false |
| 3663       | Euura s-sitchensis-apple-gall                                  | true | false |
| 3631       | Euura s-sitchensis-potato-gall                                 | true | false |
| 3671       | Euura s-tracyi-apple-gall                                      | true | false |
| 3665       | Euura salix-petiole-gall                                       | true | false |
| 3635       | Euura salix-woolly-gall                                        | true | false |
| 3657       | Euura type-ii-leaf-gall                                        | true | false |
| 3659       | Euura type-iii-leaf-gall                                       | true | false |
| 3660       | Euura type-iv-leaf-gall                                        | true | false |
| 3661       | Euura type-v-leaf-gall                                         | true | false |
| 3662       | Euura type-vi-leaf-gall                                        | true | false |
| 6003       | Exobasidium r-groenlandicum-galls-from-taxon-split             | true | false |
| 1990       | Feron q-garryana-plate-gall                                    | true | false |
| 5665       | Feron q-john-tuckeri-cone-gall (agamic)                        | true | false |
| 4402       | Feron q-lobata-hairy-pebble (sexgen)                           | true | false |
| 5611       | Feron q-obtusata-disc-gall                                     | true | false |
| 2704       | Gnorimoschema b-sarothroides-leaf-gall-moth                    | true | false |
| 3999       | Harmandiola p-tremuloides-bead-gall                            | true | false |
| 4000       | Harmandiola p-tremuloides-bumpy-bead-gall                      | true | false |
| 4033       | Harmandiola p-tremuloides-like-globuli                         | true | false |
| 4030       | Harmandiola p-tremuloides-like-populnea                        | true | false |
| 4028       | Harmandiola p-tremuloides-like-tremulae                        | true | false |
| 4029       | Harmandiola p-tremuloides-lips-gall                            | true | false |
| 4031       | Harmandiola p-tremuloides-pouch-gall                           | true | false |
| 4027       | Harmandiola p-tristis-leaf-spot                                | true | false |
| 2025       | Heteroecus q-chrysolepis-vase-gall (agamic)                    | true | false |
| 2613       | Illinoia r-parviflorus-pouch-gall                              | true | false |
| 3124       | Iteomyia s-barclayi-appressed-tooth-gall-midge                 | true | false |
| 3676       | Iteomyia s-candida-leaf-spot                                   | true | false |
| 3628       | Iteomyia s-lasiolepis-tooth-gall                               | true | false |
| 2267       | Iteomyia s-lasiolepis-tube-gall                                | true | false |
| 3633       | Iteomyia s-scouleriana-small-tube-gall                         | true | false |
| 3708       | Iteomyia salix-chili-pepper-gall                               | true | false |
| 5634       | Josephiella f-microcarpa-stem-cluster                          | true | false |
| 4825       | Kinseyella q-segoviensis-thick-walled-gall (agamic)            | true | false |
| 3724       | Lasioptera t-laxa-lily-stem-gall                               | true | false |
| 4401       | Lopesia m-arborea-tuft-gall                                    | true | false |
| 3104       | Macrodiplosis q-agrifolia-vein-fold                            | true | false |
| 2837       | Macrodiplosis q-marilandica-bubble-gall                        | true | false |
| 1164       | Macrodiplosis q-marilandica-globular-vein-gall                 | true | false |
| 2962       | Macrodiplosis q-marilandica-linear-pocket                      | true | false |
| 1639       | Macrodiplosis q-rubra-early-vein-swelling                      | true | false |
| 3463       | Macrodiplosis q-stellata-like-majalis                          | true | false |
| 5988       | Mayetiola c-canadensis-stem-swelling                           | true | false |
| 4252       | Melikaiella q-buckleyi-late-gall (sexgen)                      | true | false |
| 4689       | Melikaiella q-imbricaria-bent-catkin (sexgen)                  | true | false |
| 1170       | Melikaiella q-phellos-midrib-swelling (sexgen)                 | true | false |
| 4893       | Melikaiella q-rubra-flower-swelling                            | true | false |
| 1492       | Meunieriella on-smilax                                         | true | false |
| 3424       | Mompha c-angustifolium-stem-swelling                           | true | false |
| 4238       | Mompha e-canum-leaf-shell                                      | true | false |
| 3246       | Mompha o-lindheimeri-stem-swelling                             | true | false |
| 3210       | Neolasioptera e-hieraciifolius-stem-swelling                   | true | false |
| 3363       | Neolasioptera g-circaezans-stem-swelling                       | true | false |
| 2680       | Neolasioptera h-grosseserratus-globose-stem-gall               | true | false |
| 3255       | Neolasioptera s-carolinense-leaf-gall                          | true | false |
| 3020       | Neolasioptera s-chamissonis-stem-swelling                      | true | false |
| 1753       | Neolasioptera v-urticifolia-stem-swelling                      | true | false |
| 4263       | Neuroterus q-alba-early-flake-gall                             | true | false |
| 4851       | Neuroterus q-alba-raised-blisters (sexgen)                     | true | false |
| 1071       | Neuroterus q-alba-white-bead-gall (agamic)                     | true | false |
| 4934       | Neuroterus q-fusiformis-mottled-filament-gall (agamic)         | true | false |
| 5410       | Neuroterus q-fusiformis-spring-bud-gall (sexgen)               | true | false |
| 3753       | Neuroterus q-gambelii-like-niger (agamic)                      | true | false |
| 4696       | Neuroterus q-gambelii-new-growth-swelling (sexgen)             | true | false |
| 4811       | Neuroterus q-havardii-bead-gall (agamic)                       | true | false |
| 3484       | Neuroterus q-havardii-blackeye-gall (agamic)                   | true | false |
| 4954       | Neuroterus q-havardii-like-niger (agamic)                      | true | false |
| 4847       | Neuroterus q-john-tuckeri-leaf-blister (sexgen)                | true | false |
| 1061       | Neuroterus q-laceyi-hairy-spangle-gall (agamic)                | true | false |
| 3422       | Neuroterus q-laceyi-midrib-swelling (sexgen)                   | true | false |
| 4160       | Neuroterus q-lyrata-like-papillosus (sexgen)                   | true | false |
| 2973       | Neuroterus q-lyrata-red-spangle (agamic)                       | true | false |
| 2120       | Neuroterus q-macrocarpa-fuzzy-flower-gall (sexgen)             | true | false |
| 4283       | Neuroterus q-macrocarpa-hairy-glob (agamic)                    | true | false |
| 4282       | Neuroterus q-macrocarpa-hairy-saucer (agamic)                  | true | false |
| 4850       | Neuroterus q-muehlenbergii-rough-blister (sexgen)              | true | false |
| 5609       | Neuroterus q-obtusata-like-quercusverrucarum (agamic)          | true | false |
| 5614       | Neuroterus q-obtusata-white-spangle                            | true | false |
| 4295       | Neuroterus q-stellata-hole-punch-gall (sexgen)                 | true | false |
| 5514       | Neuroterus q-undulata-fall-like-oblongifoliae                  | true | false |
| 1110       | Neuroterus q-virginiana-numerous-leaf-galls (agamic)           | true | false |
| 5639       | Neuroterus q-virginiana-winter-blister                         | true | false |
| 4300       | Pachypsylla c-caudata-ring-gall                                | true | false |
| 3102       | Pachypsylla c-laevigata-blister-gall                           | true | false |
| 3996       | Pemphigus p-fremontii-midrib-gall                              | true | false |
| 3630       | Phyllocolpa s-exigua-fold-gall                                 | true | false |
| 3200       | Phylloteras q-alba-red-margin-spangle (agamic)                 | true | false |
| 4278       | Phylloteras q-bicolor-like-poculum (agamic)                    | true | false |
| 1260       | Phylloteras q-muehlenbergii-spangle-gall (agamic)              | true | false |
| 5613       | Phylloteras q-obtusata-plate-gall                              | true | false |
| 2972       | Phylloxera c-ovata-netted-gall                                 | true | false |
| 4187       | Phylloxera c-texana-new-shoot-gall                             | true | false |
| 1721       | Polystepha q-agrifolia-leaf-spot                               | true | false |
| 4183       | Polystepha q-alba-spot-gall                                    | true | false |
| 2611       | Polystepha q-hypoleucoides-red-apple-gall                      | true | false |
| 4205       | Polystepha q-imbricaria-leaf-spot                              | true | false |
| 2993       | Polystepha q-imbricaria-raspberry-gall                         | true | false |
| 2994       | Polystepha q-marilandica-flat-top-gall                         | true | false |
| 3353       | Polystepha q-marilandica-short-leaf-gall                       | true | false |
| 1811       | Polystepha q-nigra-cone-gall                                   | true | false |
| 3298       | Polystepha q-nigra-leaf-spot                                   | true | false |
| 3112       | Polystepha q-nigra-vein-axil-gall                              | true | false |
| 3215       | Polystepha q-phellos-purple-leaf-spot                          | true | false |
| 3266       | Polystepha q-shumardii-vein-angle-gall                         | true | false |
| 3339       | Polystepha q-velutina-small-leaf-spots                         | true | false |
| 2655       | Polystepha q-virginiana-wart-gall                              | true | false |
| 3366       | Putoniella v-angustifolium-leaf-edge-fold                      | true | false |
| 592        | Rabdophaga like-rosaria                                        | true | false |
| 3908       | Rabdophaga s-discolor-stem-gall                                | true | false |
| 3713       | Rabdophaga s-exigua-fuzzy-cone-gall                            | true | false |
| 3614       | Rabdophaga s-lasiolepis-bud-gall                               | true | false |
| 3294       | Rhopalomyia a-dracunculus-globular-rosette                     | true | false |
| 4828       | Rhopalomyia b-glutinosa-like-californica                       | true | false |
| 4249       | Rhopalomyia b-pilularis-leaf-gall                              | true | false |
| 4839       | Rhopalomyia b-sarothroides-bud-gall                            | true | false |
| 4838       | Rhopalomyia b-sarothroides-teardrop-gall                       | true | false |
| 3044       | Rhopalomyia e-leptocephala-ribbed-leaf-gall                    | true | false |
| 3976       | Rhopalomyia h-squarrosa-rosette-gall                           | true | false |
| 2970       | Rhopalomyia s-lateriflorum-spongy-gall                         | true | false |
| 5636       | Schizomyia g-sarothrae-like-s-racemicola                       | true | false |
| 4184       | Stegophylla q-stellata-edge-fold                               | true | false |
| 5475       | Synchytrium p-erecta-red-pustules                              | true | false |
| 2154       | Taxodiomyia t-distichum-starburst-gall                         | true | false |
| 5595       | Unknown (Cecidomyiidae) a-bisulcatus-flower-bud-gall           | true | false |
| 5629       | Unknown (Cecidomyiidae) h-alpinum-flower-bud-gall              | true | false |
| 2961       | Unknown (Cecidomyiidae) i-capensis-stem-swelling               | true | false |
| 6000       | Unknown (Cecidomyiidae) p-linarioides-red-leaf-swelling        | true | false |
| 4103       | Unknown (Eriophyidae) a-grandidentatum-upper-leaf-erineum      | true | false |
| 3586       | Unknown (Eriophyidae) b-alicastrum-leaf-gall                   | true | false |
| 5567       | Unknown (Eriophyidae) c-verticillata-bead-galls                | true | false |
| 5699       | Unknown (Eriophyidae) w-acapulcensis-erineum                   | true | false |
| 3375       | Unknown (Tephritidae) s-drummondii-rosette                     | true | false |
| 5502       | Unknown (Unknown) a-trichopodus-greatly-thickened-stem-segment | true | false |
| 5701       | Unknown (Unknown) c-trifoliata-stem-swelling                   | true | false |
| 5990       | Unknown (Unknown) p-spinosum-hairy-green-blob                  | true | false |
| 2687       | Vitisiella vitis-tuft-gall                                     | true | false |

---

## 4. Alias Type Changes

**Total: 1 alias converted from `former_undescribed` to `scientific`.**

| Alias ID | Alias Name | Species Name | Old Type | New Type |
|----------|------------|--------------|----------|----------|
| 12253 | Dasineura r-carolina-folded-terminal-leaflet | Dasineura r-carolina-folded-terminal-leaflet-dasineura | former_undescribed | scientific |

The migration converts all `former_undescribed` aliases to `scientific` type. Only one such alias existed at the time of migration.

---

## 5. Disambiguated Codes

Species 2747 and 5443 both have the epithet `c-americana-enlarged-bud-gall` (they are different genera inducing the same gall). The migration disambiguated their codes by appending the genus name. Both remain `undescribed=true`.

| Species ID | Species Name | Gallformers Code | Undescribed |
|------------|--------------|------------------|-------------|
| 2747 | Contarinia c-americana-enlarged-bud-gall | `c-americana-enlarged-bud-gall-contarinia` | true |
| 5443 | Dasineura c-americana-enlarged-bud-gall | `c-americana-enlarged-bud-gall-dasineura` | true |

Without disambiguation, these two species would have had identical `gallformers_code` values, violating the unique constraint.
