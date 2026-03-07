defmodule GallformersWeb.Schemas do
  @moduledoc """
  OpenAPI schemas for the Gallformers API.
  """

  alias OpenApiSpex.Schema

  defmodule Error do
    @moduledoc false
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "Error",
      type: :object,
      properties: %{
        error: %Schema{type: :string, description: "Error message"}
      },
      required: [:error],
      example: %{error: "Resource not found"}
    })
  end

  defmodule Alias do
    @moduledoc false
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "Alias",
      description: "An alternative name for a species",
      type: :object,
      properties: %{
        id: %Schema{type: :integer},
        name: %Schema{type: :string},
        type: %Schema{type: :string},
        description: %Schema{type: :string, nullable: true}
      },
      required: [:id, :name],
      example: %{id: 1, name: "Common Oak Gall", type: "common", description: nil}
    })
  end

  defmodule Host do
    @moduledoc false
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "Host",
      description: "A host plant for a gall",
      type: :object,
      properties: %{
        id: %Schema{type: :integer},
        name: %Schema{type: :string}
      },
      required: [:id, :name],
      example: %{id: 42, name: "Quercus alba"}
    })
  end

  defmodule FilterField do
    @moduledoc false
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "FilterField",
      description: "A filter field value (color, shape, texture, etc.)",
      type: :object,
      properties: %{
        id: %Schema{type: :integer},
        field: %Schema{type: :string},
        description: %Schema{type: :string, nullable: true}
      },
      required: [:id, :field],
      example: %{id: 1, field: "green", description: nil}
    })
  end

  defmodule Gall do
    @moduledoc false
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "Gall",
      description: "A gall-forming species",
      type: :object,
      properties: %{
        id: %Schema{type: :integer},
        name: %Schema{type: :string},
        gall_id: %Schema{type: :integer},
        datacomplete: %Schema{type: :boolean},
        abundance_id: %Schema{type: :integer, nullable: true},
        abundance: %Schema{type: :string, nullable: true},
        detachable: %Schema{
          type: :string,
          enum: ["unknown", "integral", "detachable", "both"],
          nullable: true
        },
        undescribed: %Schema{type: :boolean},
        aliases: %Schema{type: :array, items: GallformersWeb.Schemas.Alias},
        hosts: %Schema{type: :array, items: GallformersWeb.Schemas.Host},
        colors: %Schema{type: :array, items: GallformersWeb.Schemas.FilterField},
        shapes: %Schema{type: :array, items: GallformersWeb.Schemas.FilterField},
        textures: %Schema{type: :array, items: GallformersWeb.Schemas.FilterField},
        plant_parts: %Schema{type: :array, items: GallformersWeb.Schemas.FilterField},
        alignments: %Schema{type: :array, items: GallformersWeb.Schemas.FilterField},
        walls: %Schema{type: :array, items: GallformersWeb.Schemas.FilterField},
        cells: %Schema{type: :array, items: GallformersWeb.Schemas.FilterField},
        seasons: %Schema{type: :array, items: GallformersWeb.Schemas.FilterField},
        forms: %Schema{type: :array, items: GallformersWeb.Schemas.FilterField},
        places: %Schema{type: :array, items: %Schema{type: :string}}
      },
      required: [:id, :name, :gall_id, :undescribed]
    })
  end

  defmodule GallListResponse do
    @moduledoc false
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "GallListResponse",
      description: "Paginated list of galls",
      type: :object,
      properties: %{
        data: %Schema{type: :array, items: GallformersWeb.Schemas.Gall},
        total: %Schema{type: :integer},
        limit: %Schema{type: :integer, nullable: true},
        offset: %Schema{type: :integer}
      },
      required: [:data, :total, :offset]
    })
  end

  defmodule Image do
    @moduledoc false
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "Image",
      description: "An image for a species",
      type: :object,
      properties: %{
        id: %Schema{type: :integer},
        path: %Schema{type: :string},
        url: %Schema{type: :string},
        default: %Schema{type: :boolean},
        creator: %Schema{type: :string, nullable: true},
        attribution: %Schema{type: :string, nullable: true},
        sourcelink: %Schema{type: :string, nullable: true},
        license: %Schema{type: :string, nullable: true},
        licenselink: %Schema{type: :string, nullable: true},
        caption: %Schema{type: :string, nullable: true}
      },
      required: [:id, :path, :url]
    })
  end

  defmodule HostResponse do
    @moduledoc false
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "HostResponse",
      description: "A host plant species",
      type: :object,
      properties: %{
        id: %Schema{type: :integer},
        name: %Schema{type: :string},
        taxoncode: %Schema{type: :string},
        datacomplete: %Schema{type: :boolean},
        places: %Schema{type: :array, items: %Schema{type: :string}},
        galls: %Schema{
          type: :array,
          items: %Schema{
            type: :object,
            properties: %{
              id: %Schema{type: :integer},
              name: %Schema{type: :string},
              undescribed: %Schema{type: :boolean}
            }
          }
        }
      },
      required: [:id, :name]
    })
  end

  defmodule HostListResponse do
    @moduledoc false
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "HostListResponse",
      description: "Paginated list of hosts",
      type: :object,
      properties: %{
        data: %Schema{type: :array, items: GallformersWeb.Schemas.HostResponse},
        total: %Schema{type: :integer},
        limit: %Schema{type: :integer, nullable: true},
        offset: %Schema{type: :integer}
      },
      required: [:data, :total, :offset]
    })
  end

  defmodule Taxonomy do
    @moduledoc false
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "Taxonomy",
      description: "A taxonomy entry (family, genus, or section)",
      type: :object,
      properties: %{
        id: %Schema{type: :integer},
        name: %Schema{type: :string},
        type: %Schema{type: :string, enum: ["family", "genus", "section"]},
        description: %Schema{type: :string, nullable: true},
        parent_id: %Schema{type: :integer, nullable: true}
      },
      required: [:id, :name, :type]
    })
  end

  defmodule Source do
    @moduledoc false
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "Source",
      description: "A scientific reference/citation",
      type: :object,
      properties: %{
        id: %Schema{type: :integer},
        title: %Schema{type: :string},
        author: %Schema{type: :string, nullable: true},
        pubyear: %Schema{type: :string, nullable: true},
        link: %Schema{type: :string, nullable: true},
        citation: %Schema{type: :string, nullable: true},
        datacomplete: %Schema{type: :boolean}
      },
      required: [:id, :title]
    })
  end

  defmodule SourceDetail do
    @moduledoc false
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "SourceDetail",
      description: "A scientific source with species-specific context",
      type: :object,
      properties: %{
        id: %Schema{type: :integer},
        title: %Schema{type: :string},
        author: %Schema{type: :string, nullable: true},
        pubyear: %Schema{type: :integer, nullable: true},
        link: %Schema{type: :string, nullable: true},
        citation: %Schema{type: :string, nullable: true},
        description: %Schema{type: :string, nullable: true},
        externallink: %Schema{type: :string, nullable: true}
      },
      required: [:id, :title]
    })
  end

  defmodule GallListItem do
    @moduledoc false
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "GallListItem",
      description: "A gall species summary",
      type: :object,
      properties: %{
        id: %Schema{type: :integer},
        name: %Schema{type: :string},
        undescribed: %Schema{type: :boolean, nullable: true},
        datacomplete: %Schema{type: :boolean, nullable: true}
      },
      required: [:id, :name]
    })
  end

  defmodule GeneraListResponse do
    @moduledoc false
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "GeneraListResponse",
      description: "Paginated list of genera",
      type: :object,
      properties: %{
        data: %Schema{type: :array, items: GallformersWeb.Schemas.Taxonomy},
        total: %Schema{type: :integer},
        limit: %Schema{type: :integer, nullable: true},
        offset: %Schema{type: :integer}
      },
      required: [:data, :total, :offset]
    })
  end

  defmodule Glossary do
    @moduledoc false
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "Glossary",
      description: "A glossary term and definition",
      type: :object,
      properties: %{
        id: %Schema{type: :integer},
        word: %Schema{type: :string},
        definition: %Schema{type: :string},
        urls: %Schema{type: :string, nullable: true}
      },
      required: [:id, :word, :definition]
    })
  end

  defmodule Place do
    @moduledoc false
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "Place",
      description: "A geographic place (state, province, etc.)",
      type: :object,
      properties: %{
        id: %Schema{type: :integer},
        name: %Schema{type: :string},
        code: %Schema{type: :string},
        type: %Schema{type: :string},
        parent_id: %Schema{type: :integer, nullable: true}
      },
      required: [:id, :name, :code, :type]
    })
  end

  defmodule SearchResults do
    @moduledoc false
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "SearchResults",
      description: "Global search results grouped by type",
      type: :object,
      properties: %{
        galls: %Schema{type: :array, items: %Schema{type: :object}},
        hosts: %Schema{type: :array, items: %Schema{type: :object}},
        glossary: %Schema{type: :array, items: %Schema{type: :object}},
        sources: %Schema{type: :array, items: %Schema{type: :object}},
        taxonomy: %Schema{type: :array, items: %Schema{type: :object}},
        places: %Schema{type: :array, items: %Schema{type: :object}}
      }
    })
  end

  defmodule Stats do
    @moduledoc false
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "Stats",
      description: "Summary statistics about the database",
      type: :object,
      properties: %{
        galls: %Schema{type: :integer},
        hosts: %Schema{type: :integer},
        sources: %Schema{type: :integer},
        glossary: %Schema{type: :integer},
        undescribed_galls: %Schema{type: :integer},
        images: %Schema{type: :integer}
      }
    })
  end
end
