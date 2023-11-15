defmodule Zeph.Server do
  use GenServer
  require Logger

  alias Zeph.Zephyr

  def start_link(init) do
    name = Keyword.fetch!(init, :name)
    Logger.info("LLM Server name: #{inspect(name)}")
    GenServer.start_link(__MODULE__, :ok, name: name)
  end

  @doc """
  Submit a request to the LLM Server. Sent as a cast.
  """
  def submit_prompt(text, server \\ Zeph.LlmModel) do
    GenServer.cast(server, {:run_prompt, text, self()})
  end

  def get_response() do
    receive do
      {:zephyr_result, value} ->
        {:ok, value}
    after
      10_000 ->
        {:error, "No response after waiting 10 seconds."}
    end
  end

  # Server (callbacks)

  @impl true
  def init(:ok) do
    mode = Application.get_env(:zeph, :zephyr_mode)
    Logger.info("Zephyr LLM mode #{inspect(mode)}")
    {:ok, %{serving: nil, mode: mode}, {:continue, nil}}
  end

  @impl true
  def handle_continue(_, state) do
    Logger.info("LLM Server 'serving' getting started...")

    new_state =
      case state do
        %{mode: :live} ->
          # load the model (big and slow)
          serving = Zephyr.serving()
          Map.put(state, :serving, serving)

        _other ->
          state
      end

    {:noreply, new_state}
  end

  @impl true
  def handle_cast({:run_prompt, text, from}, %{mode: :live} = state) do
    Logger.info("LLM Server: live prompt request running...")
    {time, result} = :timer.tc(Nx.Serving, :run, [state[:serving], text])
    in_ms = time / 1_000
    Logger.info("LLM Server: generated response in #{inspect(in_ms)} msec")

    %{results: [%{text: text}]} = result
    send(from, {:zephyr_result, text, in_ms})
    {:noreply, state}
  end

  def handle_cast({:run_prompt, text, from}, %{mode: :echo} = state) do
    Logger.info("LLM Server: Echoing prompt run request - DUMMY RESPONSE")
    send(from, {:zephyr_result, text <> " echo", 0})
    {:noreply, state}
  end
end
