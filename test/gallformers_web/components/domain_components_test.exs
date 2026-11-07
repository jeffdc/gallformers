defmodule GallformersWeb.DomainComponentsTest do
  @moduledoc """
  The design system's domain components: gall_card, source_entry,
  source_quote (docs/design-system/components.md, "Domain").
  """
  use GallformersWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  import Phoenix.Component, only: [sigil_H: 2]
  import GallformersWeb.DomainComponents

  defp query(html, selector), do: html |> LazyHTML.from_fragment() |> LazyHTML.query(selector)
  defp count(html, selector), do: html |> query(selector) |> Enum.count()
  defp text(html, selector), do: html |> query(selector) |> LazyHTML.text() |> String.trim()
  defp attr(html, selector, name), do: html |> query(selector) |> LazyHTML.attribute(name)

  describe "change_entry" do
    defp change(overrides \\ %{}) do
      Map.merge(
        %{
          key: "change-9",
          who: "Adam Kranz",
          title: "Applied an import",
          at: NaiveDateTime.add(NaiveDateTime.utc_now(), -3, :day),
          source: %{id: 59, title: "Cynipid galls of the eastern United States"},
          galls: [%{id: 821, name: "Callirhytis quercuscornigera"}],
          facts: [
            %{
              id: 123,
              change: :added,
              what: "host: Quercus alba",
              gall: %{id: 821, name: "Callirhytis quercuscornigera"},
              taxon: nil
            },
            %{
              id: 124,
              change: :withdrawn,
              what: "common name \"Horned oak gall\"",
              gall: nil,
              taxon: %{id: 40, name: "Quercus alba", rank: "species", kingdom: "Plantae"}
            }
          ],
          counts: %{added: 1, withdrawn: 1},
          names: [%{id: 77, name: "Andricus", rank: "genus", kingdom: "Animalia"}],
          taxa: []
        },
        overrides
      )
    end

    defp entry(group) do
      assigns = %{group: group}
      rendered_to_string(~H|<ul><.change_entry group={@group} /></ul>|)
    end

    test "who did what, from which Source, when" do
      html = entry(change())

      assert count(html, "li#change-9") == 1
      assert text(html, "[data-part=summary]") =~ "Adam Kranz"
      assert text(html, "[data-part=summary]") =~ "applied an import"
      assert attr(html, "[data-part=summary] a", "href") == ["/admin/review/sources/59"]
      assert text(html, "[data-part=when]") == "3 days ago"
    end

    test "each Gall, each new name and each Fact links to View and Edit" do
      html = entry(change())

      assert attr(html, "[data-part=galls] a", "href") == ["/gall/821", "/gall/821?edit"]

      assert attr(html, "[data-part=names] a", "href") == [
               "/genus/Andricus",
               "/genus/Andricus?edit"
             ]

      assert attr(html, "[data-part=facts] li:first-child a", "href") ==
               ["/gall/821#fact-123", "/gall/821?edit#fact-123"]

      assert attr(html, "[data-part=facts] li:last-child a", "href") ==
               ["/host/40#fact-124", "/host/40?edit#fact-124"]
    end

    test "an inducer species links to its species page, and to it in Edit mode" do
      html =
        entry(
          change(%{
            galls: [],
            facts: [],
            counts: %{},
            names: [%{id: 5, name: "Andricus kingi", rank: "species", kingdom: "Animalia"}]
          })
        )

      assert attr(html, "[data-part=names] a", "href") == ["/species/5", "/species/5?edit"]
    end

    test "a taxon with no page of its own is found by search; Edit goes to its taxonomy record" do
      html =
        entry(
          change(%{
            galls: [],
            facts: [],
            counts: %{},
            names: [%{id: 6, name: "Hymenoptera", rank: "order", kingdom: "Animalia"}]
          })
        )

      assert attr(html, "[data-part=names] a", "href") ==
               ["/globalsearch?q=Hymenoptera", "/admin/taxonomy/6"]
    end

    test "the taxa an edit touched, each with View and Edit" do
      html =
        entry(
          change(%{taxa: [%{id: 40, name: "Quercus alba", rank: "species", kingdom: "Plantae"}]})
        )

      assert text(html, "[data-part=taxa]") =~ "Quercus alba"
      assert text(html, "[data-part=taxa] [data-part=rank]") == "species"
      assert attr(html, "[data-part=taxa] a", "href") == ["/host/40", "/host/40?edit"]
    end

    test "what happened to the Facts, counted" do
      html = entry(change())

      assert text(html, "[data-part=counts]") =~ "1 Fact added"
      assert text(html, "[data-part=counts]") =~ "1 withdrawn"
      assert text(html, "[data-part=facts] summary") == "Show the 2 Facts"
    end
  end

  describe "article_card" do
    test "a card: the band with its icon, the title, preview and meta naming the topic, one link" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.article_card
          href="/articles/idguide"
          title="Gall Identification Guide"
          topic="identification"
          icon="ph-compass"
          tone={:sky}
          meta="Adam Kranz · January 26, 2026"
        >
          A gall is a novel organ grown by a plant.
        </.article_card>
        """)

      assert attr(html, "a[data-layout=card]", "href") == ["/articles/idguide"]
      assert attr(html, "[data-part=band]", "data-tone") == ["sky"]
      assert text(html, "[data-part=band]") == ""
      assert count(html, "[data-part=band] .ph-compass") == 1
      assert text(html, "h2") == "Gall Identification Guide"
      assert text(html, "[data-part=preview]") == "A gall is a novel organ grown by a plant."
      assert text(html, "[data-part=meta]") == "identification · Adam Kranz · January 26, 2026"
      assert count(html, "a[title='Edit in admin']") == 0
    end

    test "featured: the wide layout, its topic in the meta line; an edit link when given" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.article_card
          href="/articles/lookalikes"
          title="Gall Lookalikes"
          topic="identification"
          featured
          edit_href="/admin/articles/9"
        >
          Organisms that look like galls but are not.
        </.article_card>
        """)

      assert count(html, "a[data-layout=featured]") == 1
      assert text(html, "[data-part=meta]") == "identification"
      assert text(html, "[data-part=band]") == ""
      assert attr(html, "[data-part=band]", "data-tone") == ["plain"]
      assert attr(html, "a[title='Edit in admin']", "href") == ["/admin/articles/9"]
    end
  end

  describe "photo_viewer" do
    defp photos do
      [
        %{
          src: "/a.jpg",
          thumb: "/a-small.jpg",
          alt: "",
          caption: "Leaf galls",
          creator: "Ann",
          license: "CC-BY",
          licenselink: "https://creativecommons.org/licenses/by/4.0/",
          sourcelink: "",
          uploader: "jeff",
          lastchangedby: "jeff",
          attribution: ""
        },
        %{
          "src" => "/b.jpg",
          "thumb" => "/b-small.jpg",
          "caption" => "",
          "creator" => "Bob",
          "license" => "All Rights Reserved",
          "licenselink" => "",
          "sourcelink" => "https://inaturalist.org/photos/1"
        }
      ]
    end

    test "one figure per photo, the first shown, each with its own credit" do
      assigns = %{photos: photos()}

      html =
        rendered_to_string(~H"""
        <.photo_viewer id="gall-images" photos={@photos} name="Andricus fixturi" />
        """)

      assert attr(html, "#gall-images", "phx-hook") == ["PhotoViewer"]
      assert count(html, "[data-slide]") == 2
      assert count(html, "[data-slide='0'][hidden]") == 0
      assert count(html, "[data-slide='1'][hidden]") == 1
      # The first photo has no source link; the second has one (each its own).
      assert count(html, "[data-slide='0'] a[href^='https://inaturalist']") == 0
      assert count(html, "[data-slide='1'] a[href='https://inaturalist.org/photos/1']") == 1
      assert text(html, "[data-slide='0'] [data-part=caption]") == "Leaf galls"
      assert count(html, "[data-slide='1'] [data-part=caption]") == 0

      assert count(
               html,
               "[data-slide='0'] a[href='https://creativecommons.org/licenses/by/4.0/']"
             ) == 1

      assert text(html, "[data-slide='1'] [data-part=credit]") =~ "Bob"
      assert text(html, "[data-slide='1'] [data-part=credit]") =~ "All Rights Reserved"
      # Alt text from the name when not given
      assert attr(html, "[data-slide='1'] img", "alt") == ["Photo 2 of Andricus fixturi"]
      assert attr(html, "[data-slide='0'] img", "loading") == ["lazy"]
    end

    test "two or more photos get a thumbnail strip and arrows; one gets neither" do
      assigns = %{photos: photos()}

      two =
        rendered_to_string(~H"""
        <.photo_viewer id="v" photos={@photos} name="X" />
        """)

      assert count(two, "[data-thumbs] button[data-go]") == 2
      assert attr(two, "[data-thumbs] button[data-go='0']", "aria-current") == ["true"]
      assert attr(two, "[data-thumbs] img", "src") == ["/a-small.jpg", "/b-small.jpg"]
      # On the page and in the full-size view
      assert count(two, "button[data-prev]") == 2
      assert count(two, "button[data-next]") == 2

      assigns = %{photos: Enum.take(photos(), 1)}

      one =
        rendered_to_string(~H"""
        <.photo_viewer id="v" photos={@photos} name="X" />
        """)

      assert count(one, "[data-thumbs]") == 0
      assert count(one, "button[data-prev]") == 0
    end

    test "the full-size view and the details are dialogs, per photo" do
      assigns = %{photos: photos()}

      html =
        rendered_to_string(~H"""
        <.photo_viewer id="v" photos={@photos} name="X" />
        """)

      assert count(html, "dialog[data-lightbox] [data-full='1'] img[data-src='/b.jpg']") == 1
      assert count(html, "dialog[data-details] [data-info='0']") == 1
      assert text(html, "dialog[data-details] [data-info='0']") =~ "jeff"
    end

    test "an admin gets the edit link; with no photos, the empty state and Add images" do
      assigns = %{}

      admin =
        rendered_to_string(~H"""
        <.photo_viewer id="v" photos={[]} name="X" edit_href="/admin/galls/1#images" admin />
        """)

      assert text(admin, "[data-part=empty]") =~ "No photos yet"
      assert attr(admin, "a[href='/admin/galls/1#images']", "href") == ["/admin/galls/1#images"]

      visitor =
        rendered_to_string(~H"""
        <.photo_viewer id="v" photos={[]} name="X" edit_href="/admin/galls/1#images" />
        """)

      assert count(visitor, "a[href='/admin/galls/1#images']") == 0
    end
  end

  describe "family_card" do
    defp card do
      %{
        key: "f-1",
        name: "Cynipidae",
        url: "/family/Cynipidae",
        description: "Gall wasps",
        count: 3,
        image_url: "/c.jpg",
        genera: [
          %{
            key: "g-11",
            name: "Andricus",
            url: "/genus/Andricus",
            count: 2,
            leaves: [
              %{key: "s-101", id: 101, label: "Andricus seedii (agamic)", url: "/gall/101"},
              %{key: "s-102", id: 102, label: "Andricus kingi", url: "/gall/102"}
            ]
          },
          %{
            key: "g-10",
            name: "Cynips",
            url: "/genus/Cynips",
            count: 1,
            leaves: [%{key: "s-100", id: 100, label: "Cynips quercusfolii", url: "/gall/100"}]
          }
        ]
      }
    end

    test "collapsed: the family, its count and largest genera, and a toggle" do
      assigns = %{card: card()}

      html =
        rendered_to_string(~H"""
        <.family_card card={@card} on_toggle="toggle_node" limit={1} />
        """)

      assert attr(html, "article", "data-expanded") == ["false"]
      assert text(html, "[data-part=name] a") == "Cynipidae"
      assert text(html, "[data-part=description]") == "Gall wasps"
      assert text(html, "[data-part=count]") == "3 galls · 2 genera"
      assert attr(html, "[data-part=genera] a", "href") == ["/genus/Andricus"]
      assert attr(html, "button[phx-value-key=f-1]", "phx-click") == ["toggle_node"]
      assert attr(html, "button[phx-value-key=f-1]", "aria-expanded") == ["false"]
      assert count(html, ~s(a[href="/gall/101"])) == 0
    end

    test "expanded: every genus with its own toggle, and the Galls of the expanded ones" do
      assigns = %{card: card(), expanded: MapSet.new(["f-1", "g-11"])}

      html =
        rendered_to_string(~H"""
        <.family_card card={@card} on_toggle="toggle_node" expanded={@expanded} />
        """)

      assert attr(html, "article", "data-expanded") == ["true"]
      assert attr(html, "button[phx-value-key=f-1]", "aria-expanded") == ["true"]
      assert attr(html, "button[phx-value-key=g-11]", "aria-expanded") == ["true"]
      assert attr(html, "button[phx-value-key=g-10]", "aria-expanded") == ["false"]
      assert count(html, ~s(a[href="/gall/101"])) == 1
      assert count(html, ~s(a[href="/gall/100"])) == 0
    end

    test "one gall, one genus, and no photo shows the icon well" do
      assigns = %{card: %{card() | count: 1, image_url: nil, genera: tl(card().genera)}}

      html =
        rendered_to_string(~H"""
        <.family_card card={@card} on_toggle="toggle_node" />
        """)

      assert text(html, "[data-part=count]") == "1 gall · 1 genus"
      assert count(html, "[data-part=placeholder]") == 1
    end
  end

  describe "gall_name" do
    test "a described Gall's name is a scientific name" do
      assigns = %{}
      html = rendered_to_string(~H|<.gall_name name="Andricus weldi (agamic)" />|)

      assert text(html, "em") == "Andricus weldi"
      assert html =~ "(agamic)"
    end

    test "an undescribed Gall is named by what it is, its placeholder name in the title" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.gall_name name="Unknown (Cynipidae) q-stellata-red-bud-gall" undescribed />
        """)

      assert text(html, "[data-part=gall-name]") == "Undescribed red bud gall"

      assert attr(html, "[data-part=gall-name]", "title") == [
               "Unknown (Cynipidae) q-stellata-red-bud-gall"
             ]
    end

    test "an undescribed Gall's genus is italic, its qualifiers upright; article adds An" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.gall_name name="Neuroterus q-gambelii-new-growth-swelling (sexgen)" undescribed article />
        """)

      assert text(html, "[data-part=gall-name]") ==
               "An undescribed Neuroterus new growth swelling (sexgen)"

      assert text(html, "em") == "Neuroterus"
    end
  end

  describe "cynipid_mark" do
    test "decoration, colored and sized from outside" do
      assigns = %{}
      html = rendered_to_string(~H|<.cynipid_mark class="h-28 w-44 text-brand" />|)

      assert attr(html, "[data-part=cynipid-mark]", "aria-hidden") == ["true"]

      assert attr(html, "[data-part=cynipid-mark]", "class") == [
               "gf-cynipid-mark h-28 w-44 text-brand"
             ]
    end
  end

  describe "gall_summary" do
    test "where it's found, on which Hosts and when, the Hosts as scientific names" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.gall_summary
          hosts={["Quercus alba", "Quercus rubra", "Quercus velutina", "Quercus coccinea"]}
          plant_part={["stem"]}
          season={["Fall", "Spring"]}
        />
        """)

      assert text(html, "[data-part=gall-summary]") ==
               "Found on the stem of Quercus alba and Quercus rubra and 2 more, in spring and fall."

      assert count(html, "em") == 2
    end

    test "a plant part that is already a phrase is used as one" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.gall_summary hosts={["Malus fusca"]} plant_part={["between leaf veins"]} />
        """)

      assert text(html, "[data-part=gall-summary]") == "Found between leaf veins of Malus fusca."
    end

    test "several plant parts follow the Hosts" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.gall_summary hosts={["Tilia americana"]} plant_part={["lower leaf", "upper leaf"]} />
        """)

      assert text(html, "[data-part=gall-summary]") ==
               "Found on Tilia americana (lower leaf, upper leaf)."
    end

    test "nothing known, nothing said" do
      assigns = %{}
      html = rendered_to_string(~H|<.gall_summary />|)

      assert count(html, "[data-part=gall-summary]") == 0
    end

    test "an undescribed Gall says which Gallformers make it" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.gall_summary
          name="Unknown (Cecidomyiidae) s-alba-stem-gall"
          undescribed
          hosts={["Salix alba"]}
          plant_part={["stem"]}
        />
        """)

      assert text(html, "[data-part=gall-summary]") ==
               "Made by one of the gall midges, on the stem of Salix alba."
    end
  end

  describe "category_tile" do
    test "a row: one link with a decorative photo, the name and the count" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.category_tile navigate="/id?g=Quercus" name="Quercus" count={1349} image_url="/q.jpg" italic />
        """)

      assert count(html, "a") == 1
      assert attr(html, "a", "href") == ["/id?g=Quercus"]
      assert attr(html, "a", "data-layout") == ["row"]
      assert attr(html, "a img", "alt") == [""]
      assert text(html, "[data-part=name]") == "Quercus"
      assert count(html, "[data-part=name] em") == 1
      assert text(html, "[data-part=count]") == "1,349"
    end

    test "a plain name stays upright, and no photo shows the icon well" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.category_tile navigate="/galls" name="Gall wasps" count={8} />
        """)

      assert count(html, "[data-part=name] em") == 0
      assert count(html, "img") == 0
      assert count(html, "[data-part=placeholder]") == 1
    end

    test "a tile: the photo above the name and count" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.category_tile
          navigate="/galls"
          name="Gall midges"
          count={812}
          image_url="/m.jpg"
          layout={:tile}
        />
        """)

      assert attr(html, "a", "data-layout") == ["tile"]
      assert count(html, "a img") == 1
      assert text(html, "[data-part=count]") == "812"
    end
  end

  describe "gall_card" do
    test "the whole card is one link to the Gall, with the photo, name and traits inside" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.gall_card
          navigate="/gall/582"
          name="Callirhytis quercuscornigera (agamic)"
          image_url="https://example.org/582.jpg"
          subtitle="stem · abrupt swelling · spring"
        />
        """)

      assert count(html, "a") == 1
      assert attr(html, "a", "href") == ["/gall/582"]
      assert count(html, "a img") == 1
      assert attr(html, "img", "src") == ["https://example.org/582.jpg"]
      assert attr(html, "img", "loading") == ["lazy"]
      assert text(html, "a [data-part=name]") == "Callirhytis quercuscornigera (agamic)"
      # A scientific name is italic
      assert count(html, "[data-part=name] em") == 1
      assert text(html, "a [data-part=subtitle]") == "stem · abrupt swelling · spring"
    end

    test "the photo's alt text comes from the name unless given" do
      assigns = %{}

      derived =
        rendered_to_string(~H"""
        <.gall_card navigate="/gall/1" name="Andricus quercuslanigera" image_url="/a.jpg" />
        """)

      assert attr(derived, "img", "alt") == ["Photo of Andricus quercuslanigera"]

      given =
        rendered_to_string(~H"""
        <.gall_card navigate="/gall/1" name="Andricus quercuslanigera" image_url="/a.jpg" image_alt="" />
        """)

      assert attr(given, "img", "alt") == [""]
    end

    test "with no photo it shows a gall icon on a placeholder, not an empty box or image" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.gall_card navigate="/gall/9" name="Unknown (Cynipidae) q-rubra-spur-gall" image_url={nil} />
        """)

      assert count(html, "img") == 0
      assert count(html, "a [data-part=placeholder] .gf-gall") == 1
      assert count(html, "[data-part=subtitle]") == 0
    end

    test "chips sit inside the card's one link" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.gall_card navigate="/gall/9" name="Unknown (Cynipidae) q-rubra-spur-gall">
          <:chip variant={:info}>Undescribed</:chip>
        </.gall_card>
        """)

      assert count(html, "a") == 1
      assert text(html, "a [data-part=chips] .gf-chip-info") == "Undescribed"
    end

    test "marks its size" do
      assigns = %{}
      html = rendered_to_string(~H|<.gall_card navigate="/gall/1" name="Andricus" size={:sm} />|)
      assert count(html, "[data-size=sm]") == 1
    end
  end

  describe "source_entry" do
    test "a blank or missing year reads n.d." do
      for year <- [nil, "", "  "] do
        html =
          render_component(&GallformersWeb.DomainComponents.source_entry/1,
            id: "s1",
            title: "Gallformers legacy data",
            year: year
          )

        assert html
               |> LazyHTML.from_fragment()
               |> LazyHTML.query("[data-part=year] abbr")
               |> LazyHTML.text() == "n.d."
      end
    end

    setup do
      %{
        source: %{
          id: "source-12",
          year: 1959,
          title: "The cynipid galls of Oklahoma",
          href: "/source/12",
          authors: "Kinsey, A.C.",
          excerpt: "Gall on the stem, abrupt.\nUp to 18 mm.\n\nSecond paragraph.",
          license: "Public Domain",
          original_url: "https://archive.org/details/cynipids"
        }
      }
    end

    test "collapsed: year, title link, authors, the excerpt's first line, and a labelled toggle",
         %{source: s} do
      assigns = %{s: s}

      html =
        rendered_to_string(~H"""
        <.source_entry {@s} />
        """)

      assert text(html, "#source-12 [data-part=year]") == "1959"
      assert attr(html, "#source-12 a[data-part=title]", "href") == ["/source/12"]
      assert text(html, "a[data-part=title]") == "The cynipid galls of Oklahoma"
      assert text(html, "[data-part=authors]") =~ "Kinsey, A.C."
      assert text(html, "#source-12-short") == "Gall on the stem, abrupt. Up to 18 mm."

      [toggle] = html |> query("button[aria-controls=source-12-full]") |> Enum.to_list()
      assert LazyHTML.attribute(toggle, "aria-expanded") == ["false"]

      assert LazyHTML.attribute(toggle, "aria-label") ==
               ["Show the excerpt from The cynipid galls of Oklahoma"]

      # The toggle works in the browser, without a round trip to the server
      [click] = LazyHTML.attribute(toggle, "phx-click")
      refute click =~ "push"
      assert click =~ "source-12-full"

      # The whole excerpt is there, hidden until opened
      assert count(html, "#source-12-full.hidden blockquote p") == 2
    end

    test "expanded: the whole excerpt, the license and links to the Source page and the original",
         %{source: s} do
      assigns = %{s: s}

      html =
        rendered_to_string(~H"""
        <.source_entry {@s} open />
        """)

      assert attr(html, "button[aria-controls=source-12-full]", "aria-expanded") == ["true"]
      assert count(html, "#source-12-full.hidden") == 0
      assert count(html, "#source-12-short.hidden") == 1

      assert text(html, "#source-12-full blockquote") =~ "Second paragraph."
      assert text(html, "#source-12-full [data-part=meta]") =~ "Public Domain"
      assert attr(html, "#source-12-full a[href='/source/12']", "href") == ["/source/12"]
      assert text(html, "#source-12-full a[href='/source/12']") == "Source page"

      [original] =
        html |> query("a[href='https://archive.org/details/cynipids']") |> Enum.to_list()

      assert LazyHTML.text(original) =~ "Original ↗"
      assert LazyHTML.attribute(original, "target") == ["_blank"]
      assert LazyHTML.attribute(original, "rel") == ["noopener"]
    end

    test "without an original, there is no external link", %{source: s} do
      assigns = %{s: %{s | original_url: nil}}
      html = rendered_to_string(~H|<.source_entry {@s} open />|)
      assert count(html, "a[target=_blank]") == 0
    end

    test "pinned: Gallformers' ID Notes as an info panel, always open, with no toggle" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.source_entry
          id="source-1"
          pinned
          title="Gallformers ID Notes"
          href="/source/1"
          excerpt="Compare with the gall of Andricus."
        />
        """)

      assert count(html, "#source-1[data-variant=info]") == 1
      assert count(html, "button") == 0
      assert count(html, ".hidden") == 0
      assert text(html, "#source-1 blockquote") == "Compare with the gall of Andricus."
      assert text(html, "#source-1 a[href='/source/1']") =~ "Source page"
    end
  end

  describe "source_quote" do
    test "a block quote of several paragraphs, with its page and cite" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.source_quote page="p. 113" cite="https://archive.org/details/cynipids">
          <p>Gall on the stem.</p>
          <p>Up to 18 mm.</p>
        </.source_quote>
        """)

      assert attr(html, "blockquote", "cite") == ["https://archive.org/details/cynipids"]
      assert count(html, "blockquote.font-serif p:not([data-part=page])") == 2
      assert text(html, "[data-part=page]") == "p. 113"
    end

    test "inline, it is a q, not a block" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.source_quote inline page="p. 2">abrupt swelling</.source_quote>
        """)

      assert count(html, "blockquote") == 0
      assert text(html, "q.font-serif") == "abrupt swelling"
      assert text(html, "[data-part=page]") == "p. 2"
    end
  end
end
