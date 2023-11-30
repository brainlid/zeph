defmodule Zeph.Zephyr do
  # https://twitter.com/ThinkingElixir/status/1718001978192875730

  # https://github.com/toranb/pgvector-search/blob/mistral7b/lib/search_web/live/page_live.ex#L44
  def serving() do
    mistral = {:hf, "HuggingFaceH4/zephyr-7b-beta"}

    {:ok, spec} =
      Bumblebee.load_spec(mistral,
        module: Bumblebee.Text.Mistral,
        architecture: :for_causal_language_modeling
      )

    {:ok, model_info} = Bumblebee.load_model(mistral, spec: spec)

    {:ok, tokenizer} = Bumblebee.load_tokenizer(mistral, module: Bumblebee.Text.LlamaTokenizer)

    {:ok, generation_config} =
      Bumblebee.load_generation_config(mistral, spec_module: Bumblebee.Text.Mistral)

    generation_config =
      Bumblebee.configure(generation_config,
        max_new_tokens: 500,
        strategy: %{type: :multinomial_sampling, top_p: 0.6}
      )

    Bumblebee.Text.generation(model_info, tokenizer, generation_config,
      compile: [batch_size: 1, sequence_length: 2048],
      stream: true,
      # stream: false,
      defn_options: [compiler: EXLA, lazy_transfers: :never]
      # preallocate_params: true
    )
  end
end
