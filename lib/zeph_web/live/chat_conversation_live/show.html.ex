defmodule ZephWeb.ChatConversationLive.Show do
  use ZephWeb, :live_view
  alias LangChain.Message
  alias LangChain.ChatModels.ChatZephyr
  # alias LangChain.ChatModels.ChatOpenAI
  alias LangChain.Chains.LLMChain
  alias Phoenix.LiveView.AsyncResult

  # what doesn't work:
  # - varied output. The seed is set when the serving is created. https://github.com/elixir-nx/bumblebee/issues/284
  # - cancelling - we can kill the process handling the stream, but the GPU could keep going until finished or it reaches the token limit
  # - system settings can be easily overridden by the user making it do whatever they want.
  # - no function support

  @system_prompt "You are a helpful assistant."

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:messages, [])
      |> append_message(Message.new_system!(@system_prompt))
      |> assign_llm_chain()
      |> assign(:async_result, %AsyncResult{})

    {:ok, socket}
  end

  @impl true
  def handle_params(params, _, socket) do
    {:noreply,
     socket
     |> assign(:form, to_form(%{}, as: "message"))
     |> apply_action(socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :show, _params) do
    socket
    |> assign(:page_title, "Chat Conversation with Zephyr")
    |> assign(:message, nil)
  end

  @impl true
  def handle_event("validate", %{"message" => message_params}, socket) do
    changeset =
      %Message{}
      |> Message.changeset(message_params)
      |> Map.put(:action, :validate)

    {:noreply, assign_form(socket, changeset)}
  end

  def handle_event("save", %{"message" => %{"content" => content}}, socket) do
    case Message.new_user(content) do
      {:ok, %Message{} = message} ->
        # add to the end of the messages
        {:noreply,
         socket
         |> append_message(message)
         # re-build the chain based on the current messages
         |> assign_llm_chain()
         |> run_chain()
         |> put_flash(:info, "Message sent successfully")
         # reset the changeset
         |> assign_form(Message.changeset(%Message{}, %{}))}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  # # cancel the async process
  # def handle_event("cancel", _params, socket) do
  #   socket =
  #     socket
  #     |> cancel_async(:running_llm)
  #     |> assign(:async_result, %AsyncResult{})
  #     |> put_flash(:info, "Cancelled")
  #     |> close_pending_as_cancelled()

  #   {:noreply, socket}
  # end

  # handles async function returning a successful result
  def handle_async(:running_llm, {:ok, :ok = _success_result}, socket) do
    # discard the result of the successful async function. The side-effects are
    # what we want.
    socket =
      socket
      |> assign(:async_result, AsyncResult.ok(%AsyncResult{}, :ok))

    {:noreply, socket}
  end

  # handles async function returning an error as a result
  def handle_async(:running_llm, {:ok, {:error, reason}}, socket) do
    socket =
      socket
      |> put_flash(:error, reason)
      |> assign(:async_result, AsyncResult.failed(%AsyncResult{}, reason))

    # |> close_pending_as_cancelled()

    {:noreply, socket}
  end

  # handles async function exploding
  def handle_async(:running_llm, {:exit, reason}, socket) do
    socket =
      socket
      |> put_flash(:error, "Call failed: #{inspect(reason)}")
      |> assign(:async_result, %AsyncResult{})

    # |> close_pending_as_cancelled()

    {:noreply, socket}
  end

  @impl true
  def handle_info({:chat_response, %LangChain.MessageDelta{} = delta}, socket) do
    updated_chain = LLMChain.apply_delta(socket.assigns.llm_chain, delta)
    {:noreply, assign(socket, :llm_chain, updated_chain)}
  end

  def handle_info({:chat_response, %LangChain.Message{} = message}, socket) do
    socket =
      socket
      |> append_message(message)
      |> assign_llm_chain()
      |> flash_error_if_stopped_for_limit()

    {:noreply, socket}
  end

  defp assign_form(socket, %Ecto.Changeset{} = changeset) do
    assign(socket, :form, to_form(changeset))
  end

  defp role_icon(:system), do: "hero-cloud-solid"
  defp role_icon(:user), do: "hero-user-solid"
  defp role_icon(:assistant), do: "fa-user-robot"
  defp role_icon(:function_call), do: "fa-function"
  defp role_icon(:function), do: "fa-function"

  # Support both %Message{} and %MessageDelta{}
  defp message_block_classes(%{role: :system} = _message) do
    "bg-blue-50 text-blue-700 rounded-t-xl"
  end

  defp message_block_classes(%{role: :user} = _message) do
    "bg-white text-gray-600 font-medium"
  end

  defp message_block_classes(%{status: :length, role: :assistant} = _message) do
    "bg-red-50 text-red-800 font-medium"
  end

  defp message_block_classes(%{status: :cancelled, role: :assistant} = _message) do
    "bg-yellow-50 text-yellow-800 font-medium"
  end

  defp message_block_classes(%{role: :assistant} = _message) do
    "bg-gray-50 text-gray-600 font-medium"
  end

  # append a message to the tracked list of messages
  defp append_message(socket, %Message{} = message) do
    messages = socket.assigns.messages ++ [message]
    assign(socket, :messages, messages)
  end

  defp flash_error_if_stopped_for_limit(
         %{assigns: %{llm_chain: %LLMChain{last_message: %LangChain.Message{status: :length}}}} =
           socket
       ) do
    put_flash(socket, :error, "Stopped for limit")
  end

  defp flash_error_if_stopped_for_limit(socket) do
    socket
  end

  defp assign_llm_chain(socket) do
    messages = socket.assigns.messages

    llm_chain =
      LLMChain.new!(%{
        llm:
          ChatZephyr.new!(%{
            serving: ZephyrModel,
            receive_timeout: 60_000 * 2,
            stream: true
          }),
        verbose: false
      })
      |> LLMChain.add_messages(messages)

    assign(socket, :llm_chain, llm_chain)
  end

  def run_chain(socket) do
    chain = socket.assigns.llm_chain
    live_view_pid = self()

    callback_fn = fn
      %LangChain.MessageDelta{} = delta ->
        send(live_view_pid, {:chat_response, delta})

      %LangChain.Message{} = message ->
        send(live_view_pid, {:chat_response, message})
    end

    socket
    |> assign(:async_result, AsyncResult.loading())
    |> start_async(:running_llm, fn ->
      case LLMChain.run(chain, callback_fn: callback_fn) do
        # return the errors for display
        {:error, reason} ->
          {:error, reason}

        # Don't return a large success result. The callbacks return what we
        # want.
        _other ->
          :ok
      end
    end)
  end
end
