defmodule ZephWeb.TextCompletionLive.Index do
  use ZephWeb, :live_view
  require Logger
  alias Phoenix.LiveView.AsyncResult

  @impl true
  def mount(_params, _session, socket) do
    initial = ~S"""
    <|system|>
    You are a helpful assistant.
    <|user|>
    What is the capital of Switzerland?
    <|assistant|>
    """

    socket =
      socket
      |> assign(:text, "")
      |> assign(:async_result, %AsyncResult{})
      |> assign_form(%{"content" => initial})

    {:ok, socket}
  end

  # handles async function returning a successful result
  def handle_async(:text_completion, {:ok, {:zephyr_result, _text, ms}}, socket) do
    # discard the result of the successful async function. The side-effects are
    # what we want.
    socket =
      socket
      |> assign(:async_result, AsyncResult.ok(%AsyncResult{}, :ok))
      # |> assign(:text, text)
      |> put_flash(:info, "Finished in #{ms} msec")

    {:noreply, socket}
  end

  # handles async function exploding
  def handle_async(:text_completion, {:exit, reason}, socket) do
    socket =
      socket
      |> put_flash(:error, "Call failed: #{inspect(reason)}")
      |> assign(:async_result, %AsyncResult{})

    {:noreply, socket}
  end

  @impl true
  def handle_info({:streamed, data}, socket) do
    socket =
      socket
      |> assign(:text, socket.assigns.text <> data)

    {:noreply, socket}
  end

  @impl true
  # start the async process
  def handle_event("validate", %{"message" => params}, socket) do
    {:noreply, assign_form(socket, params)}
  end

  def handle_event("save", %{"message" => %{"content" => content} = _params}, socket) do
    Logger.info("LiveView submitting text prompt to LLM Serving")
    lv_pid = self()

    socket =
      socket
      |> assign(:async_result, AsyncResult.loading())
      |> assign(:text, "")
      |> start_async(:text_completion, fn ->
        {time, result} = :timer.tc(Nx.Serving, :batched_run, [ZephyrModel, content])
        Enum.each(result, fn value ->
          send(lv_pid, {:streamed, value})
        end)
        in_ms = time / 1_000
        Logger.info("LLM Server: generated response in #{inspect(in_ms)} msec")
        # %{results: [%{text: text}]} = result

        {:zephyr_result, "", in_ms}
      end)

    {:noreply, socket}
  end

  defp assign_form(socket, %{"content" => content} = params) do
    content = String.trim(content)

    errors =
      case content do
        "" ->
          [content: {"Can't be blank", []}]

        _other ->
          []
      end

    assign(socket, :form, to_form(params, as: :message, errors: errors))
  end
end
