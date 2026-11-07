defmodule GallformersWeb.Dev.DesignSystemLive do
  @moduledoc """
  The design system's living reference (docs/design-system/README.md):
  every token and every built component, rendered with the real code in
  light and dark, at both densities. Dev only (`/dev/design-system`).

  When a component is built, it gets an example here.
  """
  use GallformersWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       page_title: "Design system",
       family_open: MapSet.new(),
       sample_family: sample_family(),
       sample_family_small: %{
         sample_family()
         | key: "f-2",
           name: "Diplolepididae",
           description: nil,
           count: 36,
           genera: [%{hd(sample_family().genera) | name: "Diplolepis", count: 36}]
       },
       wave_two:
         ~w(data_table fact_list name_list stat empty_state gall_card photo_viewer category_tile family_card source_entry source_quote field search_field facet_group filter_select notice dialog prose key_couplet article_card chip_nav link_tile bar_chart share_list edit_toggle fact_row fact_chip review_apply change_tray change_entry key_path dangerous_delete_modal gf-file file_drop radio_card review_option taxonomic_position segmented_switch data_table-selection progress_bar loading_spinner chrome),
       sample_view: "photos",
       sample_choice: "0",
       sample_selected: MapSet.new([2]),
       sample_sources: [
         %{
           title: "Cynipid galls of the eastern United States",
           authors: "LH Weld",
           year: 1959,
           status: "Complete",
           kind: nil
         },
         %{
           title: "Plant Galls and Gall Makers",
           authors: "EP Felt",
           year: 1940,
           status: nil,
           kind: nil
         },
         %{
           title: "A Catalog of the Cecidomyiidae (Diptera) of the World 6th Edition - 2025",
           authors: "Raymond J. Gagné and Matthias Jaschhof",
           year: 2025,
           status: "Complete",
           kind: nil
         }
       ],
       sample_hosts:
         Enum.map(
           ~w(buckleyi falcata hemisphaerica ilicifolia imbricaria incana laevis laurifolia myrtifolia nigra palustris phellos rubra velutina),
           &"Quercus #{&1}"
         ),
       sample_excerpt:
         "Quercus catesbaei [laevis], falcata, ilicifolia, imbricaria, palustris, rubra, texana [buckleyi]. Stem galls, woody stem swellings.\n\nHorned Knot Gall. Abrupt, cuts like cheese when growing in May–June, becoming woody, the horns finally protruding and even dropping out.",
       sample_facet: [
         %{value: "lower leaf", label: "lower leaf", count: 33, selected: true},
         %{value: "stem", label: "stem", count: 23, selected: false},
         %{value: "upper leaf", label: "upper leaf", count: 23, selected: false},
         %{value: "leaf midrib", label: "leaf midrib", count: 22, selected: false},
         %{value: "bud", label: "bud", count: 9, selected: false},
         %{value: "root", label: "root", count: 0, selected: false}
       ]
     )}
  end

  @colors [
    {"Brand",
     [
       {"bg-brand-fill", "brand-fill", "The one primary action's fill"},
       {"bg-brand", "brand", "Wordmark, active navigation (as text: text-brand)"},
       {"bg-sky", "sky", "Site header band, selected rows"},
       {"bg-sky-soft", "sky-soft", "Info surfaces, row hover"},
       {"bg-autumn", "autumn", "Needs you: marks and fills"},
       {"bg-autumn-ink", "autumn-ink", "Needs you as text (counts)"}
     ]},
    {"Text",
     [
       {"bg-ink", "ink", "Primary text, titles"},
       {"bg-ink-2", "ink-2", "Secondary text"},
       {"bg-muted", "muted", "Labels, captions, placeholders"},
       {"bg-link", "link", "Links"}
     ]},
    {"Surfaces and rules",
     [
       {"bg-paper", "paper", "Page ground"},
       {"bg-surface", "surface", "Panels, inputs, tables"},
       {"bg-surface-2", "surface-2", "Wells, table heads, sidebar"},
       {"bg-line", "line", "Hairlines (as border: border-line)"},
       {"bg-line-strong", "line-strong", "Control borders, section rules"}
     ]},
    {"State",
     [
       {"bg-ok", "ok", "Complete, approved, saved (with bg-ok-bg)"},
       {"bg-warn", "warn", "In progress, holds approval (with bg-warn-bg)"},
       {"bg-danger", "danger", "Errors, destructive (with bg-danger-bg)"},
       {"bg-info", "info", "Neutral notices (with bg-info-bg)"}
     ]}
  ]

  @type_scale [
    {"text-page", "Page title (h1)", "Callirhytis quercuscornigera"},
    {"text-section", "Section heading (h2)", "Possible range"},
    {"text-subsection", "Heading in a section (h3)", "Further reading"},
    {"text-lead", "Intro paragraph", "Galls on oaks, by the plant part they grow on."},
    {"text-body", "Running text",
     "Woody knots on the limbs, emitting pale yellow, conical, brittle projections."},
    {"text-ui", "Tables, lists, controls", "Quercus imbricaria Michx. · 14 Galls"},
    {"text-meta", "Secondary lines, counts", "Created Oct 28, 2026 · 6 of 11 traits recorded"},
    {"text-caption", "Labels, captions, credits", "POSSIBLE RANGE"}
  ]

  @impl true
  def render(assigns) do
    assigns = assign(assigns, colors: @colors, type_scale: @type_scale)

    ~H"""
    <Layouts.app flash={@flash}>
      <div class="flex flex-col gap-section">
        <.page_header>
          <:crumb href="/">Gallformers</:crumb>
          <:title>Design system</:title>
          <:description>
            Every token and every built component, rendered with the real code in light and dark.
            The rules are in docs/design-system/; this page shows them.
          </:description>
        </.page_header>

        <nav aria-label="On this page" class="flex flex-wrap gap-x-4 gap-y-1 text-meta">
          <a href="#color">Color</a>
          <a href="#type">Type</a>
          <a href="#density">Density</a>
          <a href="#shape">Radius and elevation</a>
          <a href="#button">button</a>
          <a href="#chip">chip</a>
          <a href="#menu">menu</a>
          <a href="#page-header">page_header</a>
          <a href="#section">section</a>
          <a href="#panel">panel</a>
          <a href="#rail">rail</a>
          <a href="#tab_nav">tab_nav</a>
          <a :for={id <- @wave_two} href={"#" <> id}>{id}</a>
        </nav>

        <.section id="color" title="Color">
          <:aside>assets/css/system/tokens.css · foundations.md</:aside>
          <div class="flex flex-col gap-block">
            <div :for={{group, swatches} <- @colors} class="flex flex-col gap-2">
              <h3 class="text-subsection">{group}</h3>
              <.both :let={_theme}>
                <div class="grid grid-cols-2 gap-2 sm:grid-cols-3">
                  <div :for={{class, name, role} <- swatches} class="flex items-center gap-2">
                    <span class={["size-8 shrink-0 rounded-ctl border border-line", class]}></span>
                    <span class="min-w-0">
                      <span class="block text-meta font-semibold text-ink">{name}</span>
                      <span class="block truncate text-caption text-muted" title={role}>{role}</span>
                    </span>
                  </div>
                </div>
              </.both>
            </div>
          </div>
        </.section>

        <.section id="type" title="Type">
          <:aside>League Spartan · Source Sans 3 · Source Serif 4</:aside>
          <div class="grid gap-block lg:grid-cols-2">
            <div
              :for={
                {label, density} <- [
                  {"Reading (public)", nil},
                  {"Working (admin)", "gf-density-working"}
                ]
              }
              class={[
                "flex flex-col gap-3 rounded-panel border border-line bg-surface p-panel",
                density
              ]}
            >
              <span class="text-caption font-semibold uppercase tracking-wide text-muted">
                {label}
              </span>
              <div :for={{class, role, sample} <- @type_scale} class="flex flex-col">
                <span class="text-caption text-muted">{class} · {role}</span>
                <span class={[
                  class,
                  "text-ink truncate",
                  class in ~w(text-page text-section text-subsection) && "font-brand font-semibold",
                  class == "text-caption" && "font-semibold uppercase tracking-wide text-muted"
                ]}>
                  {sample}
                </span>
              </div>
              <span class="text-caption text-muted">font-serif · what a Source wrote</span>
              <span class="font-serif text-body text-ink-2">
                Larger Empty Oak Apple. Green with scattered purplish spots, 18–32 mm in diameter.
              </span>
            </div>
          </div>
        </.section>

        <.section id="density" title="Density">
          <:aside>Reading by default · Working inside gf-density-working (the admin shell)</:aside>
          <div class="grid gap-block lg:grid-cols-2">
            <div
              :for={{label, density} <- [{"Reading", nil}, {"Working", "gf-density-working"}]}
              class={["flex flex-col gap-3", density]}
            >
              <span class="text-caption font-semibold uppercase tracking-wide text-muted">
                {label}
              </span>
              <div class="flex flex-wrap items-center gap-2">
                <.button variant="primary">Approve 9 notes</.button>
                <.button>Rename</.button>
                <input
                  type="text"
                  placeholder="Search for the new parent…"
                  class="h-ctl flex-1 rounded-ctl border border-line-strong bg-surface px-3 text-ui"
                />
              </div>
              <div class="overflow-hidden rounded-panel border border-line bg-surface text-ui">
                <div
                  :for={name <- ["Quercus rubra", "Quercus velutina", "Quercus imbricaria"]}
                  class="flex h-row items-center border-b border-line px-3 last:border-b-0"
                >
                  <em>{name}</em>
                </div>
              </div>
            </div>
          </div>
        </.section>

        <.section id="shape" title="Radius and elevation">
          <div class="flex flex-wrap gap-6 text-meta text-ink-2">
            <div class="flex flex-col items-center gap-1">
              <span class="size-16 rounded-ctl border border-line-strong bg-surface"></span>rounded-ctl (4px)
            </div>
            <div class="flex flex-col items-center gap-1">
              <span class="size-16 rounded-panel border border-line-strong bg-surface"></span>rounded-panel (8px)
            </div>
            <div class="flex flex-col items-center gap-1">
              <span class="size-16 rounded-full border border-line-strong bg-surface"></span>rounded-full
            </div>
            <div class="flex flex-col items-center gap-1">
              <span class="size-16 rounded-panel bg-surface shadow-float"></span>shadow-float (only what floats)
            </div>
          </div>
        </.section>

        <.example
          id="button"
          title="button"
          code={
            ~S'''
            <.button variant="primary">Approve 9 notes</.button>
            <.button icon="ph-plus">Add synonym</.button>
            <.button variant="ghost">Show the evidence</.button>
            <.button variant="danger" icon="ph-trash">Delete taxon</.button>
            <.button icon="ph-x" label="Close" icon_only />
            <.button size="sm">Accept</.button>
            '''
          }
        >
          <div class="flex flex-wrap items-center gap-2">
            <.button variant="primary">Approve 9 notes</.button>
            <.button icon="ph-plus">Add synonym</.button>
            <.button variant="ghost">Show the evidence</.button>
            <.button variant="danger" icon="ph-trash">Delete taxon</.button>
            <.button icon="ph-x" label="Close" icon_only />
            <.button size="sm">Accept</.button>
            <.button disabled>Move</.button>
          </div>
        </.example>

        <.example
          id="chip"
          title="chip"
          code={
            ~S'''
            <.chip variant={:ok}>Complete</.chip>
            <.chip variant={:warn}>In progress</.chip>
            <.chip variant={:rank}>Family</.chip>
            <.chip variant={:count}>358</.chip>
            <.chip variant={:recommended}>Recommended</.chip>
            <.chip on_remove={JS.push("remove")} remove_label="Remove Quercus rubra">Quercus rubra</.chip>
            '''
          }
        >
          <div class="flex flex-wrap items-center gap-2">
            <.chip variant={:ok}>Complete</.chip>
            <.chip variant={:warn}>In progress</.chip>
            <.chip variant={:danger}>Conflicts with Gallformers</.chip>
            <.chip variant={:info}>Publication</.chip>
            <.chip variant={:rank}>Family</.chip>
            <.chip>Plantae</.chip>
            <.chip variant={:count}>358</.chip>
            <.chip variant={:recommended}>Recommended</.chip>
            <.chip on_remove={JS.push("noop")} remove_label="Remove Quercus rubra">
              <em>Quercus rubra</em>
            </.chip>
          </div>
        </.example>

        <.example
          :let={theme}
          id="menu"
          title="menu"
          code={
            ~S'''
            <.menu id="browse" label="Browse">
              <:item navigate={~p"/galls"}>Galls</:item>
              <:item navigate={~p"/hosts"}>Hosts</:item>
            </.menu>
            '''
          }
        >
          <.menu id={"demo-menu-#{theme}"} label="Browse" align={:left}>
            <:item navigate="/galls">Galls</:item>
            <:item navigate="/hosts">Hosts</:item>
            <:item navigate="/places">Places</:item>
          </.menu>
        </.example>

        <.example
          id="page-header"
          title="page_header"
          code={
            ~S'''
            <.page_header>
              <:crumb navigate={~p"/family/Cynipidae"}>Cynipidae</:crumb>
              <:crumb navigate={~p"/genus/Callirhytis"} italic>Callirhytis</:crumb>
              <:title name>Callirhytis quercuscornigera (agamic)</:title>
              <:chip variant={:warn}>In progress</:chip>
              <:meta label="Other generation"><.link …><em>C. quercuscornigera (sexgen)</em></.link></:meta>
              <:meta label="Season">Spring, Summer</:meta>
              <:action><.button navigate={…}>Edit</.button></:action>
            </.page_header>
            '''
          }
        >
          <div class="flex flex-col gap-6">
            <.page_header>
              <:crumb href="#">Cynipidae</:crumb>
              <:crumb href="#">Cynipinae</:crumb>
              <:crumb href="#">Cynipini</:crumb>
              <:crumb href="#" italic>Callirhytis</:crumb>
              <:title name>Callirhytis quercuscornigera (agamic)</:title>
              <:chip variant={:warn}>In progress</:chip>
              <:meta label="Other generation">
                <a href="#"><em>C. quercuscornigera (sexgen)</em></a>
              </:meta>
              <:meta label="Season">Spring, Summer</:meta>
              <:meta label="Location">stem</:meta>
              <:action><.button icon="ph-pencil-simple">Edit</.button></:action>
            </.page_header>
            <div class="gf-density-working">
              <.page_header>
                <:crumb href="#">Taxonomy</:crumb>
                <:crumb href="#">Plantae</:crumb>
                <:title>Acanthaceae</:title>
                <:chip variant={:rank}>Family</:chip>
                <:chip>Plantae</:chip>
                <:meta>Created Oct 28, 2026 · Updated Oct 28, 2026</:meta>
                <:action><.button icon="ph-arrow-square-out">View public page</.button></:action>
              </.page_header>
            </div>
          </div>
        </.example>

        <.example
          id="section"
          title="section"
          code={
            ~S'''
            <.section title="Hosts" count={14}>
              <:aside>Oldest first · <.link …>newest first</.link></:aside>
              …
            </.section>
            '''
          }
        >
          <.section title="Hosts" count={14}>
            <:aside>Oldest first · <a href="#">newest first</a></:aside>
            <p class="text-ui italic text-ink-2">
              Quercus buckleyi · Quercus falcata · Quercus hemisphaerica · Quercus ilicifolia …
            </p>
          </.section>
        </.example>

        <.example
          id="panel"
          title="panel"
          code={
            ~S'''
            <.panel title="In the tree">…</.panel>
            <.panel variant={:info} title="Gallformers ID Notes">…</.panel>
            <.panel variant={:danger} title="Delete">…</.panel>
            '''
          }
        >
          <div class="grid gap-3 md:grid-cols-3">
            <.panel title="In the tree">
              <p class="text-meta text-ink-2">Family in Plantae · 10 child taxa</p>
            </.panel>
            <.panel variant={:info} title="Gallformers ID Notes">
              <p class="text-meta">
                Old or damaged specimens are difficult to distinguish from C. quercuspunctata.
              </p>
            </.panel>
            <.panel variant={:danger} title="Delete">
              <p class="text-meta text-ink-2">Can't be deleted while 10 child taxa refer to it.</p>
            </.panel>
          </div>
        </.example>

        <.example
          id="rail"
          title="rail"
          code={
            ~S'''
            <div class="gf-with-rail">
              <div>…main column…</div>
              <.rail width={:wide}>…photo, map, facts…</.rail>
            </div>
            '''
          }
        >
          <div class="gf-with-rail">
            <div class="flex min-h-40 items-center justify-center rounded-panel border border-dashed border-line-strong text-meta text-muted">
              main column
            </div>
            <.rail width={:wide}>
              <div class="flex min-h-40 items-center justify-center rounded-panel border border-dashed border-line-strong text-meta text-muted">
                rail (420px; first on phones)
              </div>
            </.rail>
          </div>
        </.example>

        <.example
          id="tab_nav"
          title="tab_nav"
          code={
            ~S'''
            <.tab_nav label="Browse by">
              <:tab :for={{label, path} <- BrowseHelpers.browse_tabs()} navigate={path} current={path == "/galls"}>
                {label}
              </:tab>
            </.tab_nav>
            '''
          }
        >
          <.tab_nav label="Browse by">
            <:tab href="#tab_nav" current>By what causes them</:tab>
            <:tab href="#tab_nav">By host plant</:tab>
            <:tab href="#tab_nav">By place</:tab>
          </.tab_nav>
        </.example>

        <.example
          :let={theme}
          id="data_table"
          title="data_table"
          code={
            ~S'''
            <.data_table id="sources" rows={@sources} row_navigate={&"/source/#{&1.id}"} sort={@sort}>
              <:col :let={s} label="Title" field={:title} sortable grow>{s.title}</:col>
              <:col :let={s} label="Authors" field={:authors}>{s.authors}</:col>
              <:col :let={s} label="Year" field={:year} sortable numeric>{s.year}</:col>
              <:col :let={s} label="Status"><.chip :if={s.complete} variant={:ok}>Complete</.chip></:col>
              <:empty>No Sources match.</:empty>
            </.data_table>
            '''
          }
        >
          <.data_table id={"dt-#{theme}"} rows={@sample_sources} sort={%{field: :year, dir: :desc}}>
            <:col :let={s} label="Title" field={:title} sortable grow>{s.title}</:col>
            <:col :let={s} label="Authors" field={:authors}>{s.authors}</:col>
            <:col :let={s} label="Year" field={:year} sortable numeric>{s.year}</:col>
            <:col :let={s} label="Status" field={:status}>
              <.chip :if={s.status} variant={:ok}>{s.status}</.chip>
            </:col>
            <:col :let={s} label="Kind" field={:kind}>{s.kind}</:col>
          </.data_table>
          <p class="text-caption text-muted">
            The Kind column is empty for every row, so it isn't shown.
          </p>
        </.example>

        <.example
          id="fact_list"
          title="fact_list"
          code={
            ~S'''
            <.fact_list columns={3}>
              <:item label="Detachable">Integral</:item>
              <:item label="Shape" value={nil} />
            </.fact_list>
            '''
          }
        >
          <.fact_list columns={3}>
            <:item label="Detachable">Integral</:item>
            <:item label="Color">brown, gray</:item>
            <:item label="Texture">honeydew</:item>
            <:item label="Season">Spring, Summer</:item>
            <:item label="Location">stem</:item>
            <:item label="Form">abrupt swelling</:item>
            <:item label="Abundance" value={nil} />
            <:item label="Shape" value={nil} />
            <:item label="Walls" value={nil} />
          </.fact_list>
        </.example>

        <.example
          id="name_list"
          title="name_list"
          code={
            ~S'''
            <.name_list items={@host_names} columns={4} italic />
            '''
          }
        >
          <.name_list items={@sample_hosts} columns={4} italic />
        </.example>

        <.example
          id="stat"
          title="stat"
          code={
            ~S'''
            <.stat value={3976} label="Galls" navigate={~p"/galls"} />
            '''
          }
        >
          <div class="flex flex-wrap gap-x-10 gap-y-3">
            <.stat value={3976} label="Galls" navigate="/galls" />
            <.stat value={2589} label="Host plants" />
            <.stat value={930} label="Sources" />
          </div>
        </.example>

        <.example
          id="empty_state"
          title="empty_state"
          code={
            ~S'''
            <.empty_state title="No galls match" icon="ph-funnel">
              Remove a filter to see more.
              <:action><.button phx-click="clear">Clear all filters</.button></:action>
            </.empty_state>
            '''
          }
        >
          <.empty_state title="No galls match" icon="ph-funnel">
            Remove a filter to see more.
            <:action><.button>Clear all filters</.button></:action>
          </.empty_state>
        </.example>

        <.example
          id="prose"
          title="prose"
          code={
            ~S'''
            <.prose markdown={@article.content} size={:lg} class="max-w-text" />
            <.prose markdown={@note.description} size={:sm} font={:serif} />
            '''
          }
        >
          <.prose
            class="max-w-text"
            markdown="## Being prepared\n\nBring something to cut a gall open and a way to record where you found it. A **detachable** gall can be collected whole.\n\n- A small sharp knife\n- Ziploc or organza bags\n\n> Raising an inducer is not hard, but each attempt has low odds.\n\n<details><summary>Why rear them?</summary>Most undescribed galls need a reared adult before anyone can describe the species.</details>"
          />
        </.example>

        <.example
          id="edit_toggle"
          title="edit_toggle, edit_scope"
          code={
            ~S'''
            <.edit_toggle editing={@editing} path={~p"/gall/#{@gall.id}"} />
            <.edit_scope kind={:elsewhere} href={…}>Photos: in the photo manager</.edit_scope>
            <.edit_scope kind={:follows}>Season, Location and Form follow from the Traits below.</.edit_scope>
            '''
          }
        >
          <div class="flex flex-col gap-3">
            <div class="flex gap-3">
              <.edit_toggle editing={false} path="/gall/821" />
              <.edit_toggle editing={true} path="/gall/821" />
            </div>
            <.edit_scope kind={:elsewhere} href="#">Photos: in the photo manager</.edit_scope>
            <.edit_scope kind={:follows}>
              Season, Location and Form follow from the Traits below.
            </.edit_scope>
          </div>
        </.example>

        <.example
          id="fact_row"
          title="fact_row"
          code={
            ~S'''
            <.fact_row fact_key={{:host, h.taxon_id}} sources={@sources[key]} pending={@pending[key]}>
              <.taxon_name name={h.name} />
            </.fact_row>
            '''
          }
        >
          <ul class="flex max-w-form flex-col divide-y divide-line">
            <.fact_row fact_key={{:host, 1}} sources={["Weld (1959)", "Felt (1940)"]}>
              <.taxon_name name="Quercus alba" />
            </.fact_row>
            <.fact_row
              fact_key={{:host, 2}}
              sources={["Gallformers legacy data"]}
              pending={%{action: :withdraw, state: :in_tray}}
            >
              <.taxon_name name="Quercus bicolor" />
            </.fact_row>
            <.fact_row fact_key={{:host, 3}} pending={%{action: :add, state: :waiting}}>
              <.taxon_name name="Quercus macrocarpa" />
            </.fact_row>
          </ul>
        </.example>

        <.example
          id="review_apply"
          title="review_apply"
          code={
            ~S'''
            <.dialog id="review" title="Review and apply" size={:lg} show>
              <.review_apply id="review-body" items={@preview} evidence={@evidence} confirmed={@confirmed} />
            </.dialog>
            '''
          }
        >
          <div class="max-w-2xl rounded-panel border border-line bg-surface p-panel">
            <.review_apply
              id="sg-review"
              evidence={%{text: "", observations: [], source_id: nil}}
              confirmed={[]}
              items={[
                %{
                  id: 1,
                  kind: :fact,
                  text: "Withdraw host: Quercus alba",
                  flags: [
                    %{kind: :supersedes, text: "Supersedes Weld 1959's host"},
                    %{kind: :needs_reason, text: "A reason is needed"}
                  ]
                },
                %{id: 2, kind: :fact, text: "Add Season: fall", flags: [%{kind: :new, text: "New"}]},
                %{
                  id: 4,
                  kind: :fact,
                  text: "Add Recorded in: Virginia",
                  flags: [%{kind: :new, text: "New"}],
                  evidence: %{
                    text: "Seen on iNaturalist.",
                    observations: [%{provider: "inaturalist", id: "123456"}],
                    source: nil
                  }
                },
                %{
                  id: 3,
                  kind: :editorial,
                  text: "Gallformers code: q-alba-cup",
                  flags: [%{kind: :needs_confirmation, text: "iNaturalist links use the code"}]
                }
              ]}
            />
          </div>
        </.example>

        <.example
          id="fact_chip"
          title="fact_chip"
          code={
            ~S'''
            <.fact_chip :for={v <- @values} fact_key={{:trait, "season", v}} sources={@sources[v]}
              pending={@pending[v]} target={@myself}>{v}</.fact_chip>
            '''
          }
        >
          <div class="flex flex-wrap gap-1.5">
            <.fact_chip fact_key={{:trait, "season", "Spring"}} sources={["Weld (1959)"]}>
              Spring
            </.fact_chip>
            <.fact_chip
              fact_key={{:trait, "season", "Summer"}}
              pending={%{action: :withdraw, state: :in_tray}}
            >
              Summer
            </.fact_chip>
            <.fact_chip
              fact_key={{:trait, "season", "Fall"}}
              pending={%{action: :add, state: :in_tray}}
            >
              Fall
            </.fact_chip>
          </div>
        </.example>

        <.example
          id="change_tray"
          title="change_tray (GallformersWeb.TrayLive)"
          code={
            ~S'''
            <.change_tray summary={Curation.summary(@curator)} />
            '''
          }
        >
          <p class="mb-2 text-meta text-muted">
            Pinned to the foot of the screen; shown here in a box.
          </p>
          <div class="relative h-16 transform-gpu overflow-hidden rounded-panel border border-line bg-paper">
            <.change_tray summary={
              %{
                count: 2,
                lines: [
                  "Callirhytis quercuscornigera: Withdraw host: Quercus alba",
                  "Abundance: common"
                ],
                oldest_at: nil
              }
            } />
          </div>
        </.example>

        <.example
          id="change_entry"
          title="change_entry"
          code={
            ~S'''
            <.change_entry :for={group <- Catalog.changes(limit: 20)} group={group} />
            '''
          }
        >
          <ul class="flex max-w-2xl flex-col">
            <.change_entry group={
              %{
                key: "sg-change",
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
                  }
                ],
                counts: %{added: 1},
                names: [],
                taxa: []
              }
            } />
          </ul>
        </.example>

        <.example
          id="key_path"
          title="key_path"
          code={
            ~S'''
            <.key_path layout={:panel} key={@key} path={@path} terminal={@terminal} link={@link} />
            <.key_path layout={:bar} key={@key} path={@path} terminal={@terminal} link={@link} class="lg:hidden" />
            '''
          }
        >
          <div class="max-w-xs">
            <GallformersWeb.KeyComponents.key_path
              layout={:panel}
              key={
                %{
                  couplets: %{
                    "1" => %{leads: [%{text: "Galls on leaves."}, %{text: "Galls on stems or buds."}]},
                    "4" => %{leads: [%{text: "Gall woody, with horns."}, %{text: "Gall smooth."}]}
                  }
                }
              }
              path={[{"1", 1, nil}, {"4", 0, nil}]}
              link="/key/sample?path=1b.4a"
            />
          </div>
        </.example>

        <.example
          id="dangerous_delete_modal"
          title="dangerous_delete_modal"
          code={
            ~S'''
            <.dangerous_delete_modal :if={@record} show={@show_delete_modal} item_type="article"
              item_name={@record.title} consequences={[…]} confirmation_value={@delete_confirmation} />
            '''
          }
        >
          <p class="mb-2 text-meta text-muted">
            A dialog; shown here in a box. Delete stays disabled until the name is typed exactly.
          </p>
          <div class="relative h-96 transform-gpu overflow-hidden rounded-panel border border-line">
            <.dangerous_delete_modal
              id="sg-dangerous-delete"
              show
              item_type="article"
              item_name="Oak apples in winter"
              consequences={[
                "The article content, publication state, and tags will be permanently deleted.",
                "All images owned by this article will be deleted from storage."
              ]}
            />
          </div>
        </.example>

        <.example
          id="gf-file"
          title=".gf-file"
          code={
            ~S'''
            <.live_file_input upload={@uploads.key_json} class="gf-file" />
            '''
          }
        >
          <input type="file" class="gf-file" aria-label="Upload a file" />
        </.example>

        <.example
          id="file_drop"
          title="file_drop"
          code={
            ~S'''
            <div id="uploader" phx-hook="ImageUpload" phx-update="ignore" data-max-files="20">
              <.file_drop accept="image/jpeg,image/png" multiple hint="Max 20 files. JPG or PNG only." />
              <div data-preview-container></div>
            </div>
            <.file_drop layout={:row} multiple label="Choose files… or drop JPG or PNG images here" />
            '''
          }
        >
          <.file_drop accept="image/jpeg,image/png" multiple hint="Max 20 files. JPG or PNG only." />
          <.file_drop layout={:row} multiple label="Choose files… or drop JPG or PNG images here" />
        </.example>

        <.example
          :let={theme}
          id="radio_card"
          title="radio_card"
          code={
            ~S'''
            <div role="radiogroup" aria-label="Which plant does Weld mean?" class="grid gap-1.5">
              <.radio_card id="q-0" name="q" value={0} checked={@choice == 0} recommended
                summary="The accepted name; Weld's spelling is a variant." phx-click="pick" phx-value-choice={0}>
                <:label>Quercus lobata</:label>
                <:aside>2 of 3 readers</:aside>
              </.radio_card>
              <.radio_card id="q-1" name="q" value={1} checked={@choice == 1} … >
                <:label>Another plant</:label>
                <:follow>…the plant search…</:follow>
              </.radio_card>
            </div>
            '''
          }
        >
          <div role="radiogroup" aria-label="Which plant does Weld mean?" class="grid gap-1.5">
            <.radio_card
              :for={
                {value, label, summary, rec} <- [
                  {"0", "Quercus lobata", "The accepted name; Weld's spelling is a variant.", true},
                  {"1", "Another plant", "Choose it from the plant search.", false},
                  {"2", "Keep it as written", nil, false}
                ]
              }
              id={"rc-#{theme}-#{value}"}
              name={"rc-#{theme}"}
              value={value}
              checked={@sample_choice == value}
              recommended={rec}
              summary={summary}
              phx-click="sample_choice"
              phx-value-choice={value}
            >
              <:label>{label}</:label>
              <:aside :if={rec}>2 of 3 readers</:aside>
              <:follow :if={value == "1"}>
                <span class="text-meta text-muted">The plant search goes here.</span>
              </:follow>
            </.radio_card>
          </div>
        </.example>

        <.example
          :let={theme}
          id="review_option"
          title="review_option"
          code={
            ~S'''
            <ReviewComponents.review_option id="ro-0" name="ro" value="0" checked={@choice == "0"}
              recommended by="2 of 3 readers" label="Follow Weld 1959"
              summary="The tree moves Andricus foo under Callirhytis." tags={[%{text: "newest", kind: :best}]}
              on_pick="pick" />
            <ReviewComponents.review_option id="ro-1" name="ro" value="1" checked={@choice == "1"}
              label="Decline" summary="The tree stays; a reason is required." on_pick="pick">
              <:follow>…the reason…</:follow>
            </ReviewComponents.review_option>
            '''
          }
        >
          <div role="radiogroup" aria-label="Follow the paper?" class="grid gap-1.5">
            <GallformersWeb.ReviewComponents.review_option
              id={"ro-#{theme}-0"}
              name={"ro-#{theme}"}
              value="0"
              checked={@sample_choice == "0"}
              recommended
              by="2 of 3 readers"
              label="Follow Weld 1959"
              summary="The tree moves Andricus foo under Callirhytis."
              tags={[%{text: "newest", kind: :best}]}
              on_pick="sample_choice"
            />
            <GallformersWeb.ReviewComponents.review_option
              id={"ro-#{theme}-1"}
              name={"ro-#{theme}"}
              value="1"
              checked={@sample_choice == "1"}
              label="Decline"
              summary="The tree stays; a reason is required."
              on_pick="sample_choice"
            >
              <:follow>
                <span class="text-meta text-muted">The reason goes here.</span>
              </:follow>
            </GallformersWeb.ReviewComponents.review_option>
          </div>
        </.example>

        <.example
          :let={theme}
          id="taxonomic_position"
          title="taxonomic_position"
          code={
            ~S'''
            <FactsComponents.taxonomic_position id="position"
              position={Import.taxonomic_position(@taxon.id)} />
            '''
          }
        >
          <GallformersWeb.FactsComponents.taxonomic_position
            id={"position-#{theme}"}
            position={
              %{
                placement: %{
                  fact_id: 1,
                  parent: %{name: "Callirhytis", rank: :genus},
                  source: %{source_id: 1, name: "Weld 1959"}
                },
                name: %{
                  fact_id: 2,
                  name: "Callirhytis quercuspunctata",
                  rank: :species,
                  authorship: "(Bassett, 1863)",
                  sensu: nil,
                  source: %{source_id: 1, name: "Weld 1959"}
                },
                disagreeing: []
              }
            }
          />
        </.example>

        <.example
          :let={theme}
          id="segmented_switch"
          title="segmented_switch"
          code={
            ~S'''
            <.segmented_switch label="View" value={@view} event="galls_view" param="view">
              <:option value={:photos}>Photos</:option>
              <:option value={:table}>Table</:option>
            </.segmented_switch>
            <.segmented_switch label="View" value={@mode} event="toggle_view" param="view" target={@myself}>
              <:option value={:grid} icon="ph-squares-four" label="Grid view" />
              <:option value={:table} icon="ph-list" label="Table view" />
            </.segmented_switch>
            <.segmented_switch label="Click counties as" value={@type} event="set_type" param="type" size="sm">…</.segmented_switch>
            '''
          }
        >
          <div class="flex flex-wrap items-center gap-3">
            <.segmented_switch
              id={"sw-#{theme}"}
              label="View"
              value={@sample_view}
              event="sample_view"
              param="view"
            >
              <:option value="photos">Photos</:option>
              <:option value="table">Table</:option>
            </.segmented_switch>
            <.segmented_switch label="View" value="grid" event="noop" param="view">
              <:option value="grid" icon="ph-squares-four" label="Grid view" />
              <:option value="table" icon="ph-list" label="Table view" />
            </.segmented_switch>
            <.segmented_switch label="Click counties as" value="native" event="noop" size="sm">
              <:option value="native">Native</:option>
              <:option value="introduced">Introduced</:option>
            </.segmented_switch>
            <.segmented_switch label="View" value="grid" event="noop" disabled>
              <:option value="grid">Grid</:option>
              <:option value="table">Table</:option>
            </.segmented_switch>
          </div>
        </.example>

        <.example
          :let={theme}
          id="data_table-selection"
          title="data_table: selection, row state, row attributes"
          code={
            ~S'''
            <.data_table
              id="images-table"
              rows={@images}
              row_attrs={&%{"data-image-id" => &1.id}}
              row_state={&if(unattributed?(&1), do: :warn)}
              selectable
              selected={@selected_ids}
              selectable_row={&(&1.id != @source_id)}
              select_event="toggle_copy_target"
              select_all="select_all_targets"
              target={@myself}
            >
              <:col :let={i} label="Caption" grow>{i.caption}</:col>
            </.data_table>
            '''
          }
        >
          <.data_table
            id={"dt-select-#{theme}"}
            rows={
              @sample_sources |> Enum.with_index(1) |> Enum.map(fn {s, i} -> Map.put(s, :id, i) end)
            }
            row_attrs={&%{"data-source-id" => &1.id}}
            row_state={&if(&1.status == nil, do: :warn)}
            selectable
            selected={@sample_selected}
            selectable_row={&(&1.id != 3)}
            select_event="sample_select"
            select_all="sample_select_all"
            select_label={&"Select #{&1.title}"}
          >
            <:col :let={s} label="Title" grow>{s.title}</:col>
            <:col :let={s} label="Year" numeric>{s.year}</:col>
          </.data_table>
          <p class="text-caption text-muted">
            The second row is :warn (no status); the third can't be selected.
          </p>
        </.example>

        <.example
          :let={theme}
          id="progress_bar"
          title="progress_bar"
          code={
            ~S'''
            Syncing from WCVP: 40 / 120
            <.progress_bar value={40} max={120} label="Syncing from WCVP" />
            <.progress_bar max={30} segments={[{12, :ok}, {9, :info}]} size="sm" class="w-36" />
            '''
          }
        >
          <div class="flex flex-col gap-2 text-meta text-ink-2">
            Syncing from WCVP: 40 / 120
            <.progress_bar id={"pb-#{theme}"} value={40} max={120} label="Syncing from WCVP" />
            <span>12 decided · 9 with a proposed answer, of 30</span>
            <.progress_bar max={30} segments={[{12, :ok}, {9, :info}]} size="sm" class="w-36" />
          </div>
        </.example>

        <.example
          id="loading_spinner"
          title="loading_spinner"
          code={
            ~S'''
            <.loading_spinner size="sm" label="Searching WCVP…" /> Searching WCVP…
            <.button variant="primary" disabled>
              <.loading_spinner size="sm" tone={:current} label="Loading" /> Loading…
            </.button>
            '''
          }
        >
          <div class="flex flex-wrap items-center gap-4">
            <span class="flex items-center gap-2 text-meta text-muted">
              <.loading_spinner size="sm" label="Searching WCVP…" /> Searching WCVP…
            </span>
            <.loading_spinner />
            <.button variant="primary" disabled>
              <.loading_spinner size="sm" tone={:current} label="Loading" /> Loading…
            </.button>
            <.button disabled>
              <.loading_spinner size="sm" tone={:current} label="Loading" /> Loading…
            </.button>
          </div>
        </.example>

        <.example
          id="chrome"
          title="theme_switch, palette_trigger (Layouts)"
          code={
            ~S'''
            <Layouts.theme_switch />
            <Layouts.palette_trigger />
            <Layouts.palette_trigger compact />
            '''
          }
        >
          <div class="flex flex-wrap items-center gap-4">
            <GallformersWeb.Layouts.theme_switch />
            <GallformersWeb.Layouts.palette_trigger class="w-64" />
            <GallformersWeb.Layouts.palette_trigger compact />
          </div>
        </.example>

        <.example
          id="bar_chart"
          title="bar_chart"
          code={
            ~S'''
            <.bar_chart id="daily" label="Page views and unique visitors by day" data={@days}
              series={[%{key: :views, label: "Page views", tone: :brand},
                       %{key: :visitors, label: "Unique visitors", tone: :autumn}]} />
            '''
          }
        >
          <.bar_chart
            id="sg-bar-chart"
            label="Page views and unique visitors by day"
            data={
              for {views, visitors, i} <-
                    Enum.zip([
                      [3320, 3250, 2830, 3080, 3340, 3490, 2870],
                      [480, 520, 470, 510, 520, 530, 440],
                      1..7
                    ]) do
                %{label: "Oct #{7 + i}", views: views, visitors: visitors}
              end
            }
            series={[
              %{key: :views, label: "Page views", tone: :brand},
              %{key: :visitors, label: "Unique visitors", tone: :autumn}
            ]}
          />
        </.example>

        <.example
          id="share_list"
          title="share_list"
          code={
            ~S'''
            <.share_list id="devices" items={@devices} name={&String.capitalize(&1.device_type)} />
            '''
          }
        >
          <.share_list
            id="sg-share-list"
            class="max-w-md"
            items={[
              %{name: "Desktop", count: 26_814, percentage: 53.7},
              %{name: "Mobile", count: 23_071, percentage: 46.2},
              %{name: "Tablet", count: 83, percentage: 0.2}
            ]}
            name={& &1.name}
          />
        </.example>

        <.example
          id="article_card"
          title="article_card"
          code={
            ~S'''
            <.article_card href={~p"/articles/#{a.slug}"} title={a.title} topic="faq"
              icon="ph-question" tone={:autumn} meta="Adam Kranz · January 26, 2026">
              Preface At the time of writing…
            </.article_card>
            <.article_card … featured label="Newest" />
            '''
          }
        >
          <div class="flex flex-col gap-block">
            <.article_card
              href="#"
              title="Gall Lookalikes"
              topic="identification"
              icon="ph-magnifying-glass-plus"
              tone={:sky}
              meta="Gallformers Contributors · October 27, 2026"
              label="Newest"
              featured
            >
              Organisms that look like galls but are not.
            </.article_card>
            <ul class="grid gap-block sm:grid-cols-3">
              <li :for={
                {title, topic, icon, tone} <- [
                  {"FAQ About Undescribed Galls", "faq", "ph-question", :autumn},
                  {"Gallformers Patrons", "meta", "ph-hand-heart", :brand},
                  {"Publications", "article", "ph-article", :plain}
                ]
              }>
                <.article_card
                  href="#"
                  title={title}
                  topic={topic}
                  icon={icon}
                  tone={tone}
                  meta="Adam Kranz · January 26, 2026"
                  class="h-full"
                >
                  At the time of writing, of the 3112 galls listed on Gallformers, 1117 are undescribed.
                </.article_card>
              </li>
            </ul>
          </div>
        </.example>

        <.example
          id="chip_nav"
          title="chip_nav"
          code={
            ~S'''
            <.chip_nav label="Topics">
              <:chip href={~p"/articles"} current>All</:chip>
              <:chip href={~p"/articles?tag=faq"} count={1}>faq</:chip>
            </.chip_nav>
            '''
          }
        >
          <.chip_nav label="Topics">
            <:chip href="#" current>All</:chip>
            <:chip href="#" count={2}>identification</:chip>
            <:chip href="#" count={1}>faq</:chip>
          </.chip_nav>
        </.example>

        <.example
          id="link_tile"
          title="link_tile"
          code={
            ~S'''
            <.link_tile href={~p"/keys"} icon="ph-tree-structure" name="Identification keys">
              4 step-by-step keys
            </.link_tile>
            '''
          }
        >
          <div class="max-w-xs">
            <.link_tile href="#" icon="ph-tree-structure" name="Identification keys">
              4 step-by-step keys
            </.link_tile>
          </div>
        </.example>

        <.example
          id="key_couplet"
          title="key_couplet"
          code={
            ~S'''
            <.key_couplet number="3" couplet={@key.couplets["3"]} key_slug={@key.slug}
              state={:active} gall_names={@gall_names} />
            '''
          }
        >
          <ol class="flex max-w-form flex-col gap-1">
            <GallformersWeb.KeyComponents.key_couplet
              number="3"
              key_slug="sample"
              state={:active}
              couplet={
                %{
                  leads: [
                    %{
                      text: "Fore wing with conspicuous stigma. Metasoma elongate and cylindrical.",
                      images: [],
                      destination: %{type: "couplet", number: "4", label: "Ichneumonoidea"}
                    },
                    %{
                      text: "Fore wing without stigma. Metasoma ovate.",
                      notes: "Often somewhat laterally compressed.",
                      images: [],
                      destination: %{type: "taxon", name: "Synergus", context: "Cynipidae: Synergini"}
                    }
                  ]
                }
              }
            />
          </ol>
        </.example>

        <.example
          :let={theme}
          id="photo_viewer"
          title="photo_viewer"
          code={
            ~S'''
            <.photo_viewer id="gall-images" photos={@images} name={@gall.name}
              edit_href={~p"/admin/galls/#{@gall.id}" <> "#images"} admin={Accounts.admin?(@current_user)} />
            '''
          }
        >
          <div class="max-w-md">
            <.photo_viewer
              id={"sg-photos-#{theme}"}
              name="Callirhytis quercuscornigera (agamic)"
              photos={[
                %{
                  src:
                    "https://dhz6u1p7t6okk.cloudfront.net/gall/821/821_20215122045701_original.PNG",
                  thumb: "https://dhz6u1p7t6okk.cloudfront.net/gall/821/821_20215122045701_small.PNG",
                  caption: "Agamic generation on a stem",
                  creator: "nsferguson",
                  license: "CC-BY",
                  licenselink: "https://creativecommons.org/licenses/by/4.0/"
                },
                %{
                  src: "/images/noimage.jpg",
                  creator: "Gallformers",
                  license: "Public Domain / CC0",
                  sourcelink: "https://www.gallformers.org"
                }
              ]}
            />
          </div>
        </.example>

        <.example
          id="gall_card"
          title="gall_card"
          code={
            ~S'''
            <.gall_card navigate={~p"/gall/#{g.id}"} name={g.name} image_url={g.image_url}
                        subtitle="stem · abrupt swelling · Spring" size={:sm}>
              <:chip :if={g.undescribed} variant={:info}>Undescribed</:chip>
            </.gall_card>
            '''
          }
        >
          <div class="grid grid-cols-2 gap-4 sm:grid-cols-4">
            <.gall_card
              navigate="/gall/821"
              name="Callirhytis quercuscornigera (agamic)"
              image_url="https://dhz6u1p7t6okk.cloudfront.net/gall/821/821_20215122045701_original.PNG"
              image_alt=""
              subtitle="stem · abrupt swelling · Spring"
              size={:sm}
            />
            <.gall_card
              navigate="/gall/1"
              name="Unknown (Cynipidae) q-rubra-spur-gall"
              subtitle="stem · Spring"
              size={:sm}
            >
              <:chip variant={:info}>Undescribed</:chip>
            </.gall_card>
          </div>
        </.example>

        <.example
          id="category_tile"
          title="category_tile"
          code={
            ~S'''
            <ul class="grid gap-x-6 sm:grid-cols-2">
              <li :for={genus <- @genera}>
                <.category_tile navigate={~p"/id?g=#{genus.name}"} name={genus.name}
                                count={genus.count} image_url={genus.image_url} icon="gf-host" italic />
              </li>
            </ul>
            <.category_tile navigate="/galls" name="Gall midges" count={1229} layout={:tile} />
            '''
          }
        >
          <div class="flex flex-col gap-block">
            <ul class="grid gap-x-6 sm:grid-cols-2">
              <li>
                <.category_tile
                  navigate="/id?g=Quercus"
                  name="Quercus"
                  count={1349}
                  image_url="https://dhz6u1p7t6okk.cloudfront.net/gall/821/821_20215122045701_small.PNG"
                  icon="gf-host"
                  italic
                />
              </li>
              <li>
                <.category_tile navigate="/galls" name="Gall midges" count={1229} />
              </li>
            </ul>
            <div class="gf-photo-grid max-w-xl" data-size="sm">
              <.category_tile navigate="/galls" name="Gall wasps" count={1397} layout={:tile} />
              <.category_tile navigate="/galls" name="Mites" count={306} layout={:tile} />
            </div>
          </div>
        </.example>

        <.example
          id="family_card"
          title="family_card"
          code={
            ~S'''
            <div class="grid gap-3 md:grid-cols-2 xl:grid-cols-3">
              <.family_card :for={card <- group.families} card={card} expanded={@expanded} on_toggle="toggle_node" />
            </div>
            '''
          }
        >
          <div class="grid gap-3 md:grid-cols-2">
            <.family_card card={@sample_family} on_toggle="sample_toggle" expanded={@family_open} />
            <.family_card
              card={@sample_family_small}
              on_toggle="sample_toggle"
              expanded={@family_open}
            />
          </div>
        </.example>

        <.example
          :let={theme}
          id="source_entry"
          title="source_entry"
          code={
            ~S'''
            <.source_entry id="s-1" year={1959} title="Cynipid galls of the eastern United States"
                           href={~p"/source/1"} authors="LH Weld" excerpt={text}
                           license="Public Domain / CC0" original_url={url} />
            <.source_entry id="notes" title="Gallformers ID Notes" excerpt={notes} pinned />
            '''
          }
        >
          <div class="flex flex-col gap-2">
            <.source_entry
              id={"notes-#{theme}"}
              title="Gallformers ID Notes"
              year="2026"
              excerpt="Old or damaged specimens of C quercuscornigera are difficult if not impossible to distinguish from C quercuspunctata by gall morphology alone."
              license="Public Domain / CC0"
              pinned
            />
            <.source_entry
              id={"weld-#{theme}"}
              year={1959}
              title="Cynipid galls of the eastern United States"
              href="#"
              authors="LH Weld"
              excerpt={@sample_excerpt}
              license="Public Domain / CC0"
              original_url="https://www.biodiversitylibrary.org/"
            />
            <.source_entry
              id={"felt-#{theme}"}
              year={1940}
              title="Plant Galls and Gall Makers"
              href="#"
              authors="EP Felt"
              excerpt="Irregular, ovoid, horned woody twig and branch galls, dia. 1–3 cm. Adults in April."
              license="CC-BY"
            />
          </div>
        </.example>

        <.example
          id="source_quote"
          title="source_quote"
          code={
            ~S'''
            <.source_quote page="p. 113">Woody knots on the limbs, emitting pale yellow, conical, brittle projections.</.source_quote>
            <.source_quote inline>abrupt swelling</.source_quote>
            '''
          }
        >
          <.source_quote page="p. 113">
            <p>Woody knots on the limbs, emitting pale yellow, conical, brittle projections.</p>
          </.source_quote>
          <p class="text-ui">
            The Source calls its form an <.source_quote inline>abrupt swelling</.source_quote>.
          </p>
        </.example>

        <.example
          :let={theme}
          id="field"
          title="field"
          code={
            ~S'''
            <.field label="Accepted name" for="taxon-name" layout={:row} help="The old name is kept as a synonym." saved>
              <input id="taxon-name" aria-describedby="taxon-name-help" … />
            </.field>
            '''
          }
        >
          <div class="gf-density-working flex flex-col gap-3">
            <.field
              label="Accepted name"
              for={"fname-#{theme}"}
              layout={:row}
              help="The old name is kept as a synonym. Galls whose names it changes get rename proposals."
              saved
            >
              <input
                id={"fname-#{theme}"}
                value="Acanthaceae"
                aria-describedby={"fname-#{theme}-help"}
                class="h-ctl w-full rounded-ctl border border-line-strong bg-surface px-3 text-ui text-ink"
              />
            </.field>
            <.field
              label="Synonym"
              for={"fsyn-#{theme}"}
              layout={:row}
              errors={["That name is already a synonym of Quercus rubra. Search for it instead."]}
              required
            >
              <input
                id={"fsyn-#{theme}"}
                value="Quercus borealis"
                aria-invalid="true"
                aria-describedby={"fsyn-#{theme}-errors"}
                class="h-ctl w-full rounded-ctl border border-danger bg-surface px-3 text-ui text-ink"
              />
            </.field>
          </div>
        </.example>

        <.example
          :let={theme}
          id="search_field"
          title="search_field"
          code={
            ~S'''
            <.search_field id="gall-search" name="q" value={@query} label="Search Galls"
                           placeholder="Name or Host" shortcut="/" on_clear={JS.push("clear")} phx-change="search" />
            '''
          }
        >
          <div class="grid gap-3 sm:grid-cols-2">
            <.search_field
              id={"sf1-#{theme}"}
              name="q"
              label="Search"
              placeholder="Search galls, hosts, sources"
              shortcut="/"
            />
            <.search_field
              id={"sf2-#{theme}"}
              name="q2"
              label="Filter by name"
              value="quercus"
              on_clear={JS.push("noop")}
            />
          </div>
        </.example>

        <.example
          :let={theme}
          id="facet_group"
          title="facet_group"
          code={
            ~S'''
            <form phx-change="filter">
              <.facet_group id="facet-part" title="Plant part" name="plant_part" options={@part_options} limit={5} />
            </form>
            '''
          }
        >
          <form class="max-w-64">
            <.facet_group
              id={"fg-#{theme}"}
              title="Plant part"
              name="plant_part"
              limit={4}
              options={@sample_facet}
            />
          </form>
        </.example>

        <.example
          id="filter_select"
          title="filter_select"
          code={
            ~S'''
            <.filter_select id="filter-season" name="season" label="Season" prompt="Any season"
                            options={[{"Spring", "spring"}, {"Summer", "summer"}]} value={@season}
                            counts={%{"spring" => 41, "summer" => 22}}
                            phx-change="change_filter" phx-value-filter="season" />
            '''
          }
        >
          <div class="grid max-w-xl gap-4 sm:grid-cols-2">
            <.filter_select
              id="fs-unset"
              name="season"
              label="Season"
              prompt="Any season"
              options={[{"Spring", "spring"}, {"Summer", "summer"}, {"Fall", "fall"}]}
              counts={%{"spring" => 41, "summer" => 22, "fall" => 12}}
            />
            <.filter_select
              id="fs-set"
              name="detachable"
              label="Detachable"
              prompt="Either"
              options={[{"Integral", "integral"}, {"Detachable", "detachable"}]}
              value="detachable"
            />
          </div>
        </.example>

        <.example
          id="notice"
          title="notice"
          code={
            ~S'''
            <.notice kind={:danger} title="Not saved">That name is already a synonym of <em>Quercus rubra</em>.</.notice>
            '''
          }
        >
          <div class="flex flex-col gap-2">
            <.notice>Where the Hosts grow, not where the Gall was found.</.notice>
            <.notice kind={:ok}>Approved 9 notes.</.notice>
            <.notice kind={:warn} title="Holds approval">
              Leaving this open holds the Source's Gall statements.
            </.notice>
            <.notice kind={:danger} title="Not saved">
              That name is already a synonym of <em>Quercus rubra</em>. Search for it instead.
            </.notice>
          </div>
        </.example>

        <.example
          :let={theme}
          id="dialog"
          title="dialog"
          code={
            ~S'''
            <.button variant="danger" phx-click={show_dialog("delete-taxon")}>Delete taxon</.button>
            <.dialog id="delete-taxon" size={:sm} title="Delete the taxon Acanthaceae?" on_cancel={hide_dialog("delete-taxon")}>
              Its 3 synonyms are deleted with it.
              <:actions>
                <.button phx-click={hide_dialog("delete-taxon")}>Cancel</.button>
                <.button variant="danger" phx-click="delete">Delete taxon</.button>
              </:actions>
            </.dialog>
            '''
          }
        >
          <div>
            <.button variant="danger" icon="ph-trash" phx-click={show_dialog("dlg-#{theme}")}>
              Delete taxon
            </.button>
            <.dialog
              id={"dlg-#{theme}"}
              size={:sm}
              title="Delete the taxon Acanthaceae?"
              on_cancel={hide_dialog("dlg-#{theme}")}
            >
              <p class="text-body text-ink-2">
                Its 3 synonyms are deleted with it. This can't be undone.
              </p>
              <:actions>
                <.button phx-click={hide_dialog("dlg-#{theme}")}>Cancel</.button>
                <.button variant="danger" phx-click={hide_dialog("dlg-#{theme}")}>
                  Delete taxon
                </.button>
              </:actions>
            </.dialog>
          </div>
        </.example>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def handle_event("sample_view", %{"view" => view}, socket),
    do: {:noreply, assign(socket, sample_view: view)}

  def handle_event("sample_choice", %{"choice" => choice}, socket),
    do: {:noreply, assign(socket, sample_choice: choice)}

  def handle_event("sample_select", %{"id" => id}, socket) do
    id = String.to_integer(id)
    selected = socket.assigns.sample_selected

    selected =
      if MapSet.member?(selected, id),
        do: MapSet.delete(selected, id),
        else: MapSet.put(selected, id)

    {:noreply, assign(socket, sample_selected: selected)}
  end

  def handle_event("sample_select_all", _params, socket) do
    selected = if MapSet.size(socket.assigns.sample_selected) == 2, do: [], else: [1, 2]
    {:noreply, assign(socket, sample_selected: MapSet.new(selected))}
  end

  def handle_event("noop", _params, socket), do: {:noreply, socket}

  def handle_event("sample_toggle", %{"key" => key}, socket) do
    {:noreply,
     assign(socket,
       family_open: GallformersWeb.BrowseHelpers.toggle_set(socket.assigns.family_open, key)
     )}
  end

  defp sample_family do
    genera =
      for {name, count} <- [
            {"Unknown (Cynipini)", 337},
            {"Neuroterus", 136},
            {"Andricus", 126},
            {"Callirhytis", 104},
            {"Amphibolips", 74},
            {"Disholcaspis", 64},
            {"Feron", 48}
          ] do
        %{
          key: "g-" <> name,
          name: name,
          url: "/genus/" <> name,
          count: count,
          leaves: [%{key: "s-1", id: 1, label: name <> " sample (agamic)", url: "/gall/1"}]
        }
      end

    %{
      key: "f-1",
      name: "Cynipidae",
      url: "/family/Cynipidae",
      description: "Gall wasps",
      count: 1361,
      image_url: nil,
      genera: genera
    }
  end

  # A component example: rendered in light and dark, with its usage.
  attr :id, :string, required: true
  attr :title, :string, required: true
  attr :code, :string, required: true
  slot :inner_block, required: true

  defp example(assigns) do
    ~H"""
    <.section id={@id} title={@title}>
      <div class="flex flex-col gap-3">
        <.both :let={theme}>{render_slot(@inner_block, theme)}</.both>
        <pre class="overflow-x-auto rounded-panel border border-line bg-surface-2 p-panel text-meta text-ink-2"><code>{String.trim(@code)}</code></pre>
      </div>
    </.section>
    """
  end

  # Renders its content in a light panel and a dark panel, side by side on
  # wide screens. The slot receives "light" or "dark" (for unique ids).
  slot :inner_block, required: true

  defp both(assigns) do
    ~H"""
    <div class="grid gap-3 xl:grid-cols-2">
      <div
        :for={theme <- ["light", "dark"]}
        data-theme={theme}
        class="flex flex-col gap-2 rounded-panel border border-line bg-paper p-panel text-ink"
      >
        <span class="text-caption font-semibold uppercase tracking-wide text-muted">{theme}</span>
        {render_slot(@inner_block, theme)}
      </div>
    </div>
    """
  end
end
