# .credo.exs
%{
  configs: [
    %{
      name: "default",
      files: %{
        included: [
          "lib/",
          "test/"
        ],
        excluded: [~r"/_build/", ~r"/deps/", ~r"/node_modules/"]
      },
      plugins: [],
      requires: ["dev/credo/"],
      strict: false,
      parse_timeout: 5000,
      color: true,
      checks: %{
        enabled: [
          # Consistency checks
          {Credo.Check.Consistency.ExceptionNames, []},
          {Credo.Check.Consistency.LineEndings, []},
          {Credo.Check.Consistency.ParameterPatternMatching, []},
          {Credo.Check.Consistency.SpaceAroundOperators, []},
          {Credo.Check.Consistency.SpaceInParentheses, []},
          {Credo.Check.Consistency.TabsOrSpaces, []},

          # Design checks
          {Credo.Check.Design.AliasUsage,
           [
             priority: :low,
             if_nested_deeper_than: 2,
             if_called_more_often_than: 0,
             files: %{excluded: ["test/support/"]}
           ]},
          {Credo.Check.Design.TagTODO, [exit_status: 0]},
          {Credo.Check.Design.TagFIXME, []},
          {Credo.Check.Design.SkipTestWithoutComment, []},

          # Architecture checks (custom — only scan lib/, not test/)
          {Gallformers.Credo.Checks.Architecture.NoRepoInWeb,
           files: %{
             included: ["lib/"],
             excluded: [
               "lib/gallformers_web/controllers/health_controller.ex",
               "lib/gallformers_web/controllers/sitemap_controller.ex"
             ]
           }},
          {Gallformers.Credo.Checks.Architecture.NoTransactionOutsideContext,
           files: %{included: ["lib/"]}},
          {Gallformers.Credo.Checks.Architecture.NoEctoQueryInLiveView,
           files: %{
             included: ["lib/"],
             excluded: ["lib/gallformers_web/controllers/sitemap_controller.ex"]
           }},
          {Gallformers.Credo.Checks.Architecture.NoMockingLibraries, []},

          # One entry point per capability (matter c800). This is the one
          # place the owners live; change them only by deciding to. Pending
          # callers predate the check: the list only shrinks.
          {Gallformers.Credo.Checks.Architecture.SingleEntryPoint,
           capabilities: [
             %{
               name: "WCVP name search",
               calls: [
                 {Gallformers.Wcvp.Lookup, [:search, :search_contains]},
                 {:wcvp_lookup, [:search, :search_contains]}
               ],
               scope: "lib/gallformers_web/",
               owners: [GallformersWeb.Choices],
               pending: [
                 {GallformersWeb.Admin.ReviewLive.Answer, "b230"},
                 {GallformersWeb.Admin.TaxonomyLive.New, "b230"},
                 {GallformersWeb.Admin.TaxonomyLive.RangeEditor, "b230"}
               ]
             },
             %{
               name: "iNat taxon search",
               calls: [
                 {Gallformers.Import, [:search_inat_taxa]},
                 {Gallformers.INaturalist.Taxa, [:search]}
               ],
               scope: "lib/gallformers_web/",
               owners: [GallformersWeb.Choices],
               pending: [
                 {GallformersWeb.Admin.ReviewLive.Answer, "b230"},
                 {GallformersWeb.Admin.InatTaxonPanel, "b230"}
               ]
             },
             %{
               name: "Host choices",
               calls: [{Gallformers.Taxa, [:host_choices]}],
               scope: "lib/gallformers_web/",
               owners: [GallformersWeb.Choices],
               pending: [{GallformersWeb.Admin.ReviewLive.Answer, "b230"}]
             },
             %{
               name: "Review decisions",
               calls: [{Gallformers.Import, [:decide_queue_item, :decide_group]}],
               scope: "lib/gallformers_web/",
               owners: [GallformersWeb.Admin.ReviewLive.Answer],
               pending: [{GallformersWeb.Admin.ReviewLive.Review, "b230"}]
             },
             %{
               name: "Taxon creation",
               calls: [{Gallformers.Taxa, [:create_taxon]}],
               scope: "lib/",
               owners: [
                 Gallformers.Import,
                 Gallformers.Import.ApplyTaxonomy,
                 Gallformers.CatalogMigration.Taxa
               ],
               pending: []
             }
           ]},

          # Test quality checks (custom — only scan test/)
          # FlashOnlyAssertions and TestsOwnTheirData disabled until b016 remediation
          # {Gallformers.Credo.Checks.TestQuality.FlashOnlyAssertions,
          #  files: %{included: ["test/"]}},
          {Gallformers.Credo.Checks.TestQuality.NoHardcodedIds, files: %{included: ["test/"]}},
          {Gallformers.Credo.Checks.TestQuality.NoBareTruthinessAssert,
           files: %{included: ["test/"]}},
          {Gallformers.Credo.Checks.TestQuality.TestsOwnTheirData,
           files: %{included: ["test/"], excluded: ["test/prod_data/", "test/e2e/"]}},

          # Readability checks
          {Credo.Check.Readability.AliasOrder, []},
          {Credo.Check.Readability.FunctionNames, []},
          {Credo.Check.Readability.LargeNumbers, []},
          {Credo.Check.Readability.MaxLineLength, [priority: :low, max_length: 120]},
          {Credo.Check.Readability.ModuleAttributeNames, []},
          {Credo.Check.Readability.ModuleDoc, [exit_status: 0]},
          {Credo.Check.Readability.ModuleNames, []},
          {Credo.Check.Readability.ParenthesesOnZeroArityDefs, []},
          {Credo.Check.Readability.PredicateFunctionNames, []},
          {Credo.Check.Readability.PreferImplicitTry, []},
          {Credo.Check.Readability.RedundantBlankLines, []},
          {Credo.Check.Readability.Semicolons, []},
          {Credo.Check.Readability.SpaceAfterCommas, []},
          {Credo.Check.Readability.StringSigils, []},
          {Credo.Check.Readability.TrailingBlankLine, []},
          {Credo.Check.Readability.TrailingWhiteSpace, []},
          {Credo.Check.Readability.UnnecessaryAliasExpansion, []},
          {Credo.Check.Readability.VariableNames, []},
          {Credo.Check.Readability.WithSingleClause, []},

          # Refactoring opportunities
          {Credo.Check.Refactor.Apply, []},
          {Credo.Check.Refactor.CondStatements, []},
          {Credo.Check.Refactor.CyclomaticComplexity, []},
          {Credo.Check.Refactor.FilterCount, []},
          {Credo.Check.Refactor.FilterFilter, []},
          {Credo.Check.Refactor.FunctionArity, []},
          {Credo.Check.Refactor.LongQuoteBlocks, []},
          {Credo.Check.Refactor.MapJoin, []},
          {Credo.Check.Refactor.MatchInCondition, []},
          {Credo.Check.Refactor.NegatedConditionsInUnless, []},
          {Credo.Check.Refactor.NegatedConditionsWithElse, []},
          {Credo.Check.Refactor.Nesting, []},
          {Credo.Check.Refactor.RedundantWithClauseResult, []},
          {Credo.Check.Refactor.RejectReject, []},
          {Credo.Check.Refactor.UnlessWithElse, []},
          {Credo.Check.Refactor.WithClauses, []},

          # Warnings
          {Credo.Check.Warning.ApplicationConfigInModuleAttribute, []},
          {Credo.Check.Warning.BoolOperationOnSameValues, []},
          {Credo.Check.Warning.Dbg, []},
          # Disable ExpensiveEmptyEnumCheck in test files - performance is not critical there
          {Credo.Check.Warning.ExpensiveEmptyEnumCheck, [files: %{excluded: [~r"test/"]}]},
          {Credo.Check.Warning.IExPry, []},
          {Credo.Check.Warning.IoInspect, []},
          {Credo.Check.Warning.MixEnv, []},
          {Credo.Check.Warning.OperationOnSameValues, []},
          {Credo.Check.Warning.OperationWithConstantResult, []},
          {Credo.Check.Warning.RaiseInsideRescue, []},
          {Credo.Check.Warning.SpecWithStruct, []},
          {Credo.Check.Warning.UnsafeExec, []},
          {Credo.Check.Warning.UnusedEnumOperation, []},
          {Credo.Check.Warning.UnusedFileOperation, []},
          {Credo.Check.Warning.UnusedKeywordOperation, []},
          {Credo.Check.Warning.UnusedListOperation, []},
          {Credo.Check.Warning.UnusedPathOperation, []},
          {Credo.Check.Warning.UnusedRegexOperation, []},
          {Credo.Check.Warning.UnusedStringOperation, []},
          {Credo.Check.Warning.UnusedTupleOperation, []},
          {Credo.Check.Warning.WrongTestFileExtension, []}
        ],
        disabled: [
          # Disable module doc requirement for now
          {Credo.Check.Readability.ModuleDoc, false}
        ]
      }
    },
    # Copied code (matter c800), checked against a shrink-only baseline by
    # test/gallformers/guardrails/duplicate_code_test.exs rather than by
    # `credo --strict`. See each block with: mix credo --config-name duplicates
    %{
      name: "duplicates",
      files: %{
        included: ["lib/", "test/"],
        excluded: [~r"/_build/", ~r"/deps/", ~r"/node_modules/"]
      },
      checks: %{
        enabled: [
          {Credo.Check.Design.DuplicatedCode, [mass_threshold: 40]}
        ]
      }
    }
  ]
}
