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

  @impl true
  # start the async process
  def handle_event("validate", %{"message" => params}, socket) do
    {:noreply, assign_form(socket, params)}
  end

  def handle_event("save", %{"message" => %{"content" => content} = _params}, socket) do
    Logger.info("LiveView submitting text prompt to LLM Server")
    Zeph.Server.submit_prompt(content)

    socket =
      socket
      |> assign(:async_result, AsyncResult.loading())
      |> assign(:text, "")

    {:noreply, socket}
  end

  # handles async function returning a successful result
  def handle_async(:running_task, {:ok, :ok = _success_result}, socket) do
    # discard the result of the successful async function. The side-effects are
    # what we want.
    socket =
      socket
      |> put_flash(:info, "Completed!")
      |> assign(:async_result, AsyncResult.ok(%AsyncResult{}, :ok))

    {:noreply, socket}
  end

  @impl true
  # handle receiving a message sent from the async process
  def handle_info({:zephyr_result, text, ms}, socket) do
    Logger.info("LiveView received generated text response.")

    socket =
      socket
      |> assign(:text, text)
      |> assign(:async_result, AsyncResult.ok(%AsyncResult{}, :ok))
      |> put_flash(:info, "Finished in #{ms} msec")

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
